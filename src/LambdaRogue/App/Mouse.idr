||| Pure mouse policy.
|||
||| The mouse is an alternative input path: it turns screen coordinates
||| into the same `Msg` values the keyboard produces.  It never changes the
||| Core directly, never records a replay command by itself, and never
||| consumes randomness.  Keeping the coordinate arithmetic here makes it
||| testable without a terminal.
module LambdaRogue.App.Mouse

import Data.List
import Data.Maybe
import LambdaRogue.App.Model
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Game
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Item
import LambdaRogue.Core.Types
import TermUI.Input
import TermUI.Len

%default covering

nth : Nat -> List a -> Maybe a
nth Z (x :: _) = Just x
nth (S k) (_ :: xs) = nth k xs
nth _ [] = Nothing

indexOfId : ItemId -> List Item -> Maybe Nat
indexOfId iid = go 0
  where
    go : Nat -> List Item -> Maybe Nat
    go _ [] = Nothing
    go n (i :: is) = if i.id == iid then Just n else go (S n) is

public export
isWideScreen : Model -> Bool
isWideScreen m = m.width >= 120 && m.height >= 40

||| The size of the top-level layout currently on screen.  This mirrors
||| `App.View.view` exactly so mouse coordinates can be translated.
public export
layoutSize : Model -> (Len, Len)
layoutSize m =
  if m.width < 80 || m.height < 24
     then (m.width, m.height)
  else if m.helpOpen
          then if isWideScreen m then (100, 30) else (80, 24)
  else if m.paletteOpen
          then if isWideScreen m then (90, 28) else (78, 24)
  else if m.scoreOpen
          then if isWideScreen m then (90, 30) else (78, 24)
  else if m.shareOpen
          then if isWideScreen m then (90, 30) else (78, 24)
  else if m.inventoryOpen
          then if isWideScreen m then (120, 40) else (80, 24)
  else if isWideScreen m then (120, 40) else (80, 24)

||| Where the centered layout starts on the physical terminal.
public export
layoutOrigin : Model -> (Len, Len)
layoutOrigin m =
  let (w, h) = layoutSize m
  in (if m.width > w then (m.width - w) `div` 2 else 0,
      if m.height > h then (m.height - h) `div` 2 else 0)

insideRect : Len -> Len -> Len -> Len -> Len -> Len -> Bool
insideRect x y w h c r =
  c >= x && c < x + w && r >= y && r < y + h

inPanel : Model -> Len -> Len -> Bool
inPanel m c r =
  let (w, h) = layoutSize m
      (x, y) = layoutOrigin m
  in insideRect x y w h c r

||| The game cell under a physical screen cell, if the normal map is shown.
||| The map starts one row below the top of the layout in both layouts:
||| the latest-message line in classic, and the header line in wide.
public export
mapCellAt : Model -> Len -> Len -> Maybe Coord
mapCellAt m column row =
  if not (mapVisible m)
     then Nothing
     else let (x0, y0) = layoutOrigin m
              x = column - x0
              y = row - (y0 + 1)
          in if x >= 0 && x < 80 && y >= 0 && y < 22
                then Just (MkCoord x y)
                else Nothing

explored : Game -> Coord -> Bool
explored g c = getBit c.x c.y (currentLevel g).explored

floorItemAt : Game -> Coord -> Maybe Item
floorItemAt g c =
  find (\i => case i.location of
                OnFloor d p => d == g.depth && p == c
                InPack => False
                CarriedBy _ => False)
       g.items

||| One step from the player toward the clicked cell.  A click anywhere on
||| the map therefore uses the ordinary movement/attack command; the Core
||| decides whether the step is legal.
public export
directionTo : Coord -> Coord -> Maybe Dir
directionTo (MkCoord x y) (MkCoord tx ty) =
  case (sign (tx - x), sign (ty - y)) of
    (-1, -1) => Just NW
    (0, -1) => Just N
    (1, -1) => Just NE
    (-1, 0) => Just W
    (0, 0) => Nothing
    (1, 0) => Just E
    (-1, 1) => Just SW
    (0, 1) => Just S
    (1, 1) => Just SE
    _ => Nothing

mapClickMsg : Model -> Coord -> Maybe Msg
mapClickMsg m c =
  let g = m.game
      lvl = currentLevel g
  in if not (explored g c)
        then Nothing
        else case m.pendingDir of
               Just (ZapDir iid) =>
                 map (\d => Do (Zap iid d)) (directionTo g.player.pos c)
               Just (ThrowDir iid) =>
                 map (\d => Do (Throw iid d)) (directionTo g.player.pos c)
               Nothing =>
                 if c == g.player.pos
                    then case floorItemAt g c of
                           Just _ => Just (Do PickUp)
                           Nothing =>
                             case tileAt lvl.tiles c of
                               Just (Stairs Up) => Just (Do Ascend)
                               Just (Stairs Down) => Just (Do Descend)
                               _ => Nothing
                    else map (\d => Do (Move d)) (directionTo g.player.pos c)

itemAtSlot : Model -> Nat -> Maybe Item
itemAtSlot m n = nth n (packItems m.game)

