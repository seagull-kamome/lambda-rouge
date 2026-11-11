||| The app model shared by update, view and subscriptions.
module LambdaRogue.App.Model

import public LambdaRogue.App.Catalog
import public LambdaRogue.App.Keymap
import LambdaRogue.Core.Game
import LambdaRogue.Core.Item
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Types
import LambdaRogue.Persist.Save
import LambdaRogue.UI.Animation
import LambdaRogue.UI.Theme
import TermUI.Len
import TermUI.Canvas

%default covering

public export
data ItemAction
  = QuaffAction
  | ReadAction
  | EatAction
  | WieldAction
  | WearAction
  | PutOnAction
  | TakeOffAction
  | DropAction
  | ZapAction
  | ThrowAction

public export
Eq ItemAction where
  QuaffAction == QuaffAction = True
  ReadAction == ReadAction = True
  EatAction == EatAction = True
  WieldAction == WieldAction = True
  WearAction == WearAction = True
  PutOnAction == PutOnAction = True
  TakeOffAction == TakeOffAction = True
  DropAction == DropAction = True
  ZapAction == ZapAction = True
  ThrowAction == ThrowAction = True
  _ == _ = False

||| Actions that need a direction after the item has been chosen.
public export
data PendingDir
  = ZapDir ItemId
  | ThrowDir ItemId

public export
Eq PendingDir where
  ZapDir a == ZapDir b = a == b
  ThrowDir a == ThrowDir b = a == b
  _ == _ = False

public export
data Msg
  = Quit'
  | Redraw
  | Painted
  | Resized Len Len
  | Do Command
  | OpenInventory
  | OpenInventoryFor ItemAction
  | CloseInventory
  | SelectItem ItemId
  | ActOnItem ItemAction ItemId
  | DoItemAction ItemAction
  | CancelDirection
  | OpenHelp
  | CloseHelp
  | OpenPalette
  | ClosePalette
  | PaletteNext
  | PalettePrev
  | PaletteExecute
  | CycleLogFilter
  | CycleLogFilterBack
  | CycleTheme
  | SwitchLanguage
  | OpenScores
  | CloseScores
  | OpenShare
  | CloseShare
  | CopySeed
  | HoverCell (Maybe Coord)
  | PaletteSelect Nat
  | PaletteRun Nat
  | ToggleAnimations
  | CycleAnimationSpeed
  | AnimationTick
  | SaveSettings
  | ReloadSettings
  | SaveAndQuit
  | LoadGame
  | LoadedSave (Maybe SaveFile)
  | ApplySettings Theme Bool AnimationSpeed Keymap Language
  | StartReplay
  | ReplayTick
  | ReplayToggle
  | ReplayStep
  | ReplaySpeedUp
  | ReplaySpeedDown
  | ReplayRestart
  | ReplaySeekBack
  | ReplaySeekForward
  | ReplaySeekStart
  | ReplaySeekEnd
  | CloseReplay
  | OpenReplayBrowser
  | CloseReplayBrowser
  | ReplayBrowserNext
  | ReplayBrowserPrev
  | ReplayBrowserSelect Nat
  | ReplayBrowserRun Nat
  | ReplayFiles (List String)
  | ReplayBrowserOpenSelected
  | ReplayFileLoaded String (Maybe Replay)

||| Presentation-only message filter.  The Core keeps every message; the
||| filter only decides which ones the log pane shows.
public export
data LogFilter
  = AllMessages
  | CombatMessages
  | ItemMessages
  | SystemMessages
  | WarningMessages

public export
Eq LogFilter where
  AllMessages == AllMessages = True
  CombatMessages == CombatMessages = True
  ItemMessages == ItemMessages = True
  SystemMessages == SystemMessages = True
  WarningMessages == WarningMessages = True
  _ == _ = False

public export
Show LogFilter where
  show AllMessages = "all"
  show CombatMessages = "combat"
  show ItemMessages = "items"
  show SystemMessages = "system"
  show WarningMessages = "warnings"

public export
nextLogFilter : LogFilter -> LogFilter
nextLogFilter AllMessages = CombatMessages
nextLogFilter CombatMessages = ItemMessages
nextLogFilter ItemMessages = SystemMessages
nextLogFilter SystemMessages = WarningMessages
nextLogFilter WarningMessages = AllMessages

public export
prevLogFilter : LogFilter -> LogFilter
prevLogFilter AllMessages = WarningMessages
prevLogFilter CombatMessages = AllMessages
prevLogFilter ItemMessages = CombatMessages
prevLogFilter SystemMessages = ItemMessages
prevLogFilter WarningMessages = SystemMessages

public export
messageMatches : LogFilter -> MessageKind -> Bool
messageMatches AllMessages _ = True
messageMatches CombatMessages CombatMsg = True
messageMatches ItemMessages ItemMsg = True
messageMatches SystemMessages SystemMsg = True
messageMatches SystemMessages StoryMsg = True
messageMatches WarningMessages WarningMsg = True
messageMatches _ _ = False

