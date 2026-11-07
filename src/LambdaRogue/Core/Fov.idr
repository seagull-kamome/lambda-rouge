||| A small, pure field of view.
|||
||| Rogue lights a room as a whole, so a lit room containing the player is
||| revealed completely.  Outside rooms, a line-of-sight test within a
||| short radius reveals corridors and the walls that bound them.  The
||| real lighting rules will be checked against the original during the
||| fidelity audit; this module is the only place that decides visibility.
module LambdaRogue.Core.Fov

import Data.List
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Types

%default covering

||| How far line of sight reaches outside a lit room.
public export
sightRadius : Int32
sightRadius = 12

||| Does this tile block sight?  A closed door does; the cell itself is
||| still drawn when a ray reaches it.
public export
transparent : Tile -> Bool
transparent Rock = False
transparent (Door Closed) = False
transparent (Door Secret) = False
transparent (Door Locked) = False
transparent _ = True

||| Bresenham's line from `from` to `to`, both endpoints included.
public export
line : Coord -> Coord -> List Coord
line (MkCoord x0 y0) (MkCoord tx ty) =
  let dx = abs (tx - x0)
      dy = -abs (ty - y0)
      fuel = integerToNat (cast (abs (tx - x0) + abs (ty - y0) + 1))
      sx = if x0 < tx then 1 else -1
      sy = if y0 < ty then 1 else -1
  in go fuel x0 y0 (dx + dy) sx sy dx dy
  where
    go : Nat -> Int32 -> Int32 -> Int32 -> Int32 -> Int32 -> Int32 -> Int32 -> List Coord
    go Z x y _ _ _ _ _ = [MkCoord x y]
    go (S k) x y err sx sy dx dy =
      let here = MkCoord x y in
      if x == tx && y == ty
         then [here]
         else let e2 = 2 * err
                  (x', err1) = if e2 >= dy then (x + sx, err + dy) else (x, err)
                  (y', err2) = if e2 <= dx then (y + sy, err1 + dx) else (y, err1)
              in here :: go k x' y' err2 sx sy dx dy

||| Can `from` see `to`?  The target itself may be a wall or a closed door;
||| only the cells before it have to be transparent.
public export
canSee : Grid -> Coord -> Coord -> Bool
canSee g from to =
  case line from to of
    [] => False
    (c :: cs) =>
      case cs of
        [] => True
        (_ :: _) => all (\p => maybe False transparent (tileAt g p)) (c :: init cs)

roomContains : Room -> Coord -> Bool
roomContains r (MkCoord x y) =
  x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h

||| The room plus its one-cell wall border.
roomArea : Room -> List Coord
roomArea r =
  [MkCoord x y | x <- range (r.x - 1) (r.x + r.w),
                 y <- range (r.y - 1) (r.y + r.h)]

roomCells : List Room -> Coord -> List Coord
roomCells rooms origin =
  case find (\r => roomContains r origin && not r.dark) rooms of
    Nothing => []
    Just r => roomArea r

candidatesFor : Int32 -> Coord -> List Coord
candidatesFor radius (MkCoord x0 y0) =
  [MkCoord x y | x <- range (x0 - radius) (x0 + radius),
                 y <- range (y0 - radius) (y0 + radius),
                 inBounds (MkCoord x y),
                 (x - x0) * (x - x0) + (y - y0) * (y - y0) <= radius * radius]

candidates : Coord -> List Coord
candidates = candidatesFor sightRadius

||| The visible cells from `origin`.  `lit` controls the classic lit-room
||| shortcut; blinded vision calls this with a radius of one and no room
||| lighting.
public export
computeWith : Int32 -> Bool -> Grid -> List Room -> Coord -> Bitset
computeWith radius lit g rooms origin =
  let roomPart = if lit
                    then foldl (\bs, c => setBit c.x c.y bs) (the Bitset empty)
                               (roomCells rooms origin)
                    else the Bitset empty
      losPart = foldl (\bs, c => if canSee g origin c
                                    then setBit c.x c.y bs
                                    else bs)
                      (the Bitset empty)
                      (candidatesFor radius origin)
  in union roomPart losPart

||| The normal visible cells from `origin`.
public export
compute : Grid -> List Room -> Coord -> Bitset
compute = computeWith sightRadius True

||| Blinded vision: only the immediately adjacent cells, no lit-room bonus.
public export
computeBlinded : Grid -> List Room -> Coord -> Bitset
computeBlinded = computeWith 1 False
