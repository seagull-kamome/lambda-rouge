||| The two layouts: the classic 80x24 screen and a 120x40 wide screen.
module LambdaRogue.App.View

import Data.List
import Data.Maybe
import Data.String
import LambdaRogue.App.Keymap
import LambdaRogue.App.Model
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Combat
import LambdaRogue.Core.Game
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Item
import LambdaRogue.Core.Monster
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Survival
import LambdaRogue.Core.Types
import LambdaRogue.UI.LogView
import LambdaRogue.UI.MapView
import LambdaRogue.UI.Theme
import LambdaRogue.Version
import TermUI.Len
import TermUI.Node
import TermUI.Style

%default covering

||| The presentation style of one semantic slot in the current theme.
styled : Model -> StyleRole -> Style
styled m role = styleFor m.theme role

borderColorOf : Model -> Color
borderColorOf m = (styled m BorderRole).fg

line : Style -> String -> Node Msg
line s t = box [height (Cells 1)] [truncated s t]

hpBar : Player -> String
hpBar p =
  let raw = if p.maxHp <= 0 then 0 else (p.hp * 10) `div` p.maxHp
      filled = min 10 (integerToNat (cast (max 0 raw)))
  in "[" ++ pack (replicate filled '#') ++ pack (replicate (10 `minus` filled) '-') ++ "]"

gameOverText : Game -> String
gameOverText g =
  case g.over of
    Nothing => ""
    Just (Dead cause) => "  DEAD: " ++ show cause
    Just Won => "  WON"

classicStatus : Model -> String
classicStatus m =
  let p = m.game.player
  in "Dlvl " ++ show m.game.depth
     ++ "  Lv " ++ show p.level
     ++ "  HP " ++ show p.hp ++ "/" ++ show p.maxHp
     ++ "  Str " ++ show (effectiveStrength p)
     ++ "  Gold " ++ show p.gold
     ++ "  Exp " ++ show p.exp ++ "/" ++ show (expForNext p.level)
     ++ "  Turn " ++ show m.game.turn
     ++ "  Food " ++ show (hungerState p.hunger)
     ++ gameOverText m.game

playbackText : Playback -> String
playbackText pb =
  "REPLAY " ++ show pb.played ++ "/" ++ show pb.commandCount
  ++ "  " ++ show pb.speed
  ++ (if pb.done then "  complete"
      else if pb.playing then "  playing" else "  paused")
  ++ "  " ++ (if pb.verified then "verified" else "MISMATCH")
  ++ "   Space . -/+ R Esc"

header : Model -> String
header m =
  case m.playback of
    Just pb => playbackText pb
    Nothing =>
      "lambda-rogue " ++ version
      ++ "   Depth " ++ show m.game.depth
      ++ "   Level " ++ show m.game.player.level
      ++ "   Turn " ++ show m.game.turn
      ++ "   Log " ++ show m.logFilter
      ++ "   Theme " ++ show m.theme
      ++ "   Seed " ++ seedHex m.game.seed

floorItem : Game -> Maybe Item
floorItem g =
  find (\i => case i.location of
                OnFloor d _ => d == g.depth
                InPack => False
                CarriedBy _ => False)
       g.items

monsterLine : Game -> String
monsterLine g =
  let ms = filter (\m => not (hasAbility Invisible m.kind)
                         || playerSeesInvisible g
                         || adjacent m.pos g.player.pos)
                  (currentLevel g).monsters
  in case ms of
       [] => "Monsters: none"
       (mo :: _) => "Monsters: " ++ show (length ms)
                    ++ "  " ++ monsterName mo.kind
                    ++ " (" ++ show mo.state ++ ") " ++ show mo.pos

