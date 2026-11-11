||| Keyboard subscriptions.
|||
||| Normal play and the inventory resolve keys through `Model.keymap`;
||| overlays and replay playback keep their small fixed key sets.  The
||| Core only ever sees the resulting `Command`, so rebinding a key cannot
||| change a turn, an RNG draw or a recorded replay.
module LambdaRogue.App.Subs

import Data.List
import Data.Maybe
import LambdaRogue.App.Keymap
import LambdaRogue.App.Model
import LambdaRogue.App.Mouse
import LambdaRogue.Core.Game
import LambdaRogue.Core.Item
import LambdaRogue.Core.Types
import LambdaRogue.UI.Animation
import TermUI.Input
import TermUI.Program

%default covering

nth : Nat -> List a -> Maybe a
nth Z (x :: _) = Just x
nth (S k) (_ :: xs) = nth k xs
nth _ [] = Nothing

letterIndex : Char -> Maybe Nat
letterIndex c =
  if c >= 'a' && c <= 'z'
     then Just (integerToNat (cast (ord c - ord 'a')))
     else Nothing

inventoryItem : Model -> Char -> Maybe Item
inventoryItem m c =
  case letterIndex c of
    Just n => nth n (packItems m.game)
    Nothing => Nothing

commandForInput : Model -> Input -> Maybe CommandId
commandForInput m (Press k mods) =
  commandForChord (MkKeyChord k mods) m.keymap
commandForInput _ _ = Nothing

commandMsg : CommandId -> Msg
commandMsg MoveNorth = Do (Move N)
commandMsg MoveSouth = Do (Move S)
commandMsg MoveWest = Do (Move W)
commandMsg MoveEast = Do (Move E)
commandMsg MoveNorthWest = Do (Move NW)
commandMsg MoveNorthEast = Do (Move NE)
commandMsg MoveSouthWest = Do (Move SW)
commandMsg MoveSouthEast = Do (Move SE)
commandMsg Wait = Do Wait
commandMsg Search = Do Search
commandMsg PickUp = Do PickUp
commandMsg Descend = Do Descend
commandMsg Ascend = Do Ascend
commandMsg Inventory = OpenInventory
commandMsg Quaff = OpenInventoryFor QuaffAction
commandMsg Read = OpenInventoryFor ReadAction
commandMsg Eat = OpenInventoryFor EatAction
commandMsg Wield = OpenInventoryFor WieldAction
commandMsg Wear = OpenInventoryFor WearAction
commandMsg PutOnRing = OpenInventoryFor PutOnAction
commandMsg TakeOff = OpenInventoryFor TakeOffAction
commandMsg Drop = OpenInventoryFor DropAction
commandMsg Zap = OpenInventoryFor ZapAction
commandMsg Throw = OpenInventoryFor ThrowAction
commandMsg Help = OpenHelp
commandMsg Palette = OpenPalette
commandMsg LogFilter = CycleLogFilter
commandMsg Theme = CycleTheme
commandMsg Animation = ToggleAnimations
commandMsg Scores = OpenScores
commandMsg Share = OpenShare
commandMsg ReplayBrowser = OpenReplayBrowser
commandMsg Redraw = Redraw
commandMsg Quit = Quit'

itemActionFor : CommandId -> Maybe ItemAction
itemActionFor Quaff = Just QuaffAction
itemActionFor Read = Just ReadAction
itemActionFor Eat = Just EatAction
itemActionFor Wield = Just WieldAction
itemActionFor Wear = Just WearAction
itemActionFor PutOnRing = Just PutOnAction
itemActionFor TakeOff = Just TakeOffAction
itemActionFor Drop = Just DropAction
itemActionFor Zap = Just ZapAction
itemActionFor Throw = Just ThrowAction
itemActionFor _ = Nothing

dirForCommand : CommandId -> Maybe Dir
dirForCommand MoveNorth = Just N
dirForCommand MoveSouth = Just S
dirForCommand MoveWest = Just W
dirForCommand MoveEast = Just E
dirForCommand MoveNorthWest = Just NW
dirForCommand MoveNorthEast = Just NE
dirForCommand MoveSouthWest = Just SW
dirForCommand MoveSouthEast = Just SE
dirForCommand _ = Nothing

