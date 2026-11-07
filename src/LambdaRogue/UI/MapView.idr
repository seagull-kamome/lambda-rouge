||| Pure presentation of the game map as cells.
|||
||| This module knows about glyphs and colours, but not about `Canvas`,
||| `IO` or the terminal.  `App.Canvas` is the only module that writes the
||| result into a `TermUI.Canvas`.
module LambdaRogue.UI.MapView

import Data.List
import Data.Vect
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Item
import LambdaRogue.Core.Monster
import LambdaRogue.Core.Types
import LambdaRogue.UI.Theme
import TermUI.Style

%default covering

public export
record Cell where
  constructor MkCell
  glyph : Char
  style : Style

export
Eq Cell where
  MkCell g s == MkCell g' s' = g == g' && s == s'

public export
tileGlyph : Tile -> Char
tileGlyph Rock = '#'
tileGlyph Floor = '.'
tileGlyph Corridor = ':'
tileGlyph (Door Open) = '\''
tileGlyph (Door Closed) = '+'
tileGlyph (Door Secret) = '+'
tileGlyph (Door Locked) = '+'
tileGlyph (Stairs Up) = '<'
tileGlyph (Stairs Down) = '>'

public export
tileStyleIn : Theme -> Tile -> Style
tileStyleIn t Rock = styleFor t RockRole
tileStyleIn t Floor = styleFor t FloorRole
tileStyleIn t Corridor = styleFor t CorridorRole
tileStyleIn t (Door _) = styleFor t DoorRole
tileStyleIn t (Stairs _) = styleFor t StairsRole

||| The classic palette, kept as a convenience for callers and tests that
||| do not need to choose a theme explicitly.
public export
tileStyle : Tile -> Style
tileStyle = tileStyleIn ClassicCga

public export
monsterStyleIn : Theme -> Style
monsterStyleIn t = styleFor t MonsterRole

public export
monsterStyle : Style
monsterStyle = monsterStyleIn ClassicCga

public export
detectedMonsterStyleIn : Theme -> Style
detectedMonsterStyleIn t = styleFor t DetectedMonsterRole

public export
detectedMonsterStyle : Style
detectedMonsterStyle = detectedMonsterStyleIn ClassicCga

public export
itemGlyph : ItemKind -> Char
itemGlyph (Weapon _) = ')'
itemGlyph (Armor _) = '['
itemGlyph (Food _) = '%'
itemGlyph (Potion _) = '!'
itemGlyph (Scroll _) = '?'
itemGlyph (Wand _) = '/'
itemGlyph (Ring _) = '='
itemGlyph Gold = '$'
itemGlyph Amulet = '"'

public export
itemStyleIn : Theme -> Style
itemStyleIn t = styleFor t ItemRole

public export
itemStyle : Style
itemStyle = itemStyleIn ClassicCga

public export
detectedItemStyleIn : Theme -> Style
detectedItemStyleIn t = styleFor t DetectedItemRole

public export
detectedItemStyle : Style
detectedItemStyle = detectedItemStyleIn ClassicCga

isFood : ItemKind -> Bool
isFood (Food _) = True
isFood _ = False

public export
trapGlyph : Char
trapGlyph = '^'

public export
trapStyleIn : Theme -> Style
trapStyleIn t = styleFor t TrapRole

public export
trapStyle : Style
trapStyle = trapStyleIn ClassicCga

public export
playerStyleIn : Theme -> Style
playerStyleIn t = styleFor t PlayerRole

public export
playerStyle : Style
playerStyle = playerStyleIn ClassicCga

public export
cellOfIn : Theme -> Tile -> Cell
cellOfIn t tile = MkCell (tileGlyph tile) (tileStyleIn t tile)

public export
cellOf : Tile -> Cell
cellOf = cellOfIn ClassicCga

dimCellIn : Theme -> Tile -> Cell
dimCellIn t tile = MkCell (tileGlyph tile) (styleFor t DimCellRole)

dimCell : Tile -> Cell
dimCell = dimCellIn ClassicCga

monsterAt : Level -> Coord -> Maybe Monster
monsterAt lvl c = find (\m => m.pos == c) lvl.monsters

itemAt : Game -> Coord -> Maybe Item
itemAt g c =
  find (\i => case i.location of
                OnFloor d p => d == g.depth && p == c
                InPack => False
                CarriedBy _ => False)
       g.items

trapAt : Level -> Coord -> Maybe Trap
trapAt lvl c = find (\t => t.pos == c) lvl.traps