itemLine : Game -> String
itemLine g =
  case floorItem g of
    Nothing => "Item: none"
    Just i => case i.location of
                OnFloor _ p => "Item: " ++ itemDisplayNameIn g i
                               ++ " " ++ show p
                InPack => "Item: " ++ itemDisplayNameIn g i ++ " (pack)"
                CarriedBy _ => "Item: " ++ itemDisplayNameIn g i
                               ++ " (carried)"

equippedName : Game -> Maybe ItemId -> String
equippedName g Nothing = "none"
equippedName g (Just iid) =
  case findPackItem g iid of
    Just i => itemDisplayNameIn g i
    Nothing => "?"

statusLine : Player -> String
statusLine p =
  if null p.statuses
     then "Status: none"
     else "Status: " ++ concat (intersperse ", "
            (map (\s => show s.statusKind ++ "(" ++ show s.remaining ++ ")")
                 p.statuses))

sidebarLines : Model -> List (Node Msg)
sidebarLines m =
  let g = m.game
      p = g.player
      lvl = currentLevel g
      body = styled m BodyRole
      dim = styled m DimRole
      title = styled m TitleRole
      overLine : List (Node Msg)
      overLine = case g.over of
                   Nothing => []
                   Just _ => [line (styled m DangerRole) (gameOverText g)]
  in [ line title "Status"
     , line body ("HP " ++ show p.hp ++ "/" ++ show p.maxHp ++ "  " ++ hpBar p)
     , line body ("Lv " ++ show p.level ++ "  Exp " ++ show p.exp
                  ++ "/" ++ show (expForNext p.level))
     , line body ("Str " ++ show (effectiveStrength p) ++ "/" ++ show p.maxStrength
                  ++ "   Gold " ++ show p.gold)
     , line body ("Food " ++ show (hungerState p.hunger))
     , line body ("Depth " ++ show g.depth ++ "   Turn " ++ show g.turn)
     , line body ("Pos " ++ show p.pos)
     , line body ("Seed " ++ seedHex g.seed)
     , line dim "------------"
     , line body ("Weapon: " ++ equippedName g p.wielded)
     , line body ("Armor: " ++ equippedName g p.worn)
     , line body ("Rings: " ++ equippedName g p.leftRing ++ " / "
                  ++ equippedName g p.rightRing)
     , line body (statusLine p)
     , line dim "------------"
     , line body ("Visible " ++ show (count g.visible)
                  ++ "   Explored " ++ show (count lvl.explored))
     , line body ("Rooms " ++ show (length lvl.rooms)
                  ++ "   Traps " ++ show (length lvl.traps))
     , line dim "------------"
     , line body (monsterLine g)
     , line body (itemLine g)
     , line dim "------------"
     , line title "Keys"
     , line dim "hjkl/yubn move   . wait   i inventory"
     , line dim ", pick up   > descend   < ascend"
     , line dim "r read   z zap   t throw   P put on ring"
     , line dim "R take off   ^R redraw   q quit"
     , line dim "? help  ^P palette  F2 log  F3 theme"
     , line dim "S scores   ^S share seed"
     , line dim "Mouse: map click, wheel lists"
     ] ++ overLine

directionPrompt : Model -> Maybe String
directionPrompt m =
  case m.pendingDir of
    Just (ZapDir _) =>
      Just "Zap in which direction?  hjkl/yubn or arrows, Esc cancels"
    Just (ThrowDir _) =>
      Just "Throw in which direction?  hjkl/yubn or arrows, Esc cancels"
    Nothing => Nothing

||| Up to `n` messages matching the presentation filter, oldest first.
filteredMessages : Nat -> LogFilter -> Game -> List Message
filteredMessages n f g =
  reverse (take n (filter (\msg => messageMatches f msg.kind) g.messages))

filterPrefix : Model -> String
filterPrefix m =
  if m.logFilter == AllMessages
     then ""
     else "[" ++ show m.logFilter ++ "] "

