||| The two layouts: the classic 80x24 screen and a 120x40 wide screen.
module LambdaRogue.App.View

import Data.List
import Data.Maybe
import Data.String
import LambdaRogue.App.Catalog
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
import LambdaRogue.UI.Animation
import LambdaRogue.UI.LogView
import LambdaRogue.UI.MapView
import LambdaRogue.UI.Theme
import LambdaRogue.Version
import TermUI.Len
import TermUI.Node
import TermUI.Style
import TermUI.Width

%default covering

||| The presentation style of one semantic slot in the current theme.
styled : Model -> StyleRole -> Style
styled m role = styleFor m.theme role

t : Model -> TextKey -> String
t m key = uiText m.language key

tf : Model -> TextKey -> List String -> String
tf m key args = uiTextArgs m.language key args

logFilterText : Model -> String
logFilterText m =
  case m.logFilter of
    AllMessages => t m LogAll
    CombatMessages => t m LogCombat
    ItemMessages => t m LogItems
    SystemMessages => t m LogSystem
    WarningMessages => t m LogWarnings

speedText : Model -> PlaybackSpeed -> String
speedText m SlowPlayback = t m ReplaySlow
speedText m NormalPlayback = t m ReplayNormal
speedText m FastPlayback = t m ReplayFast

replayLabel : Model -> Maybe Bool -> String
replayLabel m Nothing = t m NotChecked
replayLabel m (Just True) = t m ReplayVerified
replayLabel m (Just False) = t m ReplayMismatch

borderColorOf : Model -> Color
borderColorOf m = (styled m BorderRole).fg

line : Style -> String -> Node Msg
line s t = box [height (Cells 1)] [truncated s t]

||| Pad with spaces up to a terminal column width.  `String.length` counts
||| characters, but Japanese glyphs occupy two cells, so aligned columns
||| must use the same width table as termui's renderer.
padWidth : Len -> String -> String
padWidth target s =
  s ++ pack (replicate
               (integerToNat (cast (monus target (stringWidth s)))) ' ')

||| Cut a string to a terminal column width without splitting a wide glyph.
fitWidth : Len -> String -> String
fitWidth target s = pack (go target (unpack s))
  where
    go : Len -> List Char -> List Char
    go _ [] = []
    go room (c :: cs) =
      let w = charWidth c
      in if w > room then [] else c :: go (monus room w) cs

||| One fixed-width table cell.  Padding and cutting are display-aware, so
||| English and Japanese rows line up in the same columns.
cell : Len -> String -> String
cell width value = padWidth width (fitWidth width value)

joinCells : List Len -> List String -> String
joinCells [] _ = ""
joinCells _ [] = ""
joinCells (w :: ws) (v :: vs) = cell w v ++ joinCells ws vs

hpBar : Player -> String
hpBar p =
  let raw = if p.maxHp <= 0 then 0 else (p.hp * 10) `div` p.maxHp
      filled = min 10 (integerToNat (cast (max 0 raw)))
  in "[" ++ pack (replicate filled '#') ++ pack (replicate (10 `minus` filled) '-') ++ "]"

gameOverText : Model -> Game -> String
gameOverText m g =
  case g.over of
    Nothing => ""
    Just (Dead cause) =>
      tf m Dead [deathName m.language cause]
    Just Won => t m Won

classicStatus : Model -> String
classicStatus m =
  let p = m.game.player
  in t m LabelDlvl ++ " " ++ show m.game.depth
     ++ "  " ++ t m LabelLevel ++ " " ++ show p.level
     ++ "  " ++ t m LabelHp ++ " " ++ show p.hp ++ "/" ++ show p.maxHp
     ++ "  " ++ t m LabelStrength ++ " " ++ show (effectiveStrength p)
     ++ "  " ++ t m LabelGold ++ " " ++ show p.gold
     ++ "  " ++ t m LabelExp ++ " " ++ show p.exp
                        ++ "/" ++ show (expForNext p.level)
     ++ "  " ++ t m LabelTurn ++ " " ++ show m.game.turn
     ++ "  " ++ t m LabelFood ++ " "
                        ++ hungerName m.language (hungerState p.hunger)
     ++ gameOverText m m.game

