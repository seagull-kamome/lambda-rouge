||| Inventory key-routing tests: selection, action keys and closing.
module SubsTest

import LambdaRogue.App.Canvas
import LambdaRogue.App.Model
import LambdaRogue.App.Subs
import LambdaRogue.App.Update
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Survival
import LambdaRogue.Core.Types
import LambdaRogue.UI.Animation
import LambdaRogue.UI.Theme
import Data.Maybe
import Data.List
import System
import TermUI.Canvas
import TermUI.Input
import TermUI.Len
import TermUI.Program

check : String -> Bool -> IO ()
check name ok =
  if ok
     then putStrLn ("ok   " ++ name)
     else do
       putStrLn ("FAIL " ++ name)
       exitFailure

isSelect : ItemId -> Maybe Msg -> Bool
isSelect iid (Just (SelectItem x)) = x == iid
isSelect _ _ = False

isAction : ItemAction -> Maybe Msg -> Bool
isAction act (Just (DoItemAction a)) = a == act
isAction _ _ = False

isClose : Maybe Msg -> Bool
isClose (Just CloseInventory) = True
isClose _ = False

isOpenFor : ItemAction -> Maybe Msg -> Bool
isOpenFor act (Just (OpenInventoryFor a)) = a == act
isOpenFor _ _ = False

isActOn : ItemAction -> ItemId -> Maybe Msg -> Bool
isActOn act iid (Just (ActOnItem a i)) = a == act && i == iid
isActOn _ _ _ = False