latestMessage : Model -> Node Msg
latestMessage m =
  case find (\msg => messageMatches m.logFilter msg.kind) m.game.messages of
    Nothing => truncated (styled m DimRole)
      ("(no " ++ show m.logFilter ++ " messages)")
    Just msg => truncated (messageStyleFor m.theme msg.kind)
      (filterPrefix m ++ msg.text)

latestNode : Model -> Node Msg
latestNode m =
  case m.playback of
    Just pb => truncated (styled m TitleRole) (playbackText pb)
    Nothing => case directionPrompt m of
      Just text => truncated (styled m TitleRole) text
      Nothing =>
        case m.hover of
          Just c =>
            case describeCell m.game c of
              Just text => truncated (styled m HeaderRole) ("Hover " ++ text)
              Nothing => latestMessage m
          Nothing => latestMessage m

classicLayout : Model -> Node Msg
classicLayout m =
  box [width (Cells 80), height (Cells 24)] [
    box [height (Cells 1)] [latestNode m],
    box [height (Cells 22)] [canvas m.canvas],
    box [height (Cells 1), style (styled m StatusRole)]
      [truncated (styled m BodyRole) (classicStatus m)]
  ]

minimapLegend : Model -> List (Node Msg)
minimapLegend m =
  [ line (styled m TitleRole) "Minimap"
  , line (styled m DimRole) "@ you   < > stairs"
  , line (styled m DimRole) "+ door   # wall   . floor"
  , line (styled m DimRole) "Only explored cells are shown."
  ]

||| The eight rows under the map hold a 36x8 minimap and a short legend.
minimapPanel : Model -> Node Msg
minimapPanel m =
  row [height (Cells 8), paddingXY 1 0] [
    box [width (Cells 36), height (Cells 8)]
      (map (line (styled m MinimapRole)) (minimapRows m.game)),
    box [width (Cells 42), height (Cells 8), padding 1] (minimapLegend m)
  ]

logLines : Model -> List (Node Msg)
logLines m =
  case filteredMessages 8 m.logFilter m.game of
    [] => [line (styled m DimRole) ("(no " ++ show m.logFilter ++ " messages)")]
    msgs => map (\msg => line (messageStyleFor m.theme msg.kind) msg.text) msgs

wideLayout : Model -> Node Msg
wideLayout m =
  box [width (Cells 120), height (Cells 40)] [
    box [height (Cells 1)] [truncated (styled m HeaderRole) (header m)],
    row [height (Cells 30)] [
      box [width (Cells 80), height (Cells 30)] [
        box [height (Cells 22)] [canvas m.canvas],
        minimapPanel m
      ],
      box [width (Cells 40), height (Cells 30), padding 1] (sidebarLines m)
    ],
    box [height (Cells 8)] (logLines m),
    box [height (Cells 1), style (styled m StatusRole)]
      [truncated (styled m BodyRole) (classicStatus m)]
  ]

letters : List Char
letters = unpack "abcdefghijklmnopqrstuvwxyz"

itemMarker : Model -> Item -> String
itemMarker m i =
  if m.selectedItem == Just i.id then ">"
  else if m.game.player.wielded == Just i.id
          || m.game.player.worn == Just i.id
          || m.game.player.leftRing == Just i.id
          || m.game.player.rightRing == Just i.id then "*"
  else " "

inventoryRow : Model -> (Char, Item) -> Node Msg
inventoryRow m (letter, i) =
  let text = pack [letter] ++ " " ++ itemMarker m i ++ " "
             ++ itemDetailIn m.game i
      style = if m.selectedItem == Just i.id then styled m TitleRole
              else if itemMarker m i == "*" then styled m HeaderRole
              else styled m BodyRole
  in line style text

inventoryRows : Model -> List (Node Msg)
inventoryRows m =
  case packItems m.game of
    [] => [line (styled m DimRole) "(empty)"]
    items => map (inventoryRow m) (zip letters items)

