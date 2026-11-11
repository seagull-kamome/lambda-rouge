||| The Elm-style update function.
module LambdaRogue.App.Update

import Data.List
import Data.Maybe
import LambdaRogue.App.Canvas
import LambdaRogue.App.Model
import LambdaRogue.App.Settings
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types
import LambdaRogue.Persist.Replay
import LambdaRogue.Persist.Save
import LambdaRogue.Persist.Score
import LambdaRogue.Persist.Settings
import LambdaRogue.UI.Animation
import LambdaRogue.UI.Theme
import TermUI.Program

%default covering

commandFor : ItemAction -> ItemId -> Maybe Command
commandFor QuaffAction iid = Just (Quaff iid)
commandFor ReadAction iid = Just (Read iid)
commandFor EatAction iid = Just (Eat iid)
commandFor WieldAction iid = Just (Wield iid)
commandFor WearAction iid = Just (Wear iid)
commandFor PutOnAction iid = Just (PutOnRing iid)
commandFor TakeOffAction iid = Just (TakeOff iid)
commandFor DropAction iid = Just (Drop iid)
commandFor ZapAction _ = Nothing
commandFor ThrowAction _ = Nothing

closeBrowserState : UiState -> UiState
closeBrowserState ui = { replayBrowserOpen := False, replayError := Nothing } ui

clearPack : Model -> Model
clearPack m =
  { inventoryOpen := False, selectedItem := Nothing,
    inventoryIntent := Nothing, pendingDir := Nothing,
    helpOpen := False, paletteOpen := False,
    scoreOpen := False, shareOpen := False, hover := Nothing,
    ui := closeBrowserState m.ui } m

redraw : Model -> Cmd Msg
redraw m =
  Perform (drawMapAnimated m.theme m.hover m.animations m.canvas m.game
           >> pure Painted)

settingsOf : Model -> Settings
settingsOf m =
  MkSettings m.theme m.animationsEnabled m.ui.animationSpeed
             m.keymap m.language

saveSettingsCmd : Model -> Cmd Msg
saveSettingsCmd m =
  Perform (do _ <- saveSettings (settingsOf m)
              pure Painted)

||| A finished run is appended to the score history and its semantic replay
||| is written beside it.  Both failures are non-fatal: the in-memory score
||| screen remains usable even on a read-only data directory.
persistRun : Score -> Replay -> Cmd Msg
persistRun score replay =
  Perform (do _ <- appendScore score
              _ <- saveReplay replay
              deleteSave
              deleteAutosave
              pure Painted)

autoSaveCmd : Game -> Cmd Msg
autoSaveCmd g =
  Perform (do _ <- autoSave g
              pure Painted)

runCommand : Command -> Model -> (Model, Cmd Msg)
runCommand cmd m =
  if isJust m.game.over || playbackOpen m
     then (m, NoCmd)
     else
       let replay' : Replay
           replay' = recordCommand cmd m.replay
           out = step cmd m.game
           effects : List Effect
           effects = if m.animationsEnabled
                        then mergeAnimations (effectsFor m.game out.game out.events)
                                             m.animations
                        else []
           m0 : Model
           m0 = { game := out.game, replay := replay',
                  animations := effects } (clearPack m)
           m1 : Model
           m1 = case out.game.over of
                  Nothing => m0
                  Just _ =>
                    let verified : Bool
                        verified = replayMatches replay' out.game
                        scores' : List Score
                        scores' = case scoreOf out.game of
                                    Nothing => m0.scores
                                    Just score => score :: m0.scores
                    in { scores := scores', replayOk := Just verified,
                         scoreOpen := True } m0
           finishCmd : Cmd Msg
           finishCmd = case (out.game.over, scoreOf out.game) of
                         (Just _, Just score) => persistRun score replay'
                         _ => redraw m1
           advanced : Bool
           advanced = out.game.turn /= m.game.turn
           shouldAutoSave : Bool
           shouldAutoSave = advanced && out.game.turn `mod` 10 == 0
       in (m1, if isJust out.game.over
                  then Batch [redraw m1, finishCmd]
                  else if shouldAutoSave
                          then Batch [redraw m1, autoSaveCmd out.game]
                          else redraw m1)

