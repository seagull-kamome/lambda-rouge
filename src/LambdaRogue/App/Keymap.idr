||| Pure key bindings and their textual form.
|||
||| A binding is a stable command identifier plus a list of key chords.
||| The Core never sees this module: changing a key changes only which
||| `Msg` the App produces, never a `Command`, turn, RNG draw or replay.
||| The help screen and the palette hints are generated from the same
||| `Keymap`, so they cannot drift away from what the app actually accepts.
module LambdaRogue.App.Keymap

import Data.List
import Data.Maybe
import Data.String
import TermUI.Input

%default covering

||| A key plus its modifiers.  Character case is meaningful on its own:
||| `Q` and `q` are different chords, while `Ctrl-Q` and `Ctrl-q` are the
||| same one because terminals disagree about the case they report.
public export
record KeyChord where
  constructor MkKeyChord
  key : Key
  mods : Mods

lowerChar : Char -> Char
lowerChar c =
  if c >= 'A' && c <= 'Z'
     then chr (ord c + 32)
     else c

upperChar : Char -> Char
upperChar c =
  if c >= 'a' && c <= 'z'
     then chr (ord c - 32)
     else c

lowerString : String -> String
lowerString = pack . map lowerChar . unpack

isLetter : Char -> Bool
isLetter c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')