||| A ten-cell progress bar for the replay's command position.
progressBar : Nat -> Nat -> String
progressBar finished count =
  let filled = if count == 0
                  then 0
                  else length (takeWhile (\k => (k + 1) * count <= finished * 10)
                                         [1 .. 10])
  in "[" ++ pack (replicate filled '#')
       ++ pack (replicate (10 `minus` filled) '-') ++ "]"

playbackText : Model -> Playback -> String
playbackText m pb =
  tf m ReplayBar [show pb.played, show pb.commandCount]
  ++ progressBar pb.played pb.commandCount
  ++ "  " ++ speedText m pb.speed
  ++ (if pb.done then "  " ++ t m ReplayComplete
      else if pb.playing then "  " ++ t m ReplayPlaying
      else "  " ++ t m ReplayPaused)
  ++ "  " ++ replayLabel m pb.verified
  ++ "   " ++ t m ReplayControls

header : Model -> String
header m =
  case m.playback of
    Just pb => playbackText m pb
    Nothing =>
      t m Brand ++ " " ++ version
      ++ "   " ++ t m LabelDepth ++ " " ++ show m.game.depth
      ++ "   " ++ t m LabelLevel ++ " " ++ show m.game.player.level
      ++ "   " ++ t m LabelTurn ++ " " ++ show m.game.turn
      ++ "   " ++ t m LabelLog ++ " " ++ logFilterText m
      ++ "   " ++ t m LabelTheme ++ " " ++ show m.theme
      ++ "   " ++ t m LabelSeed ++ " " ++ seedHex m.game.seed

floorItem : Game -> Maybe Item
floorItem g =
  find (\i => case i.location of
                OnFloor d _ => d == g.depth
                InPack => False
                CarriedBy _ => False)
       g.items

monsterLine : Model -> String
monsterLine m =
  let g = m.game
  in
  let ms = filter (\m => not (hasAbility Invisible m.kind)
                         || playerSeesInvisible g
                         || adjacent m.pos g.player.pos)
                  (currentLevel g).monsters
  in case ms of
       [] => t m MonstersNone
       (mo :: _) => tf m MonsterSummary
                    [show (length ms), monsterName mo.kind,
                     monsterStateName m.language mo.state, show mo.pos]

itemLine : Model -> String
itemLine m =
  let g = m.game
  in case floorItem g of
       Nothing => t m ItemNone
       Just i => case i.location of
                   OnFloor _ p => tf m ItemFloor
                                    [itemDisplayNameIn g i, show p]
                   InPack => tf m ItemPack [itemDisplayNameIn g i]
                   CarriedBy _ => tf m ItemCarried [itemDisplayNameIn g i]

equippedName : Model -> Game -> Maybe ItemId -> String
equippedName m g Nothing = t m EquippedNone
equippedName m g (Just iid) =
  case findPackItem g iid of
    Just i => itemDisplayNameIn g i
    Nothing => "?"