runItemAction : ItemAction -> ItemId -> Model -> (Model, Cmd Msg)
runItemAction ZapAction iid m =
  let m' : Model
      m' = { inventoryOpen := False, selectedItem := Nothing,
             inventoryIntent := Nothing, pendingDir := Just (ZapDir iid),
             hover := Nothing } m
  in (m', redraw m')
runItemAction ThrowAction iid m =
  let m' : Model
      m' = { inventoryOpen := False, selectedItem := Nothing,
             inventoryIntent := Nothing, pendingDir := Just (ThrowDir iid),
             hover := Nothing } m
  in (m', redraw m')
runItemAction act iid m =
  case commandFor act iid of
    Nothing => (m, NoCmd)
    Just cmd => runCommand cmd m

advancePlayback : Model -> Model
advancePlayback m =
  case m.playback of
    Nothing => m
    Just pb =>
      case pb.remaining of
        [] => { playback := Just ({ done := True, playing := False } pb) } m
        (cmd :: rest) =>
          let out = step cmd m.game
              played' = S pb.played
              finished = null rest || isJust out.game.over
              effects : List Effect
              effects = if m.animationsEnabled
                           then mergeAnimations
                                  (effectsFor m.game out.game out.events)
                                  m.animations
                           else m.animations
              pb' : Playback
              pb' = { remaining := rest, played := played',
                      done := finished,
                      verified := if finished
                                     then Just (replayMatches pb.replay out.game)
                                     else pb.verified,
                      playing := if finished then False else pb.playing } pb
          in { game := out.game, playback := Just pb', animations := effects } m

||| Begin a visible replay.  `verified` is `Nothing` for a replay read from
||| disk because this run has no recorded final digest to compare against;
||| the flag is filled in when playback reaches its end.
beginPlayback : Replay -> Maybe Bool -> Model -> (Model, Cmd Msg)
beginPlayback r verified m =
  let commands = replayCommands r
      pb : Playback
      pb = MkPlayback m.game r commands 0 (length commands)
                      (not (null commands)) NormalPlayback
                      (null commands) verified m.scoreOpen
      m' : Model
      m' = { game := newGame r.seed, playback := Just pb,
             scoreOpen := False, shareOpen := False, helpOpen := False,
             paletteOpen := False, inventoryOpen := False,
             selectedItem := Nothing, inventoryIntent := Nothing,
             pendingDir := Nothing, hover := Nothing, animations := [],
             ui := closeBrowserState m.ui } m
  in (m', redraw m')