isZap : Dir -> Maybe Msg -> Bool
isZap d (Just (Do (Zap 2 d'))) = d == d'
isZap _ _ = False

isCancel : Maybe Msg -> Bool
isCancel (Just CancelDirection) = True
isCancel _ = False

isHelp : Maybe Msg -> Bool
isHelp (Just OpenHelp) = True
isHelp _ = False

isCloseHelp : Maybe Msg -> Bool
isCloseHelp (Just CloseHelp) = True
isCloseHelp _ = False

isPalette : Maybe Msg -> Bool
isPalette (Just OpenPalette) = True
isPalette _ = False

isPaletteClose : Maybe Msg -> Bool
isPaletteClose (Just ClosePalette) = True
isPaletteClose _ = False

isPaletteNext : Maybe Msg -> Bool
isPaletteNext (Just PaletteNext) = True
isPaletteNext _ = False

isPalettePrev : Maybe Msg -> Bool
isPalettePrev (Just PalettePrev) = True
isPalettePrev _ = False

isPaletteExec : Maybe Msg -> Bool
isPaletteExec (Just PaletteExecute) = True
isPaletteExec _ = False

isFilter : Maybe Msg -> Bool
isFilter (Just CycleLogFilter) = True
isFilter _ = False

isTheme : Maybe Msg -> Bool
isTheme (Just CycleTheme) = True
isTheme _ = False

isToggleAnimations : Maybe Msg -> Bool
isToggleAnimations (Just ToggleAnimations) = True
isToggleAnimations _ = False

isStartReplay : Maybe Msg -> Bool
isStartReplay (Just StartReplay) = True
isStartReplay _ = False

isCloseReplay : Maybe Msg -> Bool
isCloseReplay (Just CloseReplay) = True
isCloseReplay _ = False

isReplayToggle : Maybe Msg -> Bool
isReplayToggle (Just ReplayToggle) = True
isReplayToggle _ = False

isSeekBack : Maybe Msg -> Bool
isSeekBack (Just ReplaySeekBack) = True
isSeekBack _ = False

isSeekForward : Maybe Msg -> Bool
isSeekForward (Just ReplaySeekForward) = True
isSeekForward _ = False

isSeekStart : Maybe Msg -> Bool
isSeekStart (Just ReplaySeekStart) = True
isSeekStart _ = False

isSeekEnd : Maybe Msg -> Bool
isSeekEnd (Just ReplaySeekEnd) = True
isSeekEnd _ = False

isOpenBrowser : Maybe Msg -> Bool
isOpenBrowser (Just OpenReplayBrowser) = True
isOpenBrowser _ = False

isCloseBrowser : Maybe Msg -> Bool
isCloseBrowser (Just CloseReplayBrowser) = True
isCloseBrowser _ = False

isBrowserNext : Maybe Msg -> Bool
isBrowserNext (Just ReplayBrowserNext) = True
isBrowserNext _ = False

isBrowserPrev : Maybe Msg -> Bool
isBrowserPrev (Just ReplayBrowserPrev) = True
isBrowserPrev _ = False

isBrowserOpen : Maybe Msg -> Bool
isBrowserOpen (Just ReplayBrowserOpenSelected) = True
isBrowserOpen _ = False

isScores : Maybe Msg -> Bool
isScores (Just OpenScores) = True
isScores _ = False

isCloseScores : Maybe Msg -> Bool
isCloseScores (Just CloseScores) = True
isCloseScores _ = False

isShare : Maybe Msg -> Bool
isShare (Just OpenShare) = True
isShare _ = False

isCloseShare : Maybe Msg -> Bool
isCloseShare (Just CloseShare) = True
isCloseShare _ = False

isCopySeed : Maybe Msg -> Bool
isCopySeed (Just CopySeed) = True
isCopySeed _ = False

hasMouseSub : List (Sub Msg) -> Bool
hasMouseSub [] = False
hasMouseSub (OnMouse _ :: _) = True
hasMouseSub (_ :: rest) = hasMouseSub rest

hasAnimationSub : List (Sub Msg) -> Bool
hasAnimationSub [] = False
hasAnimationSub (Every "animation" 16 AnimationTick :: _) = True
hasAnimationSub (_ :: rest) = hasAnimationSub rest

hasReplaySub : List (Sub Msg) -> Bool
hasReplaySub [] = False
hasReplaySub (Every "replay" _ ReplayTick :: _) = True
hasReplaySub (_ :: rest) = hasReplaySub rest

hasPaletteEntry : String -> (Msg -> Bool) -> Bool
hasPaletteEntry label p =
  any (\e => e.label == label && p e.action) paletteEntries

public export
run : IO ()
run = do
  c <- newCanvas (the Len 80) (the Len 22)
  let potion : Item
      potion = MkItem 2 (Potion PotionHealing) InPack 1 0 False 0 False
      p : Player
      p = { inventory := [2] } sampleGame.player
      g : Game
      g = { player := p, items := [potion] } sampleGame
      m : Model
      m = MkModel c g 80 24 True Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState

  check "a selects the first pack item"
    (isSelect 2 (key m (Press (KChar 'a') noMods)))

  let mSel : Model
      mSel = { selectedItem := Just 2 } m
  check "q quaffs the selected item"
    (isAction QuaffAction (key mSel (Press (KChar 'q') noMods)))
  check "e eats the selected item"
    (isAction EatAction (key mSel (Press (KChar 'e') noMods)))
  check "Enter uses the item's default action"
    (isAction QuaffAction (key mSel (Press KEnter noMods)))
  check "Escape closes the inventory"
    (isClose (key mSel (Press KEscape noMods)))
  check "i closes the inventory"
    (isClose (key mSel (Press (KChar 'i') noMods)))

  let mNormal : Model
      mNormal = { inventoryOpen := False } m
  check "the app subscribes to raw mouse events"
    (hasMouseSub (subs mNormal))
  let mAnimated : Model
      mAnimated = { animations := [mkEffect Trail (MkCoord 4 5)] } mNormal
  check "the app runs a timer while an animation is active"
    (hasAnimationSub (subs mAnimated))
  check "the app has no animation timer when idle"
    (not (hasAnimationSub (subs mNormal)))
  check "r opens the pack for reading"
    (isOpenFor ReadAction (key mNormal (Press (KChar 'r') noMods)))
  check "z opens the pack for zapping"
    (isOpenFor ZapAction (key mNormal (Press (KChar 'z') noMods)))
  check "t opens the pack for throwing"
    (isOpenFor ThrowAction (key mNormal (Press (KChar 't') noMods)))
  check "P opens the pack for putting on rings"
    (isOpenFor PutOnAction (key mNormal (Press (KChar 'P') noMods)))
  check "l still moves east"
    (case key mNormal (Press (KChar 'l') noMods) of
       Just (Do (Move E)) => True
       _ => False)

  let mPending : Model
      mPending = { pendingDir := Just (ZapDir 2), inventoryOpen := False } m
  check "a direction key resolves a zap"
    (isZap E (key mPending (Press (KChar 'l') noMods)))
  check "Escape cancels the direction prompt"
    (isCancel (key mPending (Press KEscape noMods)))

  let mIntent : Model
      mIntent = { inventoryOpen := True, inventoryIntent := Just ReadAction } m
  check "an inventory intent acts on the chosen item"
    (isActOn ReadAction 2 (key mIntent (Press (KChar 'a') noMods)))

  let wandItem : Item
      wandItem = MkItem 3 (Wand WandLight) InPack 1 0 False 5 False
      gWand : Game
      gWand = { player := { inventory := [3] } sampleGame.player
              , items := [wandItem] } sampleGame
      mWand : Model
      mWand = MkModel c gWand 80 24 True (Just 3) Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  check "Enter zaps a selected wand"
    (isAction ZapAction (key mWand (Press KEnter noMods)))

  let zapOut = update (DoItemAction ZapAction) mSel
      mZapping : Model
      mZapping = fst zapOut
  check "zapping enters the direction prompt"
    (mZapping.pendingDir == Just (ZapDir 2))
  let cancelOut = update CancelDirection mZapping
      mCancelled : Model
      mCancelled = fst cancelOut
  check "cancelling clears the direction prompt"
    (mCancelled.pendingDir == Nothing)

  check "? opens help"
    (isHelp (key mNormal (Press (KChar '?') noMods)))
  check "F1 opens help"
    (isHelp (key mNormal (Press (KF 1) noMods)))
  check "Ctrl-P opens the command palette"
    (isPalette (key mNormal (Press (KChar 'p') (MkMods False True False))))
  check "F2 cycles the log filter"
    (isFilter (key mNormal (Press (KF 2) noMods)))
  check "F3 cycles the theme"
    (isTheme (key mNormal (Press (KF 3) noMods)))
  check "F4 toggles animation"
    (isToggleAnimations (key mNormal (Press (KF 4) noMods)))

  let mHelp : Model
      mHelp = { helpOpen := True } mNormal
  check "Escape closes help"
    (isCloseHelp (key mHelp (Press KEscape noMods)))
  check "? closes help"
    (isCloseHelp (key mHelp (Press (KChar '?') noMods)))
  check "help swallows movement keys"
    (isNothing (key mHelp (Press (KChar 'l') noMods)))
  check "F3 still cycles the theme while help is open"
    (isTheme (key mHelp (Press (KF 3) noMods)))
  check "F4 still toggles animation while help is open"
    (isToggleAnimations (key mHelp (Press (KF 4) noMods)))

  let mPalette : Model
      mPalette = { paletteOpen := True, paletteIndex := 0 } mNormal
  check "j moves the palette cursor down"
    (isPaletteNext (key mPalette (Press (KChar 'j') noMods)))
  check "Up moves the palette cursor up"
    (isPalettePrev (key mPalette (Press KUp noMods)))
  check "Enter runs the selected palette entry"
    (isPaletteExec (key mPalette (Press KEnter noMods)))
  check "Escape closes the palette"
    (isPaletteClose (key mPalette (Press KEscape noMods)))
  check "the palette swallows movement keys"
    (isNothing (key mPalette (Press (KChar 'h') noMods)))

  let helpOut = update OpenHelp mNormal
      mOpenedHelp = fst helpOut
  check "opening help closes the pack"
    (mOpenedHelp.helpOpen && not mOpenedHelp.inventoryOpen)
  let paletteOut = update OpenPalette mNormal
      mOpenedPalette = fst paletteOut
  check "opening the palette resets its cursor"
    (mOpenedPalette.paletteOpen && mOpenedPalette.paletteIndex == 0)
  let execOut = update PaletteExecute mPalette
      mExecuted = fst execOut
  check "executing Inventory from the palette opens the pack"
    (mExecuted.inventoryOpen && not mExecuted.paletteOpen)
  let filterOut = update CycleLogFilter mNormal
      mFiltered = fst filterOut
  check "cycling the log filter advances it"
    (mFiltered.logFilter == CombatMessages)
  check "the log filter cycle continues"
    ((fst (update CycleLogFilter mFiltered)).logFilter == ItemMessages)
  let mWarnings : Model
      mWarnings = { logFilter := WarningMessages } mNormal
  check "the log filter cycle goes back from the wheel"
    ((fst (update CycleLogFilterBack mWarnings)).logFilter == SystemMessages)
  let themeOut = update CycleTheme mNormal
      mThemed = fst themeOut
  check "cycling the theme advances it"
    (mThemed.theme == ModernDark)
  check "cycling the theme keeps the game state"
    (mThemed.game.turn == mNormal.game.turn
     && mThemed.replay.commands == mNormal.replay.commands)

  let mPaletteLast : Model
      mPaletteLast = { paletteIndex := minus paletteCount 1 } mPalette
  check "palette next wraps to the first entry"
    ((fst (update PaletteNext mPaletteLast)).paletteIndex == 0)
  check "palette prev wraps to the last entry"
    ((fst (update PalettePrev mPalette)).paletteIndex
       == minus paletteCount 1)
  check "opening the palette closes help"
    (let m' = fst (update OpenPalette mHelp)
     in m'.paletteOpen && not m'.helpOpen)

  check "S opens the score screen"
    (isScores (key mNormal (Press (KChar 'S') noMods)))
  check "Ctrl-S opens seed sharing"
    (isShare (key mNormal (Press (KChar 's') (MkMods False True False))))
  check "the palette has 28 entries"
    (paletteCount == 28)
  check "game actions lead the palette"
    (map (.label) (Data.List.take 6 paletteEntries)
       == [ "Inventory", "Pick up", "Search for traps", "Wait one turn"
          , "Descend stairs", "Ascend stairs" ])
  check "Search for traps is near the top"
    (case paletteEntryAt 2 of
       Just e => e.label == "Search for traps"
                  && (case e.action of Do Search => True; _ => False)
       Nothing => False)
  check "the palette includes Scores"
    (hasPaletteEntry "Scores"
      (\m => case m of OpenScores => True; _ => False))
  check "the palette includes Share seed"
    (hasPaletteEntry "Share seed"
      (\m => case m of OpenShare => True; _ => False))
  check "the palette includes Cycle theme"
    (hasPaletteEntry "Cycle theme"
      (\m => case m of CycleTheme => True; _ => False))
  check "the palette includes Toggle animation"
    (hasPaletteEntry "Toggle animation"
      (\m => case m of ToggleAnimations => True; _ => False))
  check "the palette includes Cycle animation speed"
    (hasPaletteEntry "Cycle animation speed"
      (\m => case m of CycleAnimationSpeed => True; _ => False))
  check "the palette includes Switch language"
    (hasPaletteEntry "Switch language"
      (\m => case m of SwitchLanguage => True; _ => False))
  check "the palette includes Replay browser"
    (hasPaletteEntry "Replay browser"
      (\m => case m of OpenReplayBrowser => True; _ => False))
  check "the palette includes Save settings"
    (hasPaletteEntry "Save settings"
      (\m => case m of SaveSettings => True; _ => False))
  check "the palette includes Reload settings"
    (hasPaletteEntry "Reload settings"
      (\m => case m of ReloadSettings => True; _ => False))
  check "the palette includes Save and quit"
    (hasPaletteEntry "Save and quit"
      (\m => case m of SaveAndQuit => True; _ => False))
  check "the palette includes Load game"
    (hasPaletteEntry "Load game"
      (\m => case m of LoadGame => True; _ => False))
  check "Quit is the last palette entry"
    (case paletteEntryAt (minus paletteCount 1) of
       Just e => e.label == "Quit"
                  && (case e.action of Quit' => True; _ => False)
       Nothing => False)

  let mScores : Model
      mScores = { scoreOpen := True } mNormal
  check "Escape closes the score screen"
    (isCloseScores (key mScores (Press KEscape noMods)))
  check "S closes the score screen"
    (isCloseScores (key mScores (Press (KChar 'S') noMods)))
  check "the score screen swallows movement keys"
    (isNothing (key mScores (Press (KChar 'l') noMods)))
  check "P starts the visible replay"
    (isStartReplay (key mScores (Press (KChar 'P') noMods)))

  let mWithReplay : Model
      mWithReplay = { replay := recordCommand Wait (emptyReplay sampleGame.seed) } mScores
      mPlayback = fst (update StartReplay mWithReplay)
  check "the app runs a replay timer while playing"
    (hasReplaySub (subs mPlayback))
  check "Escape stops the visible replay"
    (isCloseReplay (key mPlayback (Press KEscape noMods)))
  check "Space pauses the visible replay"
    (isReplayToggle (key mPlayback (Press (KChar ' ') noMods)))
  check "a plain movement key is swallowed during playback"
    (isNothing (key mPlayback (Press (KChar 'l') noMods)))
  let mPaused = fst (update ReplayToggle mPlayback)
  check "the replay timer stops when paused"
    (not (hasReplaySub (subs mPaused)))
  check "Left seeks the replay backwards"
    (isSeekBack (key mPlayback (Press KLeft noMods)))
  check "Right seeks the replay forwards"
    (isSeekForward (key mPlayback (Press KRight noMods)))
  check "Home seeks to the start"
    (isSeekStart (key mPlayback (Press KHome noMods)))
  check "End seeks to the end"
    (isSeekEnd (key mPlayback (Press KEnd noMods)))
  check "F5 is ignored during playback"
    (isNothing (key mPlayback (Press (KF 5) noMods)))

  check "F5 opens the replay browser"
    (isOpenBrowser (key mNormal (Press (KF 5) noMods)))
  let mBrowser : Model
      mBrowser = { ui := { replayBrowserOpen := True } mNormal.ui } mNormal
  check "Escape closes the replay browser"
    (isCloseBrowser (key mBrowser (Press KEscape noMods)))
  check "j moves down the replay browser"
    (isBrowserNext (key mBrowser (Press (KChar 'j') noMods)))
  check "the down arrow moves down the replay browser"
    (isBrowserNext (key mBrowser (Press KDown noMods)))
  check "k moves up the replay browser"
    (isBrowserPrev (key mBrowser (Press (KChar 'k') noMods)))
  check "Enter plays the selected replay"
    (isBrowserOpen (key mBrowser (Press KEnter noMods)))
  check "the browser swallows movement keys"
    (isNothing (key mBrowser (Press (KChar 'h') noMods)))

  let mShare : Model
      mShare = { shareOpen := True } mNormal
  check "c copies the seed"
    (isCopySeed (key mShare (Press (KChar 'c') noMods)))
  check "Ctrl-S closes seed sharing"
    (isCloseShare (key mShare (Press (KChar 's') (MkMods False True False))))
  check "the share screen swallows movement keys"
    (isNothing (key mShare (Press (KChar 'l') noMods)))

  check "opening scores closes help"
    (let m' = fst (update OpenScores mHelp)
     in m'.scoreOpen && not m'.helpOpen)
  check "opening share closes scores"
    (let m' = fst (update OpenShare mScores)
     in m'.shareOpen && not m'.scoreOpen)

  let gStarve0 = newGame 42
      lvl : Level
      lvl = { monsters := [] } (currentLevel gStarve0)
      gStarve = updateCurrentLevel (const lvl) gStarve0
      pDying : Player
      pDying = { hp := 1, hunger := starvingDeathAt + 1 } gStarve.player
      gDying : Game
      gDying = { player := pDying } gStarve
      mDying = MkModel c gDying 80 24 False Nothing Nothing Nothing
                 False False 0 AllMessages (emptyReplay 42)
                 [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
      deadOut = update (Do Wait) mDying
      mDead = fst deadOut
  check "game over auto-opens the score screen"
    (mDead.scoreOpen && length mDead.scores == 1)
  check "game over records the replay result"
    (isJust mDead.replayOk)
  check "commands after game over are ignored"
    ((fst (update (Do Wait) mDead)).replay.commands
       == mDead.replay.commands)

  putStrLn "subs tests passed"