categoryName : ItemKind -> String
categoryName (Weapon _) = "weapon"
categoryName (Armor _) = "armor"
categoryName (Food _) = "food"
categoryName (Potion _) = "potion"
categoryName (Scroll _) = "scroll"
categoryName (Wand _) = "wand"
categoryName (Ring _) = "ring"
categoryName Gold = "gold"
categoryName Amulet = "amulet"

signed : Int32 -> String
signed n = if n >= 0 then "+" ++ show n else show n

enchantLines : Model -> Item -> List (Node Msg)
enchantLines m i =
  [line (styled m BodyRole) ("Enchantment: " ++ signed i.enchant)]
  ++ (if i.cursed
         then [line (styled m DangerRole) "Cursed: cannot remove"]
         else [])

kindDetail : Model -> Item -> List (Node Msg)
kindDetail m i =
  if not (itemKnown m.game.knownKinds i)
     then [line (styled m DimRole) "Unidentified: effects hidden"]
     else case i.kind of
            Weapon _ => enchantLines m i
            Armor _ => enchantLines m i
            Ring _ => enchantLines m i
            Wand _ => [line (styled m BodyRole) ("Charges: " ++ show i.charges)]
            Gold => [line (styled m BodyRole)
                          ("Amount: " ++ show i.count ++ " gold")]
            _ => []

equippedSlot : Player -> ItemId -> Maybe String
equippedSlot p iid =
  if p.wielded == Just iid then Just "wielded"
  else if p.worn == Just iid then Just "worn"
  else if p.leftRing == Just iid then Just "left ring"
  else if p.rightRing == Just iid then Just "right ring"
  else Nothing

itemLetter : Model -> ItemId -> String
itemLetter m iid =
  case find (\(_, i) => i.id == iid) (zip letters (packItems m.game)) of
    Just (l, _) => pack [l]
    Nothing => "?"

comparisonLines : Model -> Item -> List (Node Msg)
comparisonLines m i =
  let dim = styled m DimRole
  in case i.kind of
       Weapon _ =>
         [line dim ("Wielded: "
           ++ equippedName m.game m.game.player.wielded)]
       Armor _ =>
         [line dim ("Worn: " ++ equippedName m.game m.game.player.worn)]
       Ring _ =>
         [line dim ("Rings: "
           ++ equippedName m.game m.game.player.leftRing ++ " / "
           ++ equippedName m.game m.game.player.rightRing)]
       _ => []

selectedOrFirst : Model -> Maybe Item
selectedOrFirst m =
  case m.selectedItem of
    Just iid =>
      case find (\i => i.id == iid) (packItems m.game) of
        Just i => Just i
        Nothing => head' (packItems m.game)
    Nothing => head' (packItems m.game)

inventoryDetailLines : Model -> List (Node Msg)
inventoryDetailLines m =
  let body = styled m BodyRole
      dim = styled m DimRole
  in case selectedOrFirst m of
       Nothing => [line dim "The pack is empty."]
       Just i =>
         [ line (styled m TitleRole) "Item details"
         , line (styled m HeaderRole) (itemDisplayNameIn m.game i)
         , line body ("Slot " ++ itemLetter m i.id ++ "   "
                       ++ categoryName i.kind)
         ] ++ (case equippedSlot m.game.player i.id of
                 Just s => [line (styled m HeaderRole) ("Equipped: " ++ s)]
                 Nothing => [line dim "In pack"])
           ++ kindDetail m i
           ++ (if i.protected
                  then [line body "Protected from theft"]
                  else [])
           ++ comparisonLines m i
           ++ [ line dim "------------"
              , line dim "Enter uses this item."
              , line dim "a-z selects another slot."
              ]

inventoryHints : Model -> List (Node Msg)
inventoryHints m =
  let dim = styled m DimRole
  in [ line dim "a-z select  Enter use  q quaff  r read  e eat  w wield"
     , line dim "W wear  P put on  R/T take off  z zap  t throw  d drop  Esc"
     ]