directionForKey : Model -> Input -> Maybe Dir
directionForKey m input =
  commandForInput m input >>= dirForCommand

||| With no selection, a-z choose an item.  Once an item is selected, the
||| action keys from the keymap act on it; Enter uses the item's default
||| action.  Opening the pack with a command remembers the intended action,
||| so the next selected item is used immediately.
inventoryKey : Model -> Input -> Maybe Msg
inventoryKey m (Press KEscape _) = Just CloseInventory
inventoryKey m (Press (KChar 'i') _) = Just CloseInventory
inventoryKey m (Press KEnter _) =
  case m.selectedItem of
    Just iid =>
      case m.inventoryIntent of
        Just act => Just (ActOnItem act iid)
        Nothing =>
          case find (\i => i.id == iid) (packItems m.game) of
            Just i => Just (DoItemAction (defaultAction i))
            Nothing => Nothing
    Nothing => Nothing
inventoryKey m input@(Press (KChar c) _) =
  case m.selectedItem of
    Just _ =>
      case commandForInput m input of
        Just cid =>
          case itemActionFor cid of
            Just act => Just (DoItemAction act)
            Nothing => map SelectItem (map (.id) (inventoryItem m c))
        Nothing => map SelectItem (map (.id) (inventoryItem m c))
    Nothing =>
      case (m.inventoryIntent, inventoryItem m c) of
        (Just act, Just i) => Just (ActOnItem act i.id)
        _ => map SelectItem (map (.id) (inventoryItem m c))
inventoryKey _ _ = Nothing

directionMsg : Model -> Input -> Maybe Msg
directionMsg m input =
  case (m.pendingDir, directionForKey m input) of
    (_, Nothing) => Nothing
    (Just (ZapDir iid), Just d) => Just (Do (Zap iid d))
    (Just (ThrowDir iid), Just d) => Just (Do (Throw iid d))
    (Nothing, Just _) => Nothing

helpKey : Input -> Maybe Msg
helpKey (Press KEscape _) = Just CloseHelp
helpKey (Press (KChar '?') _) = Just CloseHelp
helpKey (Press (KChar 'q') _) = Just CloseHelp
helpKey (Press (KF 1) _) = Just CloseHelp
helpKey _ = Nothing

paletteKey : Input -> Maybe Msg
paletteKey (Press KEscape _) = Just ClosePalette
paletteKey (Press (KChar 'p') mods) =
  if mods.ctrl then Just ClosePalette else Nothing
paletteKey (Press KUp _) = Just PalettePrev
paletteKey (Press (KChar 'k') _) = Just PalettePrev
paletteKey (Press KDown _) = Just PaletteNext
paletteKey (Press (KChar 'j') _) = Just PaletteNext
paletteKey (Press KEnter _) = Just PaletteExecute
paletteKey _ = Nothing

scoreKey : Input -> Maybe Msg
scoreKey (Press KEscape _) = Just CloseScores
scoreKey (Press (KChar 'S') _) = Just CloseScores
scoreKey (Press (KChar 'q') _) = Just CloseScores
scoreKey (Press KEnter _) = Just CloseScores
scoreKey (Press (KChar 'p') _) = Just StartReplay
scoreKey (Press (KChar 'P') _) = Just StartReplay
scoreKey _ = Nothing

shareKey : Input -> Maybe Msg
shareKey (Press KEscape _) = Just CloseShare
shareKey (Press (KChar 's') mods) =
  if mods.ctrl then Just CloseShare else Nothing
shareKey (Press (KChar 'q') _) = Just CloseShare
shareKey (Press (KChar 'c') _) = Just CopySeed
shareKey (Press (KChar 'C') _) = Just CopySeed
shareKey (Press KEnter _) = Just CopySeed
shareKey _ = Nothing

replayBrowserKey : Input -> Maybe Msg
replayBrowserKey (Press KEscape _) = Just CloseReplayBrowser
replayBrowserKey (Press (KChar 'q') _) = Just CloseReplayBrowser
replayBrowserKey (Press (KChar 'r') _) = Just OpenReplayBrowser
replayBrowserKey (Press KUp _) = Just ReplayBrowserPrev
replayBrowserKey (Press (KChar 'k') _) = Just ReplayBrowserPrev
replayBrowserKey (Press KDown _) = Just ReplayBrowserNext
replayBrowserKey (Press (KChar 'j') _) = Just ReplayBrowserNext
replayBrowserKey (Press KEnter _) = Just ReplayBrowserOpenSelected
replayBrowserKey _ = Nothing

