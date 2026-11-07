||| Geometry: directions, coordinate arithmetic and map access.
module LambdaRogue.Core.Geometry

import Data.Fin
import Data.Vect
import LambdaRogue.Core.Types

%default covering

public export
delta : Dir -> Coord
delta N = MkCoord 0 (-1)
delta NE = MkCoord 1 (-1)
delta E = MkCoord 1 0
delta SE = MkCoord 1 1
delta S = MkCoord 0 1
delta SW = MkCoord (-1) 1
delta W = MkCoord (-1) 0
delta NW = MkCoord (-1) (-1)

public export
add : Coord -> Coord -> Coord
add (MkCoord x y) (MkCoord x' y') = MkCoord (x + x') (y + y')

public export
inBounds : Coord -> Bool
inBounds (MkCoord x y) = x >= 0 && x < 80 && y >= 0 && y < 22

public export
tileAt : Grid -> Coord -> Maybe Tile
tileAt g (MkCoord x y) =
  if not (inBounds (MkCoord x y))
     then Nothing
     else case natToFin (integerToNat (cast y)) 22 of
            Nothing => Nothing
            Just fy =>
              case natToFin (integerToNat (cast x)) 80 of
                Nothing => Nothing
                Just fx => Just (index fx (index fy g))

public export
setTile : Coord -> Tile -> Grid -> Grid
setTile (MkCoord x y) t g =
  case natToFin (integerToNat (cast y)) 22 of
    Nothing => g
    Just fy =>
      case natToFin (integerToNat (cast x)) 80 of
        Nothing => g
        Just fx => replaceAt fy (replaceAt fx t (index fy g)) g

public export
chebyshev : Coord -> Coord -> Int32
chebyshev (MkCoord x y) (MkCoord x' y') =
  max (abs (x - x')) (abs (y - y'))

public export
adjacent : Coord -> Coord -> Bool
adjacent a b = a /= b && chebyshev a b <= 1

public export
sign : Int32 -> Int32
sign n = if n < 0 then -1 else if n > 0 then 1 else 0