inventoryRowAt : Model -> Maybe (Char, Item) -> Node Msg
inventoryRowAt m Nothing = line (styled m BodyRole) ""
inventoryRowAt m (Just entry) = inventoryRow m entry

||| The classic layout has room for two 40-column item columns, so all 23
||| pack slots stay reachable on an 80x24 screen.
inventoryTwoColumnRows : Model -> List (Node Msg)
inventoryTwoColumnRows m =
  let entries = zip letters (packItems m.game)
      left : List (Maybe (Char, Item))
      left = map Just (take 20 entries)
      right : List (Maybe (Char, Item))
      right = map Just (take 20 (drop 20 entries))
      pad : List (Maybe (Char, Item)) -> List (Maybe (Char, Item))
      pad xs = take 20 (xs ++ replicate 20 Nothing)
  in map (\(l, r) =>
            row [height (Cells 1)] [
              box [width (Cells 40)] [inventoryRowAt m l],
              box [width (Cells 40)] [inventoryRowAt m r]
            ])
         (zip (pad left) (pad right))

inventoryLayout : Model -> Node Msg
inventoryLayout m =
  let count = length (packItems m.game)
      title = "Inventory  " ++ show count ++ "/" ++ show maxPack
  in box [width (Cells 80), height (Cells 24)] [
       line (styled m TitleRole) title,
       box [height (Cells 20)] (inventoryTwoColumnRows m),
       box [height (Cells 2)] (inventoryHints m),
       box [height (Cells 1), style (styled m StatusRole)]
         [truncated (styled m BodyRole) (classicStatus m)]
     ]

inventoryWideLayout : Model -> Node Msg
inventoryWideLayout m =
  let count = length (packItems m.game)
      title = "Inventory  " ++ show count ++ "/" ++ show maxPack
  in box [width (Cells 120), height (Cells 40)] [
       line (styled m TitleRole) title,
       row [height (Cells 35)] [
         box [width (Cells 68), height (Cells 35), paddingXY 1 0]
           (take 35 (inventoryRows m)),
         box [width (Cells 52), height (Cells 35), border Single,
              borderColor (borderColorOf m), padding 1]
           (inventoryDetailLines m)
       ],
       box [height (Cells 2)] (inventoryHints m),
       box [height (Cells 1)] [truncated (styled m DimRole)
         "Equipped items are marked with *."],
       box [height (Cells 1), style (styled m StatusRole)]
         [truncated (styled m BodyRole) (classicStatus m)]
     ]

helpRow : String -> String -> String
helpRow keys description =
  "  " ++ padRight 29 ' ' keys ++ description

allKeysText : Keymap -> List CommandId -> String
allKeysText km cids =
  case concatMap (\cid => keysFor cid km) cids of
    [] => "unbound"
    ks => formatKeys ks

movementCommands : List CommandId
movementCommands =
  [ MoveWest, MoveSouth, MoveNorth, MoveEast
  , MoveNorthWest, MoveNorthEast, MoveSouthWest, MoveSouthEast
  ]

movementText : Keymap -> String
movementText km =
  let primaries = filter (/= "unbound")
                       (map (formatPrimary km) movementCommands)
      base = joinBy " " primaries
  in if anyArrowKeys movementCommands km
        then (if base == "" then "arrows" else base ++ " / arrows")
        else if base == "" then "unbound" else base