||| Invisible monsters are hidden until they are adjacent, the player has
||| see-invisible, or the player has the ring of see invisible.
monsterHidden : Game -> Monster -> Bool
monsterHidden g m =
  hasAbility Invisible m.kind
  && not (playerSeesInvisible g)
  && not (adjacent m.pos g.player.pos)

||| The name of a tile for the hover line.
public export
tileName : Tile -> String
tileName Rock = "wall"
tileName Floor = "floor"
tileName Corridor = "corridor"
tileName (Door Open) = "open door"
tileName (Door Closed) = "closed door"
tileName (Door Secret) = "wall"
tileName (Door Locked) = "locked door"
tileName (Stairs Up) = "stairs up"
tileName (Stairs Down) = "stairs down"

joinFeatures : List String -> String
joinFeatures [] = ""
joinFeatures (x :: xs) = x ++ concatMap (\s => " / " ++ s) xs

||| What the player knows about a cell, or `Nothing` for unexplored cells.
||| Visible monsters, items and revealed traps are named; remembered cells
||| only name the terrain.  Invisible monsters are not leaked.
public export
describeCell : Game -> Coord -> Maybe String
describeCell g c =
  let lvl = currentLevel g
      visible = getBit c.x c.y g.visible
      playerPart = if g.player.pos == c then ["you"] else []
      monsterPart =
        case monsterAt lvl c of
          Just m => if visible && not (monsterHidden g m)
                       then [monsterName m.kind] else []
          Nothing => []
      itemPart =
        case itemAt g c of
          Just i => if visible then [itemDisplayNameIn g i] else []
          Nothing => []
      trapPart =
        case trapAt lvl c of
          Just trap => if visible && trap.revealed then ["trap"] else []
          Nothing => []
      features = playerPart ++ monsterPart ++ itemPart ++ trapPart
      suffix = if null features
                  then ""
                  else "  " ++ joinFeatures features
  in if not (getBit c.x c.y lvl.explored)
        then Nothing
        else Just (show c ++ "  " ++ maybe "unknown" tileName
                     (tileAt lvl.tiles c) ++ suffix)

||| Add a visible cursor to the hovered cell without changing its glyph.
public export
highlightCell : Coord -> Maybe Coord -> Cell -> Cell
highlightCell c Nothing cell = cell
highlightCell c (Just hovered) cell =
  if c == hovered then { style := withAttr Inverse cell.style } cell else cell

||| The cell to draw at `(x, y)`, or `Nothing` when the cell is still
||| unknown.  Monsters, items and revealed traps are only shown while they
||| are visible; remembered terrain is dimmed.
public export
cellForWith : Theme -> Maybe Coord -> Game -> Coord -> Tile -> Maybe Cell
cellForWith theme hovered g c t =
  let lvl = currentLevel g
      base =
        if g.player.pos == c
           then Just (MkCell '@' (playerStyleIn theme))
           else if getBit c.x c.y g.visible
                   then case monsterAt lvl c of
                          Just m =>
                            if monsterHidden g m
                               then Just (cellOfIn theme t)
                               else Just (MkCell (monsterGlyph m.kind)
                                                 (monsterStyleIn theme))
                          Nothing =>
                            case itemAt g c of
                              Just i => Just (MkCell (itemGlyph i.kind)
                                                     (itemStyleIn theme))
                              Nothing =>
                                case trapAt lvl c of
                                  Just trap =>
                                    if trap.revealed
                                       then Just (MkCell trapGlyph
                                                         (trapStyleIn theme))
                                       else Just (cellOfIn theme t)
                                  Nothing => Just (cellOfIn theme t)
                   else if getBit c.x c.y lvl.explored
                           then case monsterAt lvl c of
                                  Just m =>
                                    if hasStatus DetectMonsters g.player
                                       && not (monsterHidden g m)
                                       then Just (MkCell (monsterGlyph m.kind)
                                                         (detectedMonsterStyleIn theme))
                                       else Just (dimCellIn theme t)
                                  Nothing =>
                                    case itemAt g c of
                                      Just i =>
                                        if hasStatus DetectFood g.player
                                           && isFood i.kind
                                           then Just (MkCell (itemGlyph i.kind)
                                                             (detectedItemStyleIn theme))
                                           else Just (dimCellIn theme t)
                                      Nothing => Just (dimCellIn theme t)
                           else Nothing
  in map (highlightCell c hovered) base

public export
cellForIn : Theme -> Game -> Coord -> Tile -> Maybe Cell
cellForIn theme = cellForWith theme Nothing

public export
cellFor : Game -> Coord -> Tile -> Maybe Cell
cellFor = cellForIn ClassicCga