||| Move to command `target` by deterministically replaying the prefix from
||| the recorded seed.  Seeking pauses playback and never edits the replay.
seekPlayback : Nat -> Model -> Model
seekPlayback target m =
  case m.playback of
    Nothing => m
    Just pb =>
      let commandList = replayCommands pb.replay
          count = length commandList
          n = min target count
          replayed : List Command
          replayed = take n commandList
          remaining = drop n commandList
          g = foldl (\gg, c => (step c gg).game) (newGame pb.replay.seed) replayed
          done = null remaining
          pb' : Playback
          pb' = { remaining := remaining, played := n, done := done,
                  playing := False,
                  verified := if done
                                 then Just (replayMatches pb.replay g)
                                 else Nothing } pb
      in { game := g, playback := Just pb', animations := [] } m

nth : Nat -> List a -> Maybe a
nth Z (x :: _) = Just x
nth (S k) (_ :: xs) = nth k xs
nth _ [] = Nothing

public export
update : Msg -> Model -> (Model, Cmd Msg)
update Quit' m =
  (m, Batch [Perform (do deleteAutosave
                         pure Painted), Quit])
update Redraw m = (m, redraw m)
update Painted m = (m, NoCmd)
update (Resized w h) m =
  let m' : Model
      m' = { width := w, height := h } m
  in (m', NoCmd)
update (Do cmd) m = runCommand cmd m
update OpenInventory m =
  let m' : Model
      m' = { inventoryOpen := True, selectedItem := Nothing,
             inventoryIntent := Nothing, helpOpen := False,
             paletteOpen := False, scoreOpen := False, shareOpen := False,
             pendingDir := Nothing, hover := Nothing,
             ui := closeBrowserState m.ui } m
  in (m', NoCmd)
update (OpenInventoryFor act) m =
  let m' : Model
      m' = { inventoryOpen := True, selectedItem := Nothing,
             inventoryIntent := Just act, helpOpen := False,
             paletteOpen := False, scoreOpen := False, shareOpen := False,
             pendingDir := Nothing, hover := Nothing,
             ui := closeBrowserState m.ui } m
  in (m', NoCmd)
update CloseInventory m =
  let m' : Model
      m' = { inventoryOpen := False, selectedItem := Nothing,
             inventoryIntent := Nothing, hover := Nothing } m
  in (m', redraw m')
update (SelectItem iid) m =
  case m.inventoryIntent of
    Just act => runItemAction act iid m
    Nothing =>
      let m' : Model
          m' = { selectedItem := Just iid } m
      in (m', NoCmd)
update (ActOnItem act iid) m = runItemAction act iid m
update (DoItemAction act) m =
  case m.selectedItem of
    Nothing => (m, NoCmd)
    Just iid => runItemAction act iid m
update CancelDirection m =
  let m' : Model
      m' = { pendingDir := Nothing } m
  in (m', NoCmd)
update OpenHelp m =
  let m' : Model
      m' = { helpOpen := True, paletteOpen := False, scoreOpen := False,
             shareOpen := False, inventoryOpen := False,
             selectedItem := Nothing, inventoryIntent := Nothing,
             pendingDir := Nothing, hover := Nothing,
             ui := closeBrowserState m.ui } m
  in (m', NoCmd)
update CloseHelp m =
  let m' : Model
      m' = { helpOpen := False, hover := Nothing } m
  in (m', redraw m')
update OpenPalette m =
  let m' : Model
      m' = { paletteOpen := True, paletteIndex := 0,
             helpOpen := False, scoreOpen := False, shareOpen := False,
             inventoryOpen := False, selectedItem := Nothing,
             inventoryIntent := Nothing, pendingDir := Nothing,
             hover := Nothing, ui := closeBrowserState m.ui } m
  in (m', NoCmd)
update ClosePalette m =
  let m' : Model
      m' = { paletteOpen := False, hover := Nothing } m
  in (m', redraw m')
update PaletteNext m =
  let n : Nat
      n = if paletteCount == 0 || m.paletteIndex + 1 >= paletteCount
             then 0
             else m.paletteIndex + 1
      m' : Model
      m' = { paletteIndex := n } m
  in (m', NoCmd)
update PalettePrev m =
  let n : Nat
      n = if paletteCount == 0
             then 0
             else if m.paletteIndex == 0
                     then minus paletteCount 1
                     else minus m.paletteIndex 1
      m' : Model
      m' = { paletteIndex := n } m
  in (m', NoCmd)
update (PaletteSelect n) m =
  let m' : Model
      m' = { paletteIndex := if n < paletteCount then n else m.paletteIndex } m
  in (m', NoCmd)
update (PaletteRun n) m =
  let m' : Model
      m' = { paletteIndex := n, paletteOpen := False, hover := Nothing } m
  in case paletteEntryAtIn m.keymap n of
       Nothing => (m', NoCmd)
       Just entry =>
         let (m2, cmd) = update entry.action m'
         in case cmd of
              NoCmd => if mapVisible m2 then (m2, redraw m2) else (m2, NoCmd)
              _ => (m2, cmd)
update PaletteExecute m = update (PaletteRun m.paletteIndex) m
update CycleLogFilter m =
  let m' : Model
      m' = { logFilter := nextLogFilter m.logFilter } m
  in (m', NoCmd)
update CycleLogFilterBack m =
  let m' : Model
      m' = { logFilter := prevLogFilter m.logFilter } m
  in (m', NoCmd)
update CycleTheme m =
  let m' : Model
      m' = { theme := nextTheme m.theme } m
  in (m', Batch [redraw m', saveSettingsCmd m'])
update SwitchLanguage m =
  let m' : Model
      m' = { language := nextLanguage m.language } m
  in (m', Batch [redraw m', saveSettingsCmd m'])
update ToggleAnimations m =
  let enabled = not m.animationsEnabled
      m' : Model
      m' = { animationsEnabled := enabled,
             animations := if enabled then m.animations else [] } m
  in (m', Batch [redraw m', saveSettingsCmd m'])
update CycleAnimationSpeed m =
  let speed = nextAnimationSpeed m.ui.animationSpeed
      m' : Model
      m' = { ui := { animationSpeed := speed } m.ui } m
  in (m', saveSettingsCmd m')
update SaveSettings m = (m, saveSettingsCmd m)
update ReloadSettings m =
  (m, Perform (do s <- loadSettings
                  pure (ApplySettings s.theme s.animationsEnabled
                                       s.animationSpeed s.keymap s.language)))
update (ApplySettings theme animations speed keymap language) m =
  let m' : Model
      m' = { theme := theme, animationsEnabled := animations,
             keymap := keymap, language := language,
             ui := { animationSpeed := speed } m.ui,
             animations := if animations then m.animations else [] } m
  in (m', redraw m')
update SaveAndQuit m =
  (m, Perform (do ok <- saveGame Manual m.game
                  if ok
                     then do deleteAutosave
                             pure Quit'
                     else pure Painted))
update LoadGame m =
  (m, Perform (do saved <- loadSave
                  pure (LoadedSave saved)))
update (LoadedSave Nothing) m = (m, NoCmd)
update (LoadedSave (Just saved)) m =
  let g : Game
      g = saved.game
      m0 : Model
      m0 = clearPack m
      m' : Model
      m' = { game := g, replay := emptyReplay g.seed,
             replayOk := Nothing, playback := Nothing,
             animations := [] } m0
  in (m', Batch [redraw m', Perform (do deleteSave
                                        deleteAutosave
                                        pure Painted)])
update AnimationTick m =
  let animations' : List Effect
      animations' = advanceAnimations m.animations
      m' : Model
      m' = { animations := animations' } m
  in if null m.animations
        then (m, NoCmd)
        else (m', if mapVisible m' then redraw m' else NoCmd)
update StartReplay m = beginPlayback m.replay m.replayOk m

update OpenReplayBrowser m =
  let m' : Model
      m' = { helpOpen := False, paletteOpen := False, scoreOpen := False,
             shareOpen := False, inventoryOpen := False,
             selectedItem := Nothing, inventoryIntent := Nothing,
             pendingDir := Nothing, hover := Nothing,
             ui := { replayBrowserOpen := True, replayIndex := 0,
                     replayError := Nothing } m.ui } m
  in (m', Perform (do names <- listReplayFiles
                      pure (ReplayFiles (reverse names))))

update CloseReplayBrowser m =
  let m' : Model
      m' = { ui := closeBrowserState m.ui, hover := Nothing } m
  in (m', NoCmd)

update (ReplayFiles names) m =
  let m' : Model
      m' = { ui := { replayFiles := names, replayIndex := 0,
                     replayError := Nothing } m.ui } m
  in (m', NoCmd)

update ReplayBrowserNext m =
  let count = length m.ui.replayFiles
      n = if count == 0 || m.ui.replayIndex + 1 >= count
             then 0
             else m.ui.replayIndex + 1
  in ({ ui := { replayIndex := n } m.ui } m, NoCmd)

update ReplayBrowserPrev m =
  let count = length m.ui.replayFiles
      n = if count == 0
             then 0
             else if m.ui.replayIndex == 0
                     then minus count 1
                     else minus m.ui.replayIndex 1
  in ({ ui := { replayIndex := n } m.ui } m, NoCmd)

update (ReplayBrowserSelect n) m =
  let count = length m.ui.replayFiles
  in ({ ui := { replayIndex := if n < count then n else m.ui.replayIndex }
               m.ui } m, NoCmd)

update (ReplayBrowserRun n) m =
  let m0 = fst (update (ReplayBrowserSelect n) m)
  in update ReplayBrowserOpenSelected m0

update ReplayBrowserOpenSelected m =
  case nth m.ui.replayIndex m.ui.replayFiles of
    Nothing => (m, NoCmd)
    Just name =>
      (m, Perform (do r <- loadReplayFile name
                      pure (ReplayFileLoaded name r)))

update (ReplayFileLoaded name (Just r)) m = beginPlayback r Nothing m

update (ReplayFileLoaded name Nothing) m =
  let m' : Model
      m' = { ui := { replayError := Just name } m.ui } m
  in (m', NoCmd)

update ReplayTick m =
  case m.playback of
    Nothing => (m, NoCmd)
    Just pb =>
      if pb.playing && not pb.done && not (null pb.remaining)
         then let m' = advancePlayback m
              in (m', redraw m')
         else (m, NoCmd)
update ReplayStep m =
  case m.playback of
    Nothing => (m, NoCmd)
    Just pb =>
      if pb.done
         then (m, NoCmd)
         else let m' = advancePlayback m
              in (m', redraw m')
update ReplayToggle m =
  case m.playback of
    Nothing => (m, NoCmd)
    Just pb =>
      let pb' : Playback
          pb' = { playing := if pb.done then False else not pb.playing } pb
          m' : Model
          m' = { playback := Just pb' } m
      in (m', redraw m')
update ReplaySpeedUp m =
  case m.playback of
    Nothing => (m, NoCmd)
    Just pb =>
      let m' : Model
          m' = { playback := Just ({ speed := fasterPlayback pb.speed } pb) } m
      in (m', redraw m')
update ReplaySpeedDown m =
  case m.playback of
    Nothing => (m, NoCmd)
    Just pb =>
      let m' : Model
          m' = { playback := Just ({ speed := slowerPlayback pb.speed } pb) } m
      in (m', redraw m')
update ReplaySeekBack m =
  case m.playback of
    Nothing => (m, NoCmd)
    Just pb => let m' = seekPlayback (minus pb.played 10) m
               in (m', redraw m')
update ReplaySeekForward m =
  case m.playback of
    Nothing => (m, NoCmd)
    Just pb => let m' = seekPlayback (pb.played + 10) m
               in (m', redraw m')
update ReplaySeekStart m =
  case m.playback of
    Nothing => (m, NoCmd)
    Just _ => let m' = seekPlayback 0 m in (m', redraw m')
update ReplaySeekEnd m =
  case m.playback of
    Nothing => (m, NoCmd)
    Just pb => let m' = seekPlayback pb.commandCount m
               in (m', redraw m')
update ReplayRestart m =
  case m.playback of
    Nothing => (m, NoCmd)
    Just pb =>
      let r = pb.replay
          commands = replayCommands r
          pb' : Playback
          pb' = { remaining := commands, played := 0,
                  commandCount := length commands, playing := not (null commands),
                  done := null commands, speed := pb.speed,
                  verified := pb.verified } pb
          m' : Model
          m' = { game := newGame r.seed, playback := Just pb',
                 animations := [] } m
      in (m', redraw m')
update CloseReplay m =
  case m.playback of
    Nothing => (m, NoCmd)
    Just pb =>
      let m' : Model
          m' = { game := pb.original, playback := Nothing,
                 scoreOpen := pb.returnToScores,
                 animations := [] } m
      in (m', NoCmd)
update (HoverCell c) m =
  if m.hover == c
     then (m, NoCmd)
     else let m' : Model
              m' = { hover := c } m
          in if mapVisible m' then (m', redraw m') else (m', NoCmd)
update OpenScores m =
  let m' : Model
      m' = { scoreOpen := True, shareOpen := False,
             helpOpen := False, paletteOpen := False,
             inventoryOpen := False, selectedItem := Nothing,
             inventoryIntent := Nothing, pendingDir := Nothing,
             hover := Nothing, ui := closeBrowserState m.ui } m
  in (m', NoCmd)
update CloseScores m =
  let m' : Model
      m' = { scoreOpen := False, hover := Nothing } m
  in (m', redraw m')
update OpenShare m =
  let m' : Model
      m' = { shareOpen := True, scoreOpen := False,
             helpOpen := False, paletteOpen := False,
             inventoryOpen := False, selectedItem := Nothing,
             inventoryIntent := Nothing, pendingDir := Nothing,
             hover := Nothing, ui := closeBrowserState m.ui } m
  in (m', NoCmd)
update CloseShare m =
  let m' : Model
      m' = { shareOpen := False, hover := Nothing } m
  in (m', redraw m')
update CopySeed m = (m, SetClipboard (seedHex m.game.seed))
