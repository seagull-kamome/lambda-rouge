||| Seeded dungeon generation.
|||
||| The generator uses the classic 3x3 room-slot layout: each slot gets a
||| rectangular room, and adjacent rooms are joined by L-shaped corridors.
||| All randomness comes from `Rng`, so the same seed produces the same
||| level, monsters, items and traps.
module LambdaRogue.Core.Dungeon

import Data.List
import Data.Maybe
import Data.Vect
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Fov
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Item
import LambdaRogue.Core.Monster
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types

%default covering

slotW, slotH : Int32
slotW = 26
slotH = 7

||| A uniformly distributed integer in `lo .. hi` (inclusive).
randInt : Int32 -> Int32 -> Rng -> (Int32, Rng)
randInt lo hi g =
  if hi <= lo
     then (lo, g)
     else let (v, g') = uniform (cast (hi - lo + 1)) g
          in (lo + cast v, g')

carveRect : Coord -> Int32 -> Int32 -> Tile -> Grid -> Grid
carveRect (MkCoord x0 y0) w h t g =
  foldl (\acc, xy => setTile (uncurry MkCoord xy) t acc) g
    [(x, y) | x <- range x0 (x0 + w - 1), y <- range y0 (y0 + h - 1)]

public export
roomCenter : Room -> Coord
roomCenter r = MkCoord (r.x + r.w `div` 2) (r.y + r.h `div` 2)

public export
roomCells : Room -> List Coord
roomCells r =
  [MkCoord x y | x <- range r.x (r.x + r.w - 1),
                 y <- range r.y (r.y + r.h - 1)]

public export
allRoomCells : List Room -> List Coord
allRoomCells = concatMap roomCells

public export
roomsOverlap : Room -> Room -> Bool
roomsOverlap a b =
  not (a.x + a.w <= b.x || b.x + b.w <= a.x
       || a.y + a.h <= b.y || b.y + b.h <= a.y)

genRoom : Int32 -> Int32 -> Rng -> (Room, Rng)
genRoom sx sy g0 =
  let (w, g1) = randInt 4 10 g0
      (h, g2) = randInt 3 5 g1
      (x, g3) = randInt (sx + 1) (sx + slotW - 1 - w) g2
      (y, g4) = randInt (sy + 1) (sy + slotH - 1 - h) g3
      (dark, g5) = chance 20 g4
  in (MkRoom x y w h dark, g5)

slotCoords : List (Int32, Int32)
slotCoords =
  [(1 + c * slotW, 1 + r * slotH) | r <- range 0 2, c <- range 0 2]

genRooms : Rng -> (List Room, Rng)
genRooms g = go slotCoords g []
  where
    go : List (Int32, Int32) -> Rng -> List Room -> (List Room, Rng)
    go [] g acc = (reverse acc, g)
    go ((sx, sy) :: rest) g acc =
      let (r, g') = genRoom sx sy g
      in go rest g' (r :: acc)

carveRooms : List Room -> Grid -> Grid
carveRooms rs g =
  foldl (\acc, r => carveRect (MkCoord r.x r.y) r.w r.h Floor acc) g rs

carveCell : Coord -> Grid -> Grid
carveCell c g =
  case tileAt g c of
    Just Rock => setTile c Corridor g
    _ => g

carveH : Int32 -> Int32 -> Int32 -> Grid -> Grid
carveH x0 x1 y g =
  foldl (\acc, x => carveCell (MkCoord x y) acc) g
    (range (min x0 x1) (max x0 x1))

carveV : Int32 -> Int32 -> Int32 -> Grid -> Grid
carveV x y0 y1 g =
  foldl (\acc, y => carveCell (MkCoord x y) acc) g
    (range (min y0 y1) (max y0 y1))

setDoor : Coord -> Grid -> Grid
setDoor c g =
  case tileAt g c of
    Just Rock => setTile c (Door Closed) g
    _ => g

withinX, withinY : Room -> Int32 -> Bool
withinX r x = x >= r.x && x < r.x + r.w
withinY r y = y >= r.y && y < r.y + r.h

||| Join two rooms in the same row.  The corridor leaves the first room
||| horizontally, then turns vertically inside the second room's slot.
connectH : Room -> Room -> Grid -> Grid
connectH a b g0 =
  let ac = roomCenter a
      bc = roomCenter b
      ay = ac.y
      bx = bc.x
      g1 = setDoor (MkCoord (a.x + a.w) ay) g0
      g2 = if withinY b ay
              then setDoor (MkCoord (b.x - 1) ay) g1
              else if ay < b.y
                      then setDoor (MkCoord bx (b.y - 1)) g1
                      else setDoor (MkCoord bx (b.y + b.h)) g1
      g3 = carveH ac.x bx ay g2
      g4 = carveV bx ay bc.y g3
  in g4

||| Join two rooms in the same column, mirroring `connectH`.
connectV : Room -> Room -> Grid -> Grid
connectV a c g0 =
  let ac = roomCenter a
      cc = roomCenter c
      ax = ac.x
      cy = cc.y
      g1 = setDoor (MkCoord ax (a.y + a.h)) g0
      g2 = if withinX c ax
              then setDoor (MkCoord ax (c.y - 1)) g1
              else if ax < c.x
                      then setDoor (MkCoord (c.x - 1) cy) g1
                      else setDoor (MkCoord (c.x + c.w) cy) g1
      g3 = carveV ax ac.y cy g2
      g4 = carveH ax cc.x cy g3
  in g4

connectAll : List Room -> Grid -> Grid
connectAll [r0, r1, r2, r3, r4, r5, r6, r7, r8] g =
  let g1 = connectH r0 r1 g
      g2 = connectH r1 r2 g1
      g3 = connectV r0 r3 g2
      g4 = connectV r1 r4 g3
      g5 = connectV r2 r5 g4
      g6 = connectH r3 r4 g5
      g7 = connectH r4 r5 g6
      g8 = connectV r3 r6 g7
      g9 = connectV r4 r7 g8
      g10 = connectV r5 r8 g9
      g11 = connectH r6 r7 g10
      g12 = connectH r7 r8 g11
  in g12
connectAll _ g = g

pickCoord : List Coord -> Rng -> (Coord, Rng)
pickCoord cs g =
  case pick cs g of
    (Just c, g') => (c, g')
    (Nothing, g') => (MkCoord 1 1, g')

removeCoords : List Coord -> List Coord -> List Coord
removeCoords cs removed =
  foldl (\acc, c => filter (/= c) acc) cs removed

walkableAt : Grid -> Coord -> Bool
walkableAt g c = maybe False walkable (tileAt g c)

public export
allWalkableCells : Grid -> List Coord
allWalkableCells g =
  [MkCoord x y | y <- range 0 21, x <- range 0 79,
                 walkableAt g (MkCoord x y)]

trapKinds : List TrapKind
trapKinds = [TrapDoor, ArrowTrap, Sleep, Bear, Teleport, DartTrap, Rust, Mysterious]

spawnTraps : Depth -> List Coord -> Rng -> (List Trap, Rng)
spawnTraps depth candidates g0 =
  let (count, g1) = randInt 0 3 g0
  in go (cast count) candidates g1 []
  where
    go : Nat -> List Coord -> Rng -> List Trap -> (List Trap, Rng)
    go Z _ g acc = (reverse acc, g)
    go (S k) [] g acc = (reverse acc, g)
    go (S k) cs g acc =
      let (kindOpt, g1) = pick trapKinds g
          (coordOpt, g2) = pick cs g1
      in case (kindOpt, coordOpt) of
           (Just kind, Just c) =>
             let trap : Trap
                 trap = MkTrap c kind False
                 cs' = filter (/= c) cs
             in go k cs' g2 (trap :: acc)
           _ => (reverse acc, g2)

itemPos : Item -> Coord
itemPos i =
  case i.location of
    OnFloor _ c => c
    InPack => MkCoord 0 0
    CarriedBy _ => MkCoord 0 0

public export
record GeneratedLevel where
  constructor MkGeneratedLevel
  level : Level
  items : List Item
  rng : Rng
  nextMonsterId : MonsterId
  nextItemId : ItemId

||| Generate one level.  The caller supplies the next free monster and item
||| IDs so the whole run keeps unique IDs across levels.
public export
generateLevel : Depth -> MonsterId -> ItemId -> Rng -> GeneratedLevel
generateLevel depth nextMonster nextItem g0 =
  let (rooms, g1) = genRooms g0
      grid0 = the Grid (replicate 22 (replicate 80 Rock))
      grid1 = carveRooms rooms grid0
      grid2 = connectAll rooms grid1
      upRoom = fromMaybe (MkRoom 2 2 4 3 False) (head' rooms)
      downRoom = fromMaybe upRoom (last' rooms)
      (upPos, g2) = pickCoord (roomCells upRoom) g1
      (downPos, g3) = pickCoord (roomCells downRoom) g2
      grid3 = setTile upPos (Stairs Up) grid2
      grid4 = if depth < 26 then setTile downPos (Stairs Down) grid3 else grid3
      occupied0 = upPos :: (if depth < 26 then [downPos] else [])
      roomCandidates = removeCoords (allRoomCells rooms) occupied0
      (monsters, nextMonster', g4) =
        spawnMonsters depth roomCandidates nextMonster g3
      occupied1 = occupied0 ++ map (.pos) monsters
      amuletCandidates = removeCoords (allRoomCells rooms) occupied1
      (amulets, nextItemAfterAmulet, g5) =
        if depth == 26
           then case pick amuletCandidates g4 of
                  (Just c, g') =>
                    let amulet : Item
                        amulet = MkItem nextItem Amulet (OnFloor depth c) 1 0 False 0 False
                        amulets' : List Item
                        amulets' = [amulet]
                    in (amulets', nextItem + 1, g')
                  (Nothing, g') => ([], nextItem, g')
           else ([], nextItem, g4)
      amuletCells = map itemPos amulets
      itemCandidates = removeCoords (allRoomCells rooms) (occupied1 ++ amuletCells)
      (items, nextItem', g6) =
        spawnItems depth itemCandidates nextItemAfterAmulet g5
      occupied2 = occupied1 ++ amuletCells ++ map itemPos items
      trapCandidates = removeCoords (allWalkableCells grid4) occupied2
      (traps, g7) = spawnTraps depth trapCandidates g6
      downStairs = if depth < 26 then Just downPos else Nothing
      level : Level
      level = MkLevel depth grid4 empty rooms monsters traps
                       (Just upPos) downStairs
  in MkGeneratedLevel level (amulets ++ items) g7 nextMonster' nextItem'

||| The hand-built M1 level, kept for presentation tests and as a stable
||| fixture for the movement/combat tests.
public export
sampleLevel : Level
sampleLevel =
  let g0 = replicate 22 (replicate 80 Rock)
      g1 = carveRect (MkCoord 2 2) 20 8 Floor g0
      g2 = carveRect (MkCoord 30 2) 20 8 Floor g1
      g3 = carveRect (MkCoord 22 5) 8 1 Corridor g2
      g4 = setTile (MkCoord 22 5) (Door Open) g3
      g5 = setTile (MkCoord 3 8) (Stairs Up) g4
      g6 = setTile (MkCoord 47 8) (Stairs Down) g5
      rooms = [MkRoom 2 2 20 8 False, MkRoom 30 2 20 8 False]
      monsters = [MkMonster 1 Kestrel (MkCoord 36 5) 4 4 Asleep []]
  in MkLevel 1 g6 empty rooms monsters []
             (Just (MkCoord 3 8)) (Just (MkCoord 47 8))

public export
sampleSeed : Bits64
sampleSeed = 0x5eed5eed5eed5eed

public export
sampleGameWithSeed : Bits64 -> Game
sampleGameWithSeed seed =
  let lvl0 = sampleLevel
      player = initialPlayer (MkCoord 4 5)
      items = [newItem 1 (Food FoodRation) (OnFloor 1 (MkCoord 7 5))]
      visible = compute lvl0.tiles lvl0.rooms player.pos
      lvl1 = { explored := visible } lvl0
      welcome = MkMessage 0 StoryMsg
        "Welcome to lambda-rogue. hjkl/yubn move, . wait, , pick up, > descend, i inventory, q quit."
  in MkGame seed (fromSeed seed) 0 1 player [lvl1] items 2 2 [] []
             [welcome] Nothing visible

public export
sampleGame : Game
sampleGame = sampleGameWithSeed sampleSeed

||| A fresh run on a generated level 1.  The player starts on the up
||| stairs; descending from there uses the generated down stairs.
public export
newGame : Bits64 -> Game
newGame seed =
  let gen = generateLevel 1 1 1 (fromSeed seed)
      (appearances, rng') = rollAppearances gen.rng
      start = fromMaybe (MkCoord 1 1) gen.level.upStairs
      player = initialPlayer start
      visible = compute gen.level.tiles gen.level.rooms start
      lvl = { explored := visible } gen.level
      welcome = MkMessage 0 StoryMsg
        "Welcome to lambda-rogue. hjkl/yubn move, . wait, , pick up, i inventory, > descend, q quit."
  in MkGame seed rng' 0 1 player [lvl] gen.items
             gen.nextMonsterId gen.nextItemId [] appearances
             [welcome] Nothing visible