||| Every cell that should be painted, row-major, in the chosen theme.
||| The hovered cell gets the inverse attribute; this is presentation only.
public export
mapCellsWith : Theme -> Maybe Coord -> Game -> List (Int32, Int32, Cell)
mapCellsWith theme hovered g =
  let lvl = currentLevel g
  in concatMap row (zip (range 0 21) (toList lvl.tiles))
  where
    row : (Int32, Vect 80 Tile) -> List (Int32, Int32, Cell)
    row (y, tiles) =
      concatMap (\(x, t) =>
                   case cellForWith theme hovered g (MkCoord x y) t of
                     Just cell => [(x, y, cell)]
                     Nothing => [])
                (zip (range 0 79) (toList tiles))

public export
mapCellsIn : Theme -> Game -> List (Int32, Int32, Cell)
mapCellsIn theme = mapCellsWith theme Nothing

public export
mapCells : Game -> List (Int32, Int32, Cell)
mapCells = mapCellsIn ClassicCga

-- Minimap ------------------------------------------------------------------
--
-- The minimap samples the 80x22 map into a small character grid.  It is
-- deliberately information-poor: explored terrain, stairs and the player.
-- Monsters, items and traps never appear, so the minimap cannot leak
-- anything the player has not seen.

||| Replace the character at `n` in a string.  Out-of-range positions leave
||| the string unchanged; the minimap only passes in-range coordinates.
setCharAt : Nat -> Char -> String -> String
setCharAt n c s = pack (go n (unpack s))
  where
    go : Nat -> List Char -> List Char
    go _ [] = []
    go Z (_ :: xs) = c :: xs
    go (S k) (x :: xs) = x :: go k xs

replaceNth : Nat -> a -> List a -> List a
replaceNth _ _ [] = []
replaceNth Z v (_ :: xs) = v :: xs
replaceNth (S k) v (x :: xs) = x :: replaceNth k v xs

nth : Nat -> List a -> Maybe a
nth Z (x :: _) = Just x
nth (S k) (_ :: xs) = nth k xs
nth _ [] = Nothing

putMini : Int32 -> Int32 -> Char -> List String -> List String
putMini mx my c rows =
  let row = integerToNat (cast my)
      col = integerToNat (cast mx)
  in case nth row rows of
       Nothing => rows
       Just old => replaceNth row (setCharAt col c old) rows

overlayCoord : Int32 -> Int32 -> Int32 -> Int32 -> Char
            -> List String -> List String
overlayCoord cols rows x y c out =
  putMini ((x * cols) `div` 80) ((y * rows) `div` 22) c out

||| The tile at the centre of one block, if it has been explored.
sampleCell : Level -> Int32 -> Int32 -> Int32 -> Int32 -> Char
sampleCell lvl x0 x1 y0 y1 =
  if x0 >= x1 || y0 >= y1
     then ' '
     else let x = (x0 + x1) `div` 2
              y = (y0 + y1) `div` 2
          in if getBit x y lvl.explored
                then case tileAt lvl.tiles (MkCoord x y) of
                       Just t => tileGlyph t
                       Nothing => ' '
                else ' '

||| A `w`x`h` minimap.  Explored blocks show their centre tile; stairs and
||| the player are overlaid explicitly so they never disappear between
||| samples.  Unexplored blocks stay blank.
public export
minimapRowsWith : Nat -> Nat -> Game -> List String
minimapRowsWith w h g =
  let lvl = currentLevel g
      cols : Int32
      cols = cast (max 1 w)
      rows : Int32
      rows = cast (max 1 h)
      rowFor : Int32 -> String
      rowFor r =
        let y0 = (r * 22) `div` rows
            y1 = ((r + 1) * 22) `div` rows
            cellForCol : Int32 -> Char
            cellForCol c =
              let x0 = (c * 80) `div` cols
                  x1 = ((c + 1) * 80) `div` cols
              in sampleCell lvl x0 x1 y0 y1
        in pack (map cellForCol (range 0 (cols - 1)))
      sampled = map rowFor (range 0 (rows - 1))
      withDown = case lvl.downStairs of
                   Just c =>
                     if getBit c.x c.y lvl.explored
                        then overlayCoord cols rows c.x c.y '>' sampled
                        else sampled
                   Nothing => sampled
      withUp = case lvl.upStairs of
                 Just c =>
                   if getBit c.x c.y lvl.explored
                      then overlayCoord cols rows c.x c.y '<' withDown
                      else withDown
                 Nothing => withDown
  in overlayCoord cols rows g.player.pos.x g.player.pos.y '@' withUp

||| The wide-layout minimap: 36x8 cells under the map.
public export
minimapRows : Game -> List String
minimapRows g = minimapRowsWith 36 8 g