||| The action Enter uses for an item in the pack.  It is shared by the
||| keyboard inventory and the mouse so both take the same path.
public export
defaultAction : Item -> ItemAction
defaultAction i =
  case i.kind of
    Potion _ => QuaffAction
    Scroll _ => ReadAction
    Wand _ => ZapAction
    Ring _ => PutOnAction
    Food _ => EatAction
    Weapon _ => WieldAction
    Armor _ => WearAction
    _ => DropAction

||| One command-palette row.  `action` is an ordinary message, so palette
||| entries take exactly the same update path as keyboard commands.
public export
record PaletteEntry where
  constructor MkPaletteEntry
  label : String
  hint : String
  action : Msg
  command : Maybe CommandId

public export
paletteEntries : List PaletteEntry
paletteEntries =
  [ MkPaletteEntry "Inventory" "i" OpenInventory (Just Inventory)
  , MkPaletteEntry "Help" "?" OpenHelp (Just Help)
  , MkPaletteEntry "Wait one turn" "." (Do Wait) (Just Wait)
  , MkPaletteEntry "Pick up" "," (Do PickUp) (Just PickUp)
  , MkPaletteEntry "Descend stairs" ">" (Do Descend) (Just Descend)
  , MkPaletteEntry "Ascend stairs" "<" (Do Ascend) (Just Ascend)
  , MkPaletteEntry "Read a scroll" "r" (OpenInventoryFor ReadAction) (Just Read)
  , MkPaletteEntry "Quaff a potion" "q" (OpenInventoryFor QuaffAction) (Just Quaff)
  , MkPaletteEntry "Eat food" "e" (OpenInventoryFor EatAction) (Just Eat)
  , MkPaletteEntry "Zap a wand" "z" (OpenInventoryFor ZapAction) (Just Zap)
  , MkPaletteEntry "Throw an item" "t" (OpenInventoryFor ThrowAction) (Just Throw)
  , MkPaletteEntry "Put on a ring" "P" (OpenInventoryFor PutOnAction) (Just PutOnRing)
  , MkPaletteEntry "Take off an item" "R" (OpenInventoryFor TakeOffAction) (Just TakeOff)
  , MkPaletteEntry "Drop an item" "d" (OpenInventoryFor DropAction) (Just Drop)
  , MkPaletteEntry "Cycle log filter" "F2" CycleLogFilter (Just LogFilter)
  , MkPaletteEntry "Scores" "S" OpenScores (Just Scores)
  , MkPaletteEntry "Share seed" "Ctrl-S" OpenShare (Just Share)
  , MkPaletteEntry "Cycle theme" "F3" CycleTheme (Just Theme)
  , MkPaletteEntry "Toggle animation" "F4" ToggleAnimations (Just Animation)
  , MkPaletteEntry "Cycle animation speed" "" CycleAnimationSpeed Nothing
  , MkPaletteEntry "Switch language" "ja" SwitchLanguage Nothing
  , MkPaletteEntry "Replay browser" "F5" OpenReplayBrowser (Just ReplayBrowser)
  , MkPaletteEntry "Save settings" "" SaveSettings Nothing
  , MkPaletteEntry "Reload settings" "" ReloadSettings Nothing
  , MkPaletteEntry "Save and quit" "" SaveAndQuit Nothing
  , MkPaletteEntry "Load game" "" LoadGame Nothing
  , MkPaletteEntry "Search for traps" "s" (Do Search) (Just Search)
  , MkPaletteEntry "Quit" "Q" Quit' (Just Quit)
  ]

||| Palette hints follow the active keymap instead of keeping a second,
||| stale copy of the defaults.
public export
paletteEntriesFor : Keymap -> List PaletteEntry
paletteEntriesFor km = map refresh paletteEntries
  where
    refresh : PaletteEntry -> PaletteEntry
    refresh entry =
      case entry.command of
        Nothing => entry
        Just cid => { hint := formatPrimary km cid } entry

||| Palette labels are presentation only; the English label remains the
||| stable identity used by the settings and tests.
public export
paletteEntriesForLang : Language -> Keymap -> List PaletteEntry
paletteEntriesForLang lang km =
  map localize (paletteEntriesFor km)
  where
    localize : PaletteEntry -> PaletteEntry
    localize entry =
      let translated = { label := paletteLabel lang entry.label } entry
      in case entry.action of
           SwitchLanguage => { hint := languageId (nextLanguage lang) }
                               translated
           _ => translated

public export
paletteEntryAtIn : Keymap -> Nat -> Maybe PaletteEntry
paletteEntryAtIn km n = go n (paletteEntriesFor km)
  where
    go : Nat -> List PaletteEntry -> Maybe PaletteEntry
    go Z (e :: _) = Just e
    go (S k) (_ :: es) = go k es
    go _ [] = Nothing