||| Modifiers that survive normalisation.  Shift on a character is
||| represented by the character itself (`Q`), and terminal function keys
||| rarely report it, so it is dropped.
public export
normaliseChord : KeyChord -> KeyChord
normaliseChord (MkKeyChord k ms) =
  case k of
    KChar c =>
      let c' = if ms.ctrl || ms.alt then lowerChar c else c
      in MkKeyChord (KChar c') (MkMods False ms.ctrl ms.alt)
    _ => MkKeyChord k (MkMods False ms.ctrl ms.alt)

public export
Eq KeyChord where
  a == b = same (normaliseChord a) (normaliseChord b)
    where
      same : KeyChord -> KeyChord -> Bool
      same (MkKeyChord k ms) (MkKeyChord k' ms') =
        k == k' && ms.ctrl == ms'.ctrl && ms.alt == ms'.alt

||| Stable command identifiers.  They are the keys of `settings.json`,
||| never their list position.
public export
data CommandId
  = MoveNorth
  | MoveSouth
  | MoveWest
  | MoveEast
  | MoveNorthWest
  | MoveNorthEast
  | MoveSouthWest
  | MoveSouthEast
  | Wait
  | Search
  | PickUp
  | Descend
  | Ascend
  | Inventory
  | Quaff
  | Read
  | Eat
  | Wield
  | Wear
  | PutOnRing
  | TakeOff
  | Drop
  | Zap
  | Throw
  | Help
  | Palette
  | LogFilter
  | Theme
  | Animation
  | Scores
  | Share
  | Redraw
  | Quit

public export
Eq CommandId where
  MoveNorth == MoveNorth = True
  MoveSouth == MoveSouth = True
  MoveWest == MoveWest = True
  MoveEast == MoveEast = True
  MoveNorthWest == MoveNorthWest = True
  MoveNorthEast == MoveNorthEast = True
  MoveSouthWest == MoveSouthWest = True
  MoveSouthEast == MoveSouthEast = True
  Wait == Wait = True
  Search == Search = True
  PickUp == PickUp = True
  Descend == Descend = True
  Ascend == Ascend = True
  Inventory == Inventory = True
  Quaff == Quaff = True
  Read == Read = True
  Eat == Eat = True
  Wield == Wield = True
  Wear == Wear = True
  PutOnRing == PutOnRing = True
  TakeOff == TakeOff = True
  Drop == Drop = True
  Zap == Zap = True
  Throw == Throw = True
  Help == Help = True
  Palette == Palette = True
  LogFilter == LogFilter = True
  Theme == Theme = True
  Animation == Animation = True
  Scores == Scores = True
  Share == Share = True
  Redraw == Redraw = True
  Quit == Quit = True
  _ == _ = False

public export
Show CommandId where
  show MoveNorth = "MoveNorth"
  show MoveSouth = "MoveSouth"
  show MoveWest = "MoveWest"
  show MoveEast = "MoveEast"
  show MoveNorthWest = "MoveNorthWest"
  show MoveNorthEast = "MoveNorthEast"
  show MoveSouthWest = "MoveSouthWest"
  show MoveSouthEast = "MoveSouthEast"
  show Wait = "Wait"
  show Search = "Search"
  show PickUp = "PickUp"
  show Descend = "Descend"
  show Ascend = "Ascend"
  show Inventory = "Inventory"
  show Quaff = "Quaff"
  show Read = "Read"
  show Eat = "Eat"
  show Wield = "Wield"
  show Wear = "Wear"
  show PutOnRing = "PutOnRing"
  show TakeOff = "TakeOff"
  show Drop = "Drop"
  show Zap = "Zap"
  show Throw = "Throw"
  show Help = "Help"
  show Palette = "Palette"
  show LogFilter = "LogFilter"
  show Theme = "Theme"
  show Animation = "Animation"
  show Scores = "Scores"
  show Share = "Share"
  show Redraw = "Redraw"
  show Quit = "Quit"

||| The stable JSON name for a command.
public export
commandName : CommandId -> String
commandName MoveNorth = "move-north"
commandName MoveSouth = "move-south"
commandName MoveWest = "move-west"
commandName MoveEast = "move-east"
commandName MoveNorthWest = "move-north-west"
commandName MoveNorthEast = "move-north-east"
commandName MoveSouthWest = "move-south-west"
commandName MoveSouthEast = "move-south-east"
commandName Wait = "wait"
commandName Search = "search"
commandName PickUp = "pick-up"
commandName Descend = "descend"
commandName Ascend = "ascend"
commandName Inventory = "inventory"
commandName Quaff = "quaff"
commandName Read = "read"
commandName Eat = "eat"
commandName Wield = "wield"
commandName Wear = "wear"
commandName PutOnRing = "put-on-ring"
commandName TakeOff = "take-off"
commandName Drop = "drop"
commandName Zap = "zap"
commandName Throw = "throw"
commandName Help = "help"
commandName Palette = "palette"
commandName LogFilter = "log-filter"
commandName Theme = "theme"
commandName Animation = "animation"
commandName Scores = "scores"
commandName Share = "share"
commandName Redraw = "redraw"
commandName Quit = "quit"

public export
commandFromName : String -> Maybe CommandId
commandFromName "move-north" = Just MoveNorth
commandFromName "move-south" = Just MoveSouth
commandFromName "move-west" = Just MoveWest
commandFromName "move-east" = Just MoveEast
commandFromName "move-north-west" = Just MoveNorthWest
commandFromName "move-north-east" = Just MoveNorthEast
commandFromName "move-south-west" = Just MoveSouthWest
commandFromName "move-south-east" = Just MoveSouthEast
commandFromName "wait" = Just Wait
commandFromName "search" = Just Search
commandFromName "pick-up" = Just PickUp
commandFromName "descend" = Just Descend
commandFromName "ascend" = Just Ascend
commandFromName "inventory" = Just Inventory
commandFromName "quaff" = Just Quaff
commandFromName "read" = Just Read
commandFromName "eat" = Just Eat
commandFromName "wield" = Just Wield
commandFromName "wear" = Just Wear
commandFromName "put-on-ring" = Just PutOnRing
commandFromName "take-off" = Just TakeOff
commandFromName "drop" = Just Drop
commandFromName "zap" = Just Zap
commandFromName "throw" = Just Throw
commandFromName "help" = Just Help
commandFromName "palette" = Just Palette
commandFromName "log-filter" = Just LogFilter
commandFromName "theme" = Just Theme
commandFromName "animation" = Just Animation
commandFromName "scores" = Just Scores
commandFromName "share" = Just Share
commandFromName "redraw" = Just Redraw
commandFromName "quit" = Just Quit
commandFromName _ = Nothing

public export
record Binding where
  constructor MkBinding
  id : CommandId
  label : String
  keys : List KeyChord

public export
Eq Binding where
  a == b = a.id == b.id && a.keys == b.keys

public export
Keymap : Type
Keymap = List Binding

ch : Char -> KeyChord
ch c = MkKeyChord (KChar c) noMods

ctrl : Char -> KeyChord
ctrl c = MkKeyChord (KChar c) (MkMods False True False)

special : Key -> KeyChord
special k = MkKeyChord k noMods

||| Defaults follow Rogue's vi keys and keep every command reachable
||| without a mouse.  Lower-case `q` quaffs; `Q` and Ctrl-C quit.
public export
defaultKeymap : Keymap
defaultKeymap =
  [ MkBinding MoveNorth "Move north" [ch 'k', special KUp]
  , MkBinding MoveSouth "Move south" [ch 'j', special KDown]
  , MkBinding MoveWest "Move west" [ch 'h', special KLeft]
  , MkBinding MoveEast "Move east" [ch 'l', special KRight]
  , MkBinding MoveNorthWest "Move north-west" [ch 'y']
  , MkBinding MoveNorthEast "Move north-east" [ch 'u']
  , MkBinding MoveSouthWest "Move south-west" [ch 'b']
  , MkBinding MoveSouthEast "Move south-east" [ch 'n']
  , MkBinding Wait "Wait one turn" [ch '.', ch '5']
  , MkBinding Search "Search for traps" [ch 's']
  , MkBinding PickUp "Pick up" [ch ',']
  , MkBinding Descend "Descend stairs" [ch '>']
  , MkBinding Ascend "Ascend stairs" [ch '<']
  , MkBinding Inventory "Inventory" [ch 'i']
  , MkBinding Quaff "Quaff a potion" [ch 'q']
  , MkBinding Read "Read a scroll" [ch 'r']
  , MkBinding Eat "Eat food" [ch 'e']
  , MkBinding Wield "Wield a weapon" [ch 'w']
  , MkBinding Wear "Wear armor" [ch 'W']
  , MkBinding PutOnRing "Put on a ring" [ch 'P']
  , MkBinding TakeOff "Take off an item" [ch 'R', ch 'T']
  , MkBinding Drop "Drop an item" [ch 'd']
  , MkBinding Zap "Zap a wand" [ch 'z']
  , MkBinding Throw "Throw an item" [ch 't']
  , MkBinding Help "Help" [ch '?', special (KF 1)]
  , MkBinding Palette "Command palette" [ctrl 'p']
  , MkBinding LogFilter "Cycle log filter" [special (KF 2)]
  , MkBinding Theme "Cycle theme" [special (KF 3)]
  , MkBinding Animation "Toggle animation" [special (KF 4)]
  , MkBinding Scores "Scores" [ch 'S']
  , MkBinding Share "Share seed" [ctrl 's']
  , MkBinding Redraw "Redraw" [ctrl 'r', ctrl 'l']
  , MkBinding Quit "Quit" [ch 'Q', ctrl 'c']
  ]

||| Look one command up by its stable id.
public export
bindingFor : CommandId -> Keymap -> Maybe Binding
bindingFor cid [] = Nothing
bindingFor cid (b :: bs) =
  if b.id == cid then Just b else bindingFor cid bs

public export
keysFor : CommandId -> Keymap -> List KeyChord
keysFor cid km =
  case bindingFor cid km of
    Just b => b.keys
    Nothing => []

||| Replace the keys of one command, keeping the order of the keymap.
public export
setBindingKeys : CommandId -> List KeyChord -> Keymap -> Keymap
setBindingKeys cid ks [] = []
setBindingKeys cid ks (b :: bs) =
  (if b.id == cid then { keys := ks } b else b) :: setBindingKeys cid ks bs

||| The first command bound to this chord.  The keymap is validated for
||| duplicates when it is loaded, so this order is deterministic.
public export
commandForChord : KeyChord -> Keymap -> Maybe CommandId
commandForChord k [] = Nothing
commandForChord k (b :: bs) =
  if any (== k) b.keys then Just b.id else commandForChord k bs

public export
hasDuplicateChords : Keymap -> Bool
hasDuplicateChords km = go [] (concatMap keys km)
  where
    go : List KeyChord -> List KeyChord -> Bool
    go _ [] = False
    go seen (k :: ks) =
      if any (== k) seen then True else go (k :: seen) ks

public export
chordText : KeyChord -> String
chordText (MkKeyChord k ms) =
  (if ms.ctrl then "Ctrl-" else "")
  ++ (if ms.alt then "Alt-" else "")
  ++ keyText k
  where
    keyText : Key -> String
    keyText (KChar ' ') = "Space"
    keyText (KChar c) =
      if (ms.ctrl || ms.alt) && isLetter c
         then singleton (upperChar c)
         else singleton c
    keyText (KF n) = "F" ++ show n
    keyText KEnter = "Enter"
    keyText KTab = "Tab"
    keyText KBackTab = "BackTab"
    keyText KBackspace = "Backspace"
    keyText KEscape = "Esc"
    keyText KUp = "Up"
    keyText KDown = "Down"
    keyText KLeft = "Left"
    keyText KRight = "Right"
    keyText KHome = "Home"
    keyText KEnd = "End"
    keyText KPageUp = "PageUp"
    keyText KPageDown = "PageDown"
    keyText KInsert = "Insert"
    keyText KDelete = "Delete"

public export
formatKeys : List KeyChord -> String
formatKeys [] = "unbound"
formatKeys ks = joinBy " / " (map chordText ks)

public export
formatPrimary : Keymap -> CommandId -> String
formatPrimary km cid =
  case keysFor cid km of
    [] => "unbound"
    (k :: _) => chordText k

public export
anyArrowKeys : List CommandId -> Keymap -> Bool
anyArrowKeys cids km =
  any isArrow (concatMap (\cid => keysFor cid km) cids)
  where
    isArrow : KeyChord -> Bool
    isArrow (MkKeyChord KUp _) = True
    isArrow (MkKeyChord KDown _) = True
    isArrow (MkKeyChord KLeft _) = True
    isArrow (MkKeyChord KRight _) = True
    isArrow _ = False

stripPrefixCI : String -> String -> Maybe String
stripPrefixCI pre s =
  let p = lowerString pre
      t = lowerString s
  in if isPrefixOf p t
        then Just (pack (drop (length (unpack p)) (unpack s)))
        else Nothing

parseMods : Bool -> Bool -> String -> (Bool, Bool, String)
parseMods c a input =
  case stripPrefixCI "ctrl-" input of
    Just rest => parseMods True a rest
    Nothing =>
      case stripPrefixCI "alt-" input of
        Just rest => parseMods c True rest
        Nothing =>
          case stripPrefixCI "shift-" input of
            Just rest => parseMods c a rest
            Nothing => (c, a, trim input)

parseFKey : String -> Maybe Key
parseFKey s =
  case unpack s of
    ('F' :: ds) => do
      n <- parsePositive (pack ds)
      pure (KF n)
    ('f' :: ds) => do
      n <- parsePositive (pack ds)
      pure (KF n)
    _ => Nothing

parseNamedKey : String -> Maybe Key
parseNamedKey s =
  case lowerString s of
    "space" => Just (KChar ' ')
    "enter" => Just KEnter
    "return" => Just KEnter
    "tab" => Just KTab
    "backtab" => Just KBackTab
    "backspace" => Just KBackspace
    "escape" => Just KEscape
    "esc" => Just KEscape
    "up" => Just KUp
    "down" => Just KDown
    "left" => Just KLeft
    "right" => Just KRight
    "home" => Just KHome
    "end" => Just KEnd
    "pageup" => Just KPageUp
    "pgup" => Just KPageUp
    "pagedown" => Just KPageDown
    "pgdn" => Just KPageDown
    "insert" => Just KInsert
    "ins" => Just KInsert
    "delete" => Just KDelete
    "del" => Just KDelete
    other => parseFKey other

||| Parse one human-written chord: `k`, `Q`, `Ctrl-S`, `F4`, `Up`,
||| `Space`, `>` and so on.  Unknown names are rejected so a typo in
||| `settings.json` cannot silently produce a dead binding.
public export
parseKeyChord : String -> Maybe KeyChord
parseKeyChord raw =
  let (c, a, body) = parseMods False False (trim raw)
      ms = MkMods False c a
  in case unpack body of
       [one] => Just (normaliseChord (MkKeyChord (KChar one) ms))
       _ => do
         k <- parseNamedKey body
         pure (normaliseChord (MkKeyChord k ms))