helpLines : Keymap -> List String
helpLines km =
  [ "Movement"
  , helpRow (movementText km) "move (8 directions)"
  , helpRow (allKeysText km [Wait, PickUp]) "wait / pick up"
  , helpRow (allKeysText km [Descend, Ascend]) "descend / ascend stairs"
  , "Items"
  , helpRow (formatKeys (keysFor Inventory km)) "inventory (a-z, Enter)"
  , helpRow (allKeysText km [Quaff, Read, Eat]) "quaff / read / eat"
  , helpRow (allKeysText km [Wield, Wear]) "wield / wear"
  , helpRow (allKeysText km [PutOnRing, TakeOff]) "put on / take off"
  , helpRow (allKeysText km [Zap, Throw]) "zap / throw (then direction)"
  , helpRow (formatKeys (keysFor Drop km)) "drop"
  , "Interface"
  , helpRow (allKeysText km [Help, Palette]) "help / command palette"
  , helpRow (allKeysText km [LogFilter, Theme, Animation])
            "log / theme / animation"
  , helpRow (formatKeys (keysFor Redraw km)) "redraw"
  , helpRow (allKeysText km [Scores, Share]) "scores / share seed"
  , helpRow (formatKeys (keysFor Quit km)) "quit"
  , helpRow "Mouse" "click map, inventory, palette"
  ]

helpExtra : List String
helpExtra =
  [ ""
  , "Symbols"
  , "  @ you   A-Z monsters   # wall   . floor   + door   < > stairs"
  , "  ) weapon   [ armor   % food   ! potion   ? scroll   / wand   = ring"
  , "  $ gold   \" amulet   ^ trap"
  , "  Bump to attack. The Amulet is on depth 26; return it to depth 1."
  , "Settings: $XDG_DATA_HOME/lambda-rogue/settings.json"
  , "Palette: Save settings / Reload settings."
  ]

helpLayout : Model -> Node Msg
helpLayout m =
  let wide = m.width >= 120 && m.height >= 40
      panelW = if wide then 100 else 80
      panelH = if wide then 30 else 24
      extra = if wide then helpExtra else []
  in box [width (Cells panelW), height (Cells panelH),
          border Single, borderColor (borderColorOf m), padding 1] (
       [line (styled m TitleRole) "lambda-rogue help"]
       ++ map (line (styled m BodyRole)) (helpLines m.keymap ++ extra)
       ++ [line (styled m DimRole) "Esc, ? or F1 closes this help."])

numberedFrom : Nat -> List a -> List (Nat, a)
numberedFrom _ [] = []
numberedFrom n (x :: xs) = (n, x) :: numberedFrom (S n) xs

paletteRow : Model -> (Nat, PaletteEntry) -> Node Msg
paletteRow m (n, entry) =
  let selected = n == m.paletteIndex
      marker = if selected then ">" else " "
      rowStyle = if selected then styled m TitleRole else styled m BodyRole
  in line rowStyle (marker ++ " " ++ padRight 26 ' ' entry.label
                    ++ "  " ++ entry.hint)

paletteEntriesInColumns : Model -> Node Msg
paletteEntriesInColumns m =
  let entries = numberedFrom 0 (paletteEntriesFor m.keymap)
      (left, right) = splitAt 11 entries
  in row [width (Cells 74)] [
       box [width (Cells 37)] (map (paletteRow m) left),
       box [width (Cells 37)] (map (paletteRow m) right)
     ]

paletteLayout : Model -> Node Msg
paletteLayout m =
  let wide = m.width >= 120 && m.height >= 40
      panelW = if wide then 90 else 78
      panelH = if wide then 28 else 20
      entries = if wide
                   then box [] (map (paletteRow m)
                                    (numberedFrom 0 (paletteEntriesFor m.keymap)))
                   else paletteEntriesInColumns m
  in box [width (Cells panelW), height (Cells panelH), border Single,
          borderColor (borderColorOf m), paddingXY 1 0] (
       [line (styled m TitleRole) "Command palette"]
       ++ [entries]
       ++ [line (styled m DimRole) "Up/Down or j/k move   Enter run   Esc close"])

resultLabel : GameOver -> String
resultLabel Won = "won"
resultLabel (Dead _) = "dead"

scoreHeader : String
scoreHeader =
  padRight 6 ' ' "Depth" ++ padRight 4 ' ' "Lv"
  ++ padRight 8 ' ' "Exp" ++ padRight 8 ' ' "Gold"
  ++ padRight 8 ' ' "Turns" ++ "Result"