statusLine : Model -> Player -> String
statusLine m p =
  if null p.statuses
     then t m StatusNone
     else t m LabelStatus ++ ": "
          ++ concat (intersperse ", "
            (map (\s => statusName m.language s.statusKind
                        ++ "(" ++ show s.remaining ++ ")")
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
                   Just _ => [line (styled m DangerRole) (gameOverText m g)]
  in [ line title (t m LabelStatus)
     , line body (t m LabelHp ++ " " ++ show p.hp ++ "/" ++ show p.maxHp
                  ++ "  " ++ hpBar p)
     , line body (t m LabelLevel ++ " " ++ show p.level
                  ++ "  " ++ t m LabelExp ++ " " ++ show p.exp
                  ++ "/" ++ show (expForNext p.level))
     , line body (t m LabelStrength ++ " " ++ show (effectiveStrength p)
                  ++ "/" ++ show p.maxStrength
                  ++ "   " ++ t m LabelGold ++ " " ++ show p.gold)
     , line body (t m LabelFood ++ " "
                  ++ hungerName m.language (hungerState p.hunger))
     , line body (t m LabelDepth ++ " " ++ show g.depth
                  ++ "   " ++ t m LabelTurn ++ " " ++ show g.turn)
     , line body (t m LabelPos ++ " " ++ show p.pos)
     , line body (t m LabelSeed ++ " " ++ seedHex g.seed)
     , line dim "------------"
     , line body (t m LabelWeapon ++ ": " ++ equippedName m g p.wielded)
     , line body (t m LabelArmor ++ ": " ++ equippedName m g p.worn)
     , line body (t m LabelRings ++ ": " ++ equippedName m g p.leftRing
                  ++ " / " ++ equippedName m g p.rightRing)
     , line body (statusLine m p)
     , line dim "------------"
     , line body (t m LabelVisible ++ " " ++ show (count g.visible)
                  ++ "   " ++ t m LabelExplored ++ " "
                  ++ show (count lvl.explored))
     , line body (t m LabelRooms ++ " " ++ show (length lvl.rooms)
                  ++ "   " ++ t m LabelTraps ++ " "
                  ++ show (length lvl.traps))
     , line dim "------------"
     , line body (monsterLine m)
     , line body (itemLine m)
     , line dim "------------"
     , line title (t m LabelKeys)
     , line dim (t m KeysMove)
     , line dim (t m KeysPickUpDescend)
     , line dim (t m KeysReadZapThrow)
     , line dim (t m KeysTakeOffRedrawQuit)
     , line dim (t m KeysHelpLogTheme)
     , line dim (t m KeysScoresShare)
     , line dim (t m KeysMouse)
     ] ++ overLine

directionPrompt : Model -> Maybe String
directionPrompt m =
  case m.pendingDir of
    Just (ZapDir _) => Just (t m ZapPrompt)
    Just (ThrowDir _) => Just (t m ThrowPrompt)
    Nothing => Nothing

||| Up to `n` messages matching the presentation filter, oldest first.
filteredMessages : Nat -> LogFilter -> Game -> List Message
filteredMessages n f g =
  reverse (take n (filter (\msg => messageMatches f msg.kind) g.messages))

filterPrefix : Model -> String
filterPrefix m =
  if m.logFilter == AllMessages
     then ""
     else "[" ++ logFilterText m ++ "] "

latestMessage : Model -> Node Msg
latestMessage m =
  case find (\msg => messageMatches m.logFilter msg.kind) m.game.messages of
    Nothing => truncated (styled m DimRole)
      (tf m NoMessages [logFilterText m])
    Just msg => truncated (messageStyleFor m.theme msg.kind)
      (filterPrefix m ++ renderMessage m.language msg)

latestNode : Model -> Node Msg
latestNode m =
  case m.playback of
    Just pb => truncated (styled m TitleRole) (playbackText m pb)
    Nothing => case directionPrompt m of
      Just text => truncated (styled m TitleRole) text
      Nothing =>
        case m.hover of
          Just c =>
            case describeCell m.game c of
              Just text => truncated (styled m HeaderRole) (tf m Hover [text])
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
  [ line (styled m TitleRole) (t m Minimap)
  , line (styled m DimRole) (t m MinimapYou)
  , line (styled m DimRole) (t m MinimapSymbols)
  , line (styled m DimRole) (t m MinimapOnlyExplored)
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
    [] => [line (styled m DimRole) (tf m NoMessages [logFilterText m])]
    msgs => map (\msg => line (messageStyleFor m.theme msg.kind)
                              (renderMessage m.language msg)) msgs

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
    [] => [line (styled m DimRole) (t m EmptySlot)]
    items => map (inventoryRow m) (zip letters items)

categoryName : Model -> ItemKind -> String
categoryName m (Weapon _) = t m CategoryWeapon
categoryName m (Armor _) = t m CategoryArmor
categoryName m (Food _) = t m CategoryFood
categoryName m (Potion _) = t m CategoryPotion
categoryName m (Scroll _) = t m CategoryScroll
categoryName m (Wand _) = t m CategoryWand
categoryName m (Ring _) = t m CategoryRing
categoryName m Gold = t m CategoryGold
categoryName m Amulet = t m CategoryAmulet

signed : Int32 -> String
signed n = if n >= 0 then "+" ++ show n else show n

enchantLines : Model -> Item -> List (Node Msg)
enchantLines m i =
  [line (styled m BodyRole) (tf m Enchantment [signed i.enchant])]
  ++ (if i.cursed
         then [line (styled m DangerRole) (t m CursedCannotRemove)]
         else [])

kindDetail : Model -> Item -> List (Node Msg)
kindDetail m i =
  if not (itemKnown m.game.knownKinds i)
     then [line (styled m DimRole) (t m Unidentified)]
     else case i.kind of
            Weapon _ => enchantLines m i
            Armor _ => enchantLines m i
            Ring _ => enchantLines m i
            Wand _ => [line (styled m BodyRole)
                            (tf m Charges [show i.charges])]
            Gold => [line (styled m BodyRole)
                          (tf m AmountGold [show i.count])]
            _ => []

equippedSlot : Model -> Player -> ItemId -> Maybe String
equippedSlot m p iid =
  if p.wielded == Just iid then Just (t m Wielded)
  else if p.worn == Just iid then Just (t m Worn)
  else if p.leftRing == Just iid then Just (t m LeftRing)
  else if p.rightRing == Just iid then Just (t m RightRing)
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
         [line dim (tf m WieldedLabel
           [equippedName m m.game m.game.player.wielded])]
       Armor _ =>
         [line dim (tf m WornLabel
           [equippedName m m.game m.game.player.worn])]
       Ring _ =>
         [line dim (tf m RingsLabel
           [equippedName m m.game m.game.player.leftRing ++ " / "
            ++ equippedName m m.game m.game.player.rightRing])]
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
       Nothing => [line dim (t m PackEmpty)]
       Just i =>
         [ line (styled m TitleRole) (t m ItemDetails)
         , line (styled m HeaderRole) (itemDisplayNameIn m.game i)
         , line body (tf m Slot [itemLetter m i.id, categoryName m i.kind])
         ] ++ (case equippedSlot m m.game.player i.id of
                 Just s => [line (styled m HeaderRole) (tf m Equipped [s])]
                 Nothing => [line dim (t m InPack)])
           ++ kindDetail m i
           ++ (if i.protected
                  then [line body (t m ProtectedFromTheft)]
                  else [])
           ++ comparisonLines m i
           ++ [ line dim "------------"
              , line dim (t m EnterUses)
              , line dim (t m SelectSlot)
              ]

inventoryHints : Model -> List (Node Msg)
inventoryHints m =
  let dim = styled m DimRole
  in [ line dim (t m InventoryHelp1)
     , line dim (t m InventoryHelp2)
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
      title = tf m InventoryTitle [show count, show maxPack]
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
      title = tf m InventoryTitle [show count, show maxPack]
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
         (t m InventoryEquippedNote)],
       box [height (Cells 1), style (styled m StatusRole)]
         [truncated (styled m BodyRole) (classicStatus m)]
     ]

helpRow : String -> String -> String
helpRow keys description =
  "  " ++ padWidth 29 keys ++ description

allKeysText : Model -> List CommandId -> String
allKeysText m cids =
  case concatMap (\cid => keysFor cid m.keymap) cids of
    [] => t m HelpUnbound
    ks => formatKeys ks

movementCommands : List CommandId
movementCommands =
  [ MoveWest, MoveSouth, MoveNorth, MoveEast
  , MoveNorthWest, MoveNorthEast, MoveSouthWest, MoveSouthEast
  ]

movementText : Model -> String
movementText m =
  let primaries = filter (/= t m HelpUnbound)
                       (map (formatPrimary m.keymap) movementCommands)
      base = joinBy " " primaries
  in if anyArrowKeys movementCommands m.keymap
        then (if base == ""
                 then t m HelpArrows
                 else base ++ " / " ++ t m HelpArrows)
        else if base == "" then t m HelpUnbound else base

helpLines : Model -> List String
helpLines m =
  let km = m.keymap
  in [ t m HelpMovement
     , helpRow (movementText m) (t m HelpMove)
     , helpRow (allKeysText m [Wait, Search, PickUp])
               (t m HelpWaitSearchPickUp)
     , helpRow (allKeysText m [Descend, Ascend]) (t m HelpStairs)
     , t m HelpItems
     , helpRow (formatKeys (keysFor Inventory km)) (t m HelpInventory)
     , helpRow (allKeysText m [Quaff, Read, Eat]) (t m HelpQuaffReadEat)
     , helpRow (allKeysText m [Wield, Wear]) (t m HelpWieldWear)
     , helpRow (allKeysText m [PutOnRing, TakeOff]) (t m HelpPutOnTakeOff)
     , helpRow (allKeysText m [Zap, Throw]) (t m HelpZapThrow)
     , helpRow (formatKeys (keysFor Drop km)) (t m HelpDrop)
     , t m HelpInterface
     , helpRow (allKeysText m [Help, Palette]) (t m HelpHelpPalette)
     , helpRow (allKeysText m [LogFilter, Theme, Animation])
               (t m HelpLogThemeAnimation)
     , helpRow (formatKeys (keysFor Redraw km)) (t m HelpRedraw)
     , helpRow (allKeysText m [Scores, Share, ReplayBrowser])
               (t m HelpScoresShare)
     , helpRow (formatKeys (keysFor Quit km)) (t m HelpQuit)
     , helpRow (t m HelpMouseLabel) (t m HelpMouse)
     ]

helpExtra : Model -> List String
helpExtra m =
  [ ""
  , t m HelpSymbols
  , t m HelpSymbols1
  , t m HelpSymbols2
  , t m HelpSymbols3
  , t m HelpTactics
  , t m HelpSettings
  , t m HelpPaletteHint
  , t m HelpReplay
  , t m HelpAccessibility
  ]

helpLayout : Model -> Node Msg
helpLayout m =
  let wide = m.width >= 120 && m.height >= 40
      panelW = if wide then 100 else 80
      panelH = if wide then 32 else 24
      extra = if wide then helpExtra m else []
  in box [width (Cells panelW), height (Cells panelH),
          border Single, borderColor (borderColorOf m), padding 1] (
       [line (styled m TitleRole) (t m HelpTitle)]
       ++ map (line (styled m BodyRole)) (helpLines m ++ extra)
       ++ [line (styled m DimRole) (t m HelpClose)])

numberedFrom : Nat -> List a -> List (Nat, a)
numberedFrom _ [] = []
numberedFrom n (x :: xs) = (n, x) :: numberedFrom (S n) xs

public export
paletteRowText : Model -> (Nat, PaletteEntry) -> String
paletteRowText m (n, entry) =
  let marker = if n == m.paletteIndex then ">" else " "
      hint = case entry.action of
               CycleAnimationSpeed => animationSpeedId m.ui.animationSpeed
               _ => entry.hint
  in marker ++ " " ++ padWidth 26 entry.label ++ "  " ++ hint

paletteRow : Model -> (Nat, PaletteEntry) -> Node Msg
paletteRow m row =
  let selected = fst row == m.paletteIndex
      rowStyle = if selected then styled m TitleRole else styled m BodyRole
  in line rowStyle (paletteRowText m row)

paletteEntriesInColumns : Model -> Node Msg
paletteEntriesInColumns m =
  let entries = numberedFrom 0 (paletteEntriesForLang m.language m.keymap)
      (left, right) = splitAt 11 entries
  in row [width (Cells 74)] [
       box [width (Cells 37)] (map (paletteRow m) left),
       box [width (Cells 37)] (map (paletteRow m) right)
     ]

paletteLayout : Model -> Node Msg
paletteLayout m =
  let wide = m.width >= 120 && m.height >= 40
      panelW = if wide then 90 else 78
      -- Two entries were added for animation speed and the replay browser;
      -- the wide layout needs two more rows to keep its controls visible.
      panelH = if wide then 32 else 22
      entries = if wide
                   then box [] (map (paletteRow m)
                                    (numberedFrom 0
                                      (paletteEntriesForLang m.language m.keymap)))
                   else paletteEntriesInColumns m
  in box [width (Cells panelW), height (Cells panelH), border Single,
          borderColor (borderColorOf m), paddingXY 1 0] (
       [line (styled m TitleRole) (t m PaletteTitle)]
       ++ [entries]
       ++ [line (styled m DimRole) (t m PaletteControls)])

replayBrowserRow : Model -> (Nat, String) -> Node Msg
replayBrowserRow m (n, name) =
  let selected = n == m.ui.replayIndex
      marker = if selected then ">" else " "
      style = if selected then styled m TitleRole else styled m BodyRole
  in line style (marker ++ " " ++ name)

replayBrowserLayout : Model -> Node Msg
replayBrowserLayout m =
  let wide = m.width >= 120 && m.height >= 40
      panelW = if wide then 90 else 78
      panelH = if wide then 30 else 24
      names = m.ui.replayFiles
      visible = take (if wide then 24 else 18) (numberedFrom 0 names)
      rows = if null names
                then [line (styled m DimRole) (t m ReplayBrowserEmpty)]
                else map (replayBrowserRow m) visible
      errorRows = case m.ui.replayError of
                    Nothing => []
                    Just _ => [line (styled m DangerRole)
                                    (t m ReplayBrowserError)]
  in box [width (Cells panelW), height (Cells panelH), border Single,
          borderColor (borderColorOf m), paddingXY 1 0] (
       [line (styled m TitleRole) (t m ReplayBrowserTitle)]
       ++ rows
       ++ errorRows
       ++ [line (styled m DimRole) (t m ReplayBrowserControls)])

resultLabel : Model -> GameOver -> String
resultLabel m Won = t m ResultWon
resultLabel m (Dead _) = t m ResultDead

||| The recorded cause of death, shown beside the result.  A victory has no
||| cause, so its cell stays blank.
causeLabel : Model -> GameOver -> String
causeLabel m Won = ""
causeLabel m (Dead cause) = deathName m.language cause

||| Column widths in terminal cells.  The seven columns exactly fill the
||| panel's usable width (74 cells on 80x24, 86 cells on 120x40), and the
||| Japanese headers fit every one of them.
scoreColumns : Model -> List Len
scoreColumns m =
  let causeWidth = if m.width >= 120 && m.height >= 40 then 40 else 28
  in [7, 8, 8, 8, 8, 7, causeWidth]

public export
scoreHeader : Model -> String
scoreHeader m =
  joinCells (scoreColumns m)
    [ t m ScoreDepth, t m ScoreLv, t m ScoreExp, t m ScoreGold
    , t m ScoreTurns, t m ScoreResult, t m ScoreCause ]

public export
scoreRow : Model -> Score -> String
scoreRow m s =
  joinCells (scoreColumns m)
    [ show s.depth, show s.level, show s.exp, show s.gold, show s.turns
    , resultLabel m s.result, causeLabel m s.result ]

scoreLayout : Model -> Node Msg
scoreLayout m =
  let wide = m.width >= 120 && m.height >= 40
      panelW = if wide then 90 else 78
      panelH = if wide then 30 else 24
      body = styled m BodyRole
      dim = styled m DimRole
      rows = case m.scores of
               [] => [line dim (t m NoScores)]
               ss => map (line body . scoreRow m) (take 8 ss)
      replayStyle = if m.replayOk == Just False
                       then styled m DangerRole
                       else body
  in box [width (Cells panelW), height (Cells panelH), border Single,
          borderColor (borderColorOf m), padding 1] (
       [ line (styled m TitleRole) (t m Scores)
       , line dim (t m ScoresSubtitle)
       , line (styled m HeaderRole) (scoreHeader m)
       ] ++ rows ++
       [ line dim "------------"
       , line body (tf m ScoreSeed [seedHex m.game.seed])
       , line replayStyle (tf m ScoreReplay [replayLabel m m.replayOk])
       , line dim (t m ScoreControls)
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
       [ line (styled m TitleRole) (t m ShareTitle)
       , line body (tf m ShareSeed [seedHex m.game.seed])
       , line dim (t m ShareGive)
       , line dim (t m ShareRule)
       , line dim (tf m ShareStart [seedHex m.game.seed])
       , line dim "------------"
       , line body (tf m ShareDepthLine
                      [show m.game.depth, show m.game.player.level,
                       show m.game.turn])
       , line body (tf m ShareCommands [show (length m.replay.commands)])
       , line body (tf m ShareReplay [replayLabel m m.replayOk])
       , line dim "------------"
       , line body (t m ShareCopy)
       , line dim (t m ShareClose)
       ])

tooSmall : Model -> Node Msg
tooSmall m =
  box [width (Cells m.width), height (Cells m.height),
       align Center, justify JCenter] [
    box [height (Cells 3), align Center] [
      truncated (styled m DangerRole)
        (tf m TerminalTooSmall [show m.width, show m.height])
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
     else if m.ui.replayBrowserOpen
             then centered m (replayBrowserLayout m)
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