||| The pack index under a click in either inventory layout.  Classic uses
||| two 40-column lists; wide uses one list at the left of the panel.
public export
inventorySlotAt : Model -> Len -> Len -> Maybe Nat
inventorySlotAt m column row =
  let (x0, y0) = layoutOrigin m
      rx = column - x0
      ry = row - y0
  in if isWideScreen m
        then if rx >= 1 && rx < 67 && ry >= 1 && ry < 36
                then Just (integerToNat (cast (ry - 1)))
                else Nothing
        else if ry >= 1 && ry < 21
                then if rx >= 0 && rx < 40
                        then Just (integerToNat (cast (ry - 1)))
                        else if rx >= 40 && rx < 80
                                then Just (integerToNat (cast (ry - 1)) + 20)
                                else Nothing
                else Nothing

inventoryWheelMsg : Model -> Bool -> Maybe Msg
inventoryWheelMsg m up =
  let items = packItems m.game
      n = length items
      current = case m.selectedItem of
                  Just iid => indexOfId iid items
                  Nothing => Nothing
      next = if n == 0
                then Nothing
                else if up
                        then Just (maybe (minus n 1)
                          (\i => if i == 0 then minus n 1 else minus i 1) current)
                        else Just (maybe 0
                          (\i => if i + 1 >= n then 0 else i + 1) current)
  in case next of
       Just k => map SelectItem (map (.id) (nth k items))
       Nothing => Nothing

inventoryClickMsg : Model -> MouseEvent -> Maybe Msg
inventoryClickMsg m e =
  if not (inPanel m e.column e.row)
     then Just CloseInventory
     else case inventorySlotAt m e.column e.row of
            Nothing => Nothing
            Just n =>
              case itemAtSlot m n of
                Nothing => Nothing
                Just i =>
                  if e.clicks >= 2
                     then Just (ActOnItem (defaultAction i) i.id)
                     else case m.inventoryIntent of
                            Just act => Just (ActOnItem act i.id)
                            Nothing => Just (SelectItem i.id)

paletteClickMsg : Model -> MouseEvent -> Maybe Msg
paletteClickMsg m e =
  if not (inPanel m e.column e.row)
     then Just ClosePalette
     else let (_, y0) = layoutOrigin m
              firstRow = y0 + 2
              hintRow = firstRow + cast paletteCount
          in if e.row == hintRow
                then Just ClosePalette
                else if e.row >= firstRow && e.row < hintRow
                        then let n = integerToNat (cast (e.row - firstRow))
                             in if e.clicks >= 2
                                   then Just (PaletteRun n)
                                   else Just (PaletteSelect n)
                        else Nothing

shareClickMsg : Model -> MouseEvent -> Maybe Msg
shareClickMsg m e =
  if not (inPanel m e.column e.row)
     then Just CloseShare
     else let (_, y0) = layoutOrigin m
              copyRow = y0 + 11
              closeRow = y0 + 12
          in if e.row == copyRow
                then Just CopySeed
                else if e.row == closeRow
                        then Just CloseShare
                        else Nothing

overLog : Model -> Len -> Len -> Bool
overLog m column row =
  let (x0, y0) = layoutOrigin m
      x = column - x0
      y = row - y0
  in if isWideScreen m
        then x >= 0 && x < 120 && y >= 31 && y < 39
        else x >= 0 && x < 80 && y == 0

mainMouseMsg : Model -> MouseEvent -> Maybe Msg
mainMouseMsg m e =
  case (e.button, e.action) of
    (LeftButton, ButtonDown) =>
      case mapCellAt m e.column e.row of
        Just c => mapClickMsg m c
        Nothing => Nothing
    (_, Move) => Just (HoverCell (mapCellAt m e.column e.row))
    (_, Drag) => Just (HoverCell (mapCellAt m e.column e.row))
    (WheelUp, _) =>
      if overLog m e.column e.row then Just CycleLogFilterBack else Nothing
    (WheelDown, _) =>
      if overLog m e.column e.row then Just CycleLogFilter else Nothing
    _ => Nothing

||| Translate one raw mouse event into the app's ordinary messages.
public export
mouseMsg : Model -> MouseEvent -> Maybe Msg
mouseMsg m e =
  if playbackOpen m
     then Nothing
  else if m.width < 80 || m.height < 24
     then Nothing
     else if m.helpOpen
             then case (e.button, e.action) of
                    (LeftButton, ButtonDown) => Just CloseHelp
                    (RightButton, ButtonDown) => Just CloseHelp
                    _ => Nothing
     else if m.paletteOpen
             then case (e.button, e.action) of
                    (LeftButton, ButtonDown) => paletteClickMsg m e
                    (RightButton, ButtonDown) => Just ClosePalette
                    (WheelUp, _) => Just PalettePrev
                    (WheelDown, _) => Just PaletteNext
                    _ => Nothing
     else if m.scoreOpen
             then case (e.button, e.action) of
                    (LeftButton, ButtonDown) => Just CloseScores
                    (RightButton, ButtonDown) => Just CloseScores
                    _ => Nothing
     else if m.shareOpen
             then case (e.button, e.action) of
                    (LeftButton, ButtonDown) => shareClickMsg m e
                    (RightButton, ButtonDown) => Just CloseShare
                    _ => Nothing
     else if m.inventoryOpen
             then case (e.button, e.action) of
                    (LeftButton, ButtonDown) => inventoryClickMsg m e
                    (RightButton, ButtonDown) => Just CloseInventory
                    (WheelUp, _) =>
                      if inPanel m e.column e.row
                         then inventoryWheelMsg m True
                         else Nothing
                    (WheelDown, _) =>
                      if inPanel m e.column e.row
                         then inventoryWheelMsg m False
                         else Nothing
                    _ => Nothing
             else mainMouseMsg m e