public export
paletteEntryAt : Nat -> Maybe PaletteEntry
paletteEntryAt = paletteEntryAtIn defaultKeymap

public export
paletteCount : Nat
paletteCount = length paletteEntries

||| One completed run.  The slice-4 score screen is in memory only; the
||| JSON Lines persistence from `doc/persistence.md` comes later.
public export
record Score where
  constructor MkScore
  seed : Bits64
  depth : Depth
  level : Int32
  exp : Int32
  gold : Int32
  turns : Turn
  result : GameOver

public export
scoreOf : Game -> Maybe Score
scoreOf g =
  case g.over of
    Nothing => Nothing
    Just result =>
      Just (MkScore g.seed g.depth g.player.level g.player.exp
                    g.player.gold g.turn result)

public export
data PlaybackSpeed = SlowPlayback | NormalPlayback | FastPlayback

public export
Eq PlaybackSpeed where
  SlowPlayback == SlowPlayback = True
  NormalPlayback == NormalPlayback = True
  FastPlayback == FastPlayback = True
  _ == _ = False

public export
Show PlaybackSpeed where
  show SlowPlayback = "slow"
  show NormalPlayback = "normal"
  show FastPlayback = "fast"

public export
playbackDelay : PlaybackSpeed -> Nat
playbackDelay SlowPlayback = 400
playbackDelay NormalPlayback = 200
playbackDelay FastPlayback = 80

public export
fasterPlayback : PlaybackSpeed -> PlaybackSpeed
fasterPlayback SlowPlayback = NormalPlayback
fasterPlayback NormalPlayback = FastPlayback
fasterPlayback FastPlayback = FastPlayback

public export
slowerPlayback : PlaybackSpeed -> PlaybackSpeed
slowerPlayback FastPlayback = NormalPlayback
slowerPlayback NormalPlayback = SlowPlayback
slowerPlayback SlowPlayback = SlowPlayback

||| A visible replay owns the game shown on screen while it runs.  The
||| original game is kept aside so closing the playback returns to where
||| it started without changing the recorded run.
public export
record Playback where
  constructor MkPlayback
  original : Game
  replay : Replay
  remaining : List Command
  played : Nat
  commandCount : Nat
  playing : Bool
  speed : PlaybackSpeed
  done : Bool
  verified : Maybe Bool
  ||| Whether to reopen the score screen when the playback closes.  A
  ||| replay launched from the browser mid-run returns to the map instead.
  returnToScores : Bool

||| Presentation-only UI state that is neither game state nor a modal
||| overlay's contents.  Keeping it in one record makes the extra fields
||| easy to extend without touching every `Model` constructor call.
public export
record UiState where
  constructor MkUiState
  animationSpeed : AnimationSpeed
  replayBrowserOpen : Bool
  replayFiles : List String
  replayIndex : Nat
  replayError : Maybe String

public export
defaultUiState : UiState
defaultUiState = MkUiState NormalAnimation False [] 0 Nothing

public export
record Model where
  constructor MkModel
  canvas : Canvas
  game : Game
  width, height : Len
  inventoryOpen : Bool
  selectedItem : Maybe ItemId
  inventoryIntent : Maybe ItemAction
  pendingDir : Maybe PendingDir
  helpOpen : Bool
  paletteOpen : Bool
  paletteIndex : Nat
  logFilter : LogFilter
  replay : Replay
  scores : List Score
  scoreOpen : Bool
  shareOpen : Bool
  replayOk : Maybe Bool
  theme : Theme
  hover : Maybe Coord
  animations : List Effect
  animationsEnabled : Bool
  playback : Maybe Playback
  keymap : Keymap
  language : Language
  ui : UiState

public export
initModel : Canvas -> Game -> Model
initModel c g = MkModel c g 80 24 False Nothing Nothing Nothing
                       False False 0 AllMessages (emptyReplay g.seed)
                       [] False False Nothing ClassicCga Nothing [] True Nothing
                       defaultKeymap English defaultUiState

||| True while one of the modal screens owns the keyboard and the map.
public export
overlayOpen : Model -> Bool
overlayOpen m =
  m.helpOpen || m.paletteOpen || m.scoreOpen || m.shareOpen
  || m.ui.replayBrowserOpen

||| True while a visible replay owns the keyboard.  The map is still on
||| screen, but ordinary game commands must not run.
public export
playbackOpen : Model -> Bool
playbackOpen m =
  case m.playback of
    Just _ => True
    Nothing => False

||| True when the normal map is on screen.  Mouse coordinates only mean a
||| map cell in this state.
public export
mapVisible : Model -> Bool
mapVisible m =
  not (m.width < 80 || m.height < 24)
  && not (overlayOpen m) && not m.inventoryOpen