overlayKey : Model -> Input -> Maybe Msg
overlayKey m input =
  if m.helpOpen
     then helpKey input
     else if m.paletteOpen
             then paletteKey input
             else if m.ui.replayBrowserOpen
                     then replayBrowserKey input
                     else if m.scoreOpen
                             then scoreKey input
                             else if m.shareOpen
                                     then shareKey input
                                     else Nothing

normalKey : Model -> Input -> Maybe Msg
normalKey m input =
  map commandMsg (commandForInput m input)

keyWhenClosed : Model -> Input -> Maybe Msg
keyWhenClosed m input =
  case m.pendingDir of
    Just _ => case input of
                Press KEscape _ => Just CancelDirection
                _ => directionMsg m input
    Nothing => if m.inventoryOpen then inventoryKey m input
               else normalKey m input

playbackKey : Input -> Maybe Msg
playbackKey (Press KEscape _) = Just CloseReplay
playbackKey (Press (KChar 'q') _) = Just CloseReplay
playbackKey (Press (KChar 'Q') _) = Just CloseReplay
playbackKey (Press (KChar ' ') _) = Just ReplayToggle
playbackKey (Press (KChar '.') _) = Just ReplayStep
playbackKey (Press KEnter _) = Just ReplayStep
playbackKey (Press (KChar '+') _) = Just ReplaySpeedUp
playbackKey (Press (KChar '=') _) = Just ReplaySpeedUp
playbackKey (Press (KChar '-') _) = Just ReplaySpeedDown
playbackKey (Press (KChar '_') _) = Just ReplaySpeedDown
playbackKey (Press (KChar 'r') _) = Just ReplayRestart
playbackKey (Press (KChar 'R') _) = Just ReplayRestart
playbackKey (Press KLeft _) = Just ReplaySeekBack
playbackKey (Press (KChar '<') _) = Just ReplaySeekBack
playbackKey (Press KRight _) = Just ReplaySeekForward
playbackKey (Press (KChar '>') _) = Just ReplaySeekForward
playbackKey (Press KHome _) = Just ReplaySeekStart
playbackKey (Press KEnd _) = Just ReplaySeekEnd
playbackKey _ = Nothing

||| Theme and animation bindings remain global, as F3/F4 were in the
||| earlier slices.  They still do not touch `Game`.
globalKey : Model -> Input -> Maybe Msg
globalKey m input =
  case commandForInput m input of
    Just Theme => Just CycleTheme
    Just Animation => Just ToggleAnimations
    Just ReplayBrowser =>
      case m.playback of
        Just _ => Nothing
        Nothing => Just OpenReplayBrowser
    _ => Nothing

isCtrlC : Input -> Bool
isCtrlC (Press (KChar 'c') mods) = mods.ctrl
isCtrlC _ = False

public export
key : Model -> Input -> Maybe Msg
key m input =
  case globalKey m input of
    Just msg => Just msg
    Nothing =>
      if isCtrlC input
         then Just Quit'
         else case m.playback of
                Just _ => playbackKey input
                Nothing => case overlayKey m input of
                             Just msg => Just msg
                             Nothing => if overlayOpen m
                                           then Nothing
                                           else keyWhenClosed m input

public export
subs : Model -> List (Sub Msg)
replaySub : Model -> List (Sub Msg)
replaySub m =
  case m.playback of
    Just pb => if pb.playing && not pb.done && not (null pb.remaining)
                  then [Every "replay" (playbackDelay pb.speed) ReplayTick]
                  else []
    Nothing => []

subs m =
  [ OnInput (key m)
  , OnResize (\c, r => Resized c r)
  , OnMouse (mouseMsg m)
  ] ++ (if null m.animations
          then []
          else [Every "animation" (animationDelay m.ui.animationSpeed)
                    AnimationTick])
    ++ replaySub m