scoreRow : Score -> String
scoreRow s =
  padRight 6 ' ' (show s.depth) ++ padRight 4 ' ' (show s.level)
  ++ padRight 8 ' ' (show s.exp) ++ padRight 8 ' ' (show s.gold)
  ++ padRight 8 ' ' (show s.turns) ++ resultLabel s.result

replayLabel : Maybe Bool -> String
replayLabel Nothing = "not checked"
replayLabel (Just True) = "verified"
replayLabel (Just False) = "MISMATCH"

scoreLayout : Model -> Node Msg
scoreLayout m =
  let wide = m.width >= 120 && m.height >= 40
      panelW = if wide then 90 else 78
      panelH = if wide then 30 else 24
      body = styled m BodyRole
      dim = styled m DimRole
      rows = case m.scores of
               [] => [line dim "No completed runs yet."]
               ss => map (line body . scoreRow) (take 8 ss)
      replayStyle = if m.replayOk == Just False
                       then styled m DangerRole
                       else body
  in box [width (Cells panelW), height (Cells panelH), border Single,
          borderColor (borderColorOf m), padding 1] (
       [ line (styled m TitleRole) "Scores"
       , line dim "Completed runs, newest first."
       , line (styled m HeaderRole) scoreHeader
       ] ++ rows ++
       [ line dim "------------"
       , line body ("Seed: " ++ seedHex m.game.seed)
       , line replayStyle ("Replay: " ++ replayLabel m.replayOk)
       , line dim "P replays from the start.  Esc, S or Enter closes."
       ])

shareLayout : Model -> Node Msg
shareLayout m =
  let wide = m.width >= 120 && m.height >= 40
      panelW = if wide then 90 else 78
      panelH = if wide then 30 else 24
      body = styled m BodyRole
      dim = styled m DimRole
  in box [width (Cells panelW), height (Cells panelH), border Single,
          borderColor (borderColorOf m), padding 1] (
       [ line (styled m TitleRole) "Share seed"
       , line body ("Seed: " ++ seedHex m.game.seed)
       , line dim "Give this seed to another player."
       , line dim "Same seed + same commands = same run."
       , line dim "------------"
       , line body ("Depth " ++ show m.game.depth
                     ++ "   Level " ++ show m.game.player.level
                     ++ "   Turn " ++ show m.game.turn)
       , line body ("Recorded commands: "
                     ++ show (length m.replay.commands))
       , line body ("Replay: " ++ replayLabel m.replayOk)
       , line dim "------------"
       , line body "c or Enter copies the seed to the clipboard."
       , line dim "Esc or Ctrl-S closes."
       ])

tooSmall : Model -> Node Msg
tooSmall m =
  box [width (Cells m.width), height (Cells m.height),
       align Center, justify JCenter] [
    box [height (Cells 3), align Center] [
      truncated (styled m DangerRole)
        ("Terminal too small: need 80x24, have "
         ++ show m.width ++ "x" ++ show m.height)
    ]
  ]

centered : Model -> Node Msg -> Node Msg
centered m content =
  box [width (Cells m.width), height (Cells m.height),
       align Center, justify JCenter] [content]

public export
view : Model -> Node Msg
view m =
  if m.width < 80 || m.height < 24
     then tooSmall m
     else if m.helpOpen
             then centered m (helpLayout m)
     else if m.paletteOpen
             then centered m (paletteLayout m)
     else if m.scoreOpen
             then centered m (scoreLayout m)
     else if m.shareOpen
             then centered m (shareLayout m)
     else if m.inventoryOpen
             then if m.width >= 120 && m.height >= 40
                     then centered m (inventoryWideLayout m)
                     else centered m (inventoryLayout m)
     else if m.width >= 120 && m.height >= 40
             then centered m (wideLayout m)
             else centered m (classicLayout m)
