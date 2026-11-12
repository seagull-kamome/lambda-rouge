||| Seeded dungeon-generation tests.
|||
||| These tests treat the generator as a black box: they check the
||| structural invariants that the rest of the game relies on, not a
||| particular golden map.  Golden replay fixtures arrive with the replay
||| milestone.
module DungeonTest

import Data.List
import Data.Maybe
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Item
import LambdaRogue.Core.Monster
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types
import System

check : String -> Bool -> IO ()
check name ok =
  if ok
     then putStrLn ("ok   " ++ name)
     else do
       putStrLn ("FAIL " ++ name)
       exitFailure

checkAll : String -> (a -> Bool) -> List a -> IO ()
checkAll name p xs = check name (all p xs)

passable : Tile -> Bool
passable t = walkable t || openable t || t == Door Secret

walkableAt : Grid -> Coord -> Bool
walkableAt g c = maybe False walkable (tileAt g c)

neighbours : Grid -> Coord -> List Coord
neighbours g c =
  mapMaybe step [MkCoord 1 0, MkCoord (-1) 0, MkCoord 0 1, MkCoord 0 (-1)]
  where
    step : Coord -> Maybe Coord
    step d =
      let c' = add c d
      in if maybe False passable (tileAt g c')
            then Just c'
            else Nothing

||| The set of cells reachable from `from` when closed doors count as
||| passable (the player opens them by walking into them).
reachableFrom : Grid -> Coord -> Bitset
reachableFrom g from = go [from] empty
  where
    go : List Coord -> Bitset -> Bitset
    go [] seen = seen
    go (c :: cs) seen =
      if getBit c.x c.y seen
         then go cs seen
         else go (neighbours g c ++ cs) (setBit c.x c.y seen)

reachable : Grid -> Coord -> Coord -> Bool
reachable g from to = getBit to.x to.y (reachableFrom g from)

allReachable : Grid -> Coord -> Bool
allReachable g from =
  let seen = reachableFrom g from
  in all (\c => getBit c.x c.y seen) (allWalkableCells g)

countTile : Tile -> Grid -> Nat
countTile t g =
  length [MkCoord x y | y <- range 0 21, x <- range 0 79,
                        tileAt g (MkCoord x y) == Just t]

roomInBounds : Room -> Bool
roomInBounds r =
  r.x >= 0 && r.y >= 0 && r.w >= 4 && r.w <= 10 && r.h >= 3 && r.h <= 5
  && r.x + r.w <= 80 && r.y + r.h <= 22

roomsDisjoint : List Room -> Bool
roomsDisjoint [] = True
roomsDisjoint (r :: rs) =
  all (\other => not (roomsOverlap r other)) rs && roomsDisjoint rs

uniqueCoords : List Coord -> Bool
uniqueCoords cs = length (nub cs) == length cs

itemPositions : List Item -> List Coord
itemPositions [] = []
itemPositions (i :: is) =
  case i.location of
    OnFloor _ c => c :: itemPositions is
    InPack => itemPositions is
    CarriedBy _ => itemPositions is

roomsValid : Level -> Bool
roomsValid lvl =
  length lvl.rooms == 9
  && all roomInBounds lvl.rooms
  && roomsDisjoint lvl.rooms
  && all (\r => all (walkableAt lvl.tiles) (roomCells r)) lvl.rooms

stairsValid : Depth -> Level -> Bool
stairsValid d lvl =
  case (lvl.upStairs, lvl.downStairs) of
    (Just u, Just dn) =>
      d < 26
      && tileAt lvl.tiles u == Just (Stairs Up)
      && tileAt lvl.tiles dn == Just (Stairs Down)
      && u /= dn
      && reachable lvl.tiles u dn
      && countTile (Stairs Up) lvl.tiles == 1
      && countTile (Stairs Down) lvl.tiles == 1
    (Just u, Nothing) =>
      d == 26
      && tileAt lvl.tiles u == Just (Stairs Up)
      && countTile (Stairs Up) lvl.tiles == 1
      && countTile (Stairs Down) lvl.tiles == 0
    _ => False

monstersValid : Depth -> Level -> Bool
monstersValid d lvl =
  length lvl.monsters == monsterCount d
  && uniqueCoords (map (.pos) lvl.monsters)
  && all valid lvl.monsters
  where
    valid : Monster -> Bool
    valid m =
      let s = monsterSpec m.kind
      in s.minDepth <= d && d <= s.maxDepth
         && walkableAt lvl.tiles m.pos
         && m.hp > 0 && m.hp <= m.maxHp
         && (m.state == Asleep || m.state == Awake)

itemsValid : Depth -> Level -> List Item -> Bool
itemsValid d lvl items =
  length items == itemCount d + goldPileCount d + (if d == 26 then 1 else 0)
  && length (filter (\i => i.kind == Amulet) items) == (if d == 26 then 1 else 0)
  && uniqueCoords (itemPositions items)
  && all valid items
  where
    valid : Item -> Bool
    valid i =
      case i.location of
        OnFloor dd c =>
          dd == d && walkableAt lvl.tiles c && i.count > 0
          && (case i.kind of
                Gold => True
                Amulet => d == 26
                _ => i.count == 1)
        InPack => False
        CarriedBy _ => False

trapsValid : Level -> Bool
trapsValid lvl =
  length lvl.traps <= 3
  && uniqueCoords (map (.pos) lvl.traps)
  && all valid lvl.traps
  where
    valid : Trap -> Bool
    valid t =
      not t.revealed
      && walkableAt lvl.tiles t.pos
      && elem t.kind [TrapDoor, ArrowTrap, Sleep, Bear,
                      Teleport, DartTrap, Rust, Mysterious]

||| No monster, item or trap sits on a stair, and no two objects share a
||| cell.  Stairs are placed before the spawn tables run.
occupiedValid : Level -> List Item -> Bool
occupiedValid lvl items =
  let objectCells = map (.pos) lvl.monsters ++ itemPositions items
                    ++ map (.pos) lvl.traps
      stairs = catMaybes [lvl.upStairs, lvl.downStairs]
  in uniqueCoords objectCells
     && all (\c => not (elem c stairs)) objectCells

levelValid : Depth -> GeneratedLevel -> Bool
levelValid d gl =
  gl.level.depth == d
  && roomsValid gl.level
  && stairsValid d gl.level
  && monstersValid d gl.level
  && itemsValid d gl.level gl.items
  && trapsValid gl.level
  && occupiedValid gl.level gl.items
  && (case gl.level.upStairs of
        Just u => allReachable gl.level.tiles u
        Nothing => False)

depthRange : List Depth
depthRange = range 1 26

generated : List (Depth, GeneratedLevel)
generated =
  [(d, generateLevel d 1 1 (fromSeed (cast d * 1000 + 7)))
   | d <- depthRange]

checkLevels : List (Depth, GeneratedLevel) -> IO ()
checkLevels [] = putStrLn "ok   every generated level satisfies its invariants"
checkLevels ((d, gl) :: rest) =
  if levelValid d gl
     then checkLevels rest
     else do
       putStrLn ("FAIL every generated level satisfies its invariants (depth "
                 ++ show d ++ ")")
       putStrLn ("  rooms: " ++ show (roomsValid gl.level))
       putStrLn ("  stairs: " ++ show (stairsValid d gl.level))
       putStrLn ("  monsters: " ++ show (monstersValid d gl.level)
                 ++ " count " ++ show (length gl.level.monsters)
                 ++ "/" ++ show (monsterCount d))
       putStrLn ("  monster positions unique: "
                 ++ show (uniqueCoords (map (.pos) gl.level.monsters)))
       putStrLn ("  monster details: "
                 ++ show (map (\m => monsterName m.kind ++ " " ++ show m.pos
                                      ++ " hp " ++ show m.hp ++ "/" ++ show m.maxHp
                                      ++ " " ++ show m.state
                                      ++ " walkable " ++ show (walkableAt gl.level.tiles m.pos)
                                      ++ " depth " ++ show (monsterSpec m.kind).minDepth
                                      ++ ".." ++ show (monsterSpec m.kind).maxDepth)
                              gl.level.monsters))
       putStrLn ("  items: " ++ show (itemsValid d gl.level gl.items))
       putStrLn ("  traps: " ++ show (trapsValid gl.level))
       putStrLn ("  occupied: " ++ show (occupiedValid gl.level gl.items))
       putStrLn ("  reachable: "
                 ++ show (case gl.level.upStairs of
                            Just u => allReachable gl.level.tiles u
                            Nothing => False))
       exitFailure

public export
run : IO ()
run = do
  check "the depth range is 1..26" (length depthRange == 26)
  check "the generator produces nine rooms"
    (all (\(_, gl) => length gl.level.rooms == 9) generated)
  check "rooms stay inside their 3x3 slots"
    (all (\(_, gl) => all roomInBounds gl.level.rooms) generated)
  check "rooms do not overlap"
    (all (\(_, gl) => roomsDisjoint gl.level.rooms) generated)

  checkLevels generated
  checkAll "every generated level has its requested depth"
    (\(d, gl) => gl.level.depth == d) generated
  checkAll "the monster count follows the depth table"
    (\(d, gl) => length gl.level.monsters == monsterCount d) generated
  checkAll "the item count follows the depth table plus gold and the amulet"
    (\(d, gl) => length gl.items == itemCount d + goldPileCount d
                                  + (if d == 26 then 1 else 0))
    generated
  checkAll "there are at most three traps"
    (\(_, gl) => length gl.level.traps <= 3) generated
  check "the generator places secret doors"
    (any (\(_, gl) => countTile (Door Secret) gl.level.tiles > 0) generated)
  checkAll "secret doors look like walls to movement"
    (\(_, gl) =>
      all (\c => not (tileAt gl.level.tiles c == Just (Door Secret)
                      && walkableAt gl.level.tiles c))
          [MkCoord x y | y <- range 0 21, x <- range 0 79])
    generated
  checkAll "monster IDs are allocated from nextMonsterId"
    (\(_, gl) => all (\m => m.id < gl.nextMonsterId) gl.level.monsters)
    generated
  checkAll "item IDs are allocated from nextItemId"
    (\(_, gl) => all (\i => i.id < gl.nextItemId) gl.items) generated

  let lastLevel = snd (fromMaybe (1, generateLevel 1 1 1 (fromSeed 0))
                                  (last' generated))
  check "depth 26 has no down stairs"
    (lastLevel.level.depth == 26
     && isNothing lastLevel.level.downStairs
     && countTile (Stairs Down) lastLevel.level.tiles == 0)

  let a = generateLevel 7 1 1 (fromSeed 123)
      b = generateLevel 7 1 1 (fromSeed 123)
  check "the same seed generates the same level"
    (a.level == b.level && a.items == b.items && a.rng == b.rng
     && a.nextMonsterId == b.nextMonsterId && a.nextItemId == b.nextItemId)

  let c = generateLevel 3 1 1 (fromSeed 99)
      d = generateLevel 4 c.nextMonsterId c.nextItemId c.rng
  check "monster IDs continue across levels"
    (all (\m => m.id >= c.nextMonsterId) d.level.monsters)
  check "item IDs continue across levels"
    (all (\i => i.id >= c.nextItemId) d.items)

  checkAll "newGame starts on the up stairs"
    (\seed => let g = newGame seed
              in Just g.player.pos == (currentLevel g).upStairs)
    [0, 1, 42, sampleSeed]
  checkAll "newGame starts on depth 1 with one level"
    (\seed => let g = newGame seed
              in g.depth == 1 && length g.levels == 1
                 && (currentLevel g).depth == 1)
    [0, 1, 42, sampleSeed]
  checkAll "newGame has visible and explored cells"
    (\seed => let g = newGame seed
              in count g.visible > 0
                 && count (currentLevel g).explored > 0)
    [0, 1, 42, sampleSeed]

  check "the monster table has 26 kinds" (length allMonsterKinds == 26)
  check "monster kinds are unique" (length (nub allMonsterKinds) == 26)
  check "monster names are unique"
    (length (nub (map (\k => (monsterSpec k).name) allMonsterKinds)) == 26)
  check "monster glyphs are unique"
    (length (nub (map (\k => (monsterSpec k).glyph) allMonsterKinds)) == 26)
  check "monster glyphs cover A-Z"
    (map (\k => (monsterSpec k).glyph) allMonsterKinds
     == unpack "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
  check "spec names and glyphs match the kind helpers"
    (all (\k => (monsterSpec k).name == monsterName k
                && (monsterSpec k).glyph == monsterGlyph k)
         allMonsterKinds)
  check "monster abilities have no duplicates"
    (all (\k => let as = (monsterSpec k).abilities
                in length (nub as) == length as)
         allMonsterKinds)
  check "special abilities are assigned to the expected kinds"
    (hasAbility Invisible Phantom
     && hasAbility Erratic Phantom
     && hasAbility Regenerate Troll
     && hasAbility Regenerate Griffin
     && hasAbility Regenerate Vampire
     && hasAbility StealItem Nymph
     && hasAbility StealGold Leprechaun
     && hasAbility UsuallyAsleep Leprechaun
     && hasAbility UsuallyAsleep Nymph
     && hasAbility UsuallyAsleep IceMonster
     && hasAbility Freeze IceMonster
     && hasAbility FireBreath Dragon
     && hasAbility RustArmor Aquator
     && hasAbility DrainLife Vampire
     && hasAbility DrainExperience Wraith
     && hasAbility DrainStrength Rattlesnake
     && hasAbility HoldingAttack VenusFlytrap
     && hasAbility Immobile VenusFlytrap
     && hasAbility Greedy Orc
     && hasAbility MimicObject Xeroc
     && hasAbility Erratic Bat
     && hasAbility Fast Bat
     && hasAbility Fast Kestrel
     && hasAbility Fast Griffin)
  checkAll "monster specs are sane"
    (\k => let s = monsterSpec k
           in s.level > 0 && s.exp > 0
              && s.minDepth >= 1 && s.maxDepth <= 26
              && s.minDepth <= s.maxDepth)
    allMonsterKinds
  checkAll "every depth has a non-empty spawn pool"
    (\d => not (null (spawnPool d))) depthRange
  checkAll "spawn-pool members are eligible at that depth"
    (\d => all (\k => let s = monsterSpec k
                      in s.minDepth <= d && d <= s.maxDepth)
               (spawnPool d))
    depthRange
  check "depth 1 excludes deep monsters"
    (not (elem Dragon (spawnPool 1)) && not (elem Vampire (spawnPool 1)))
  check "depth 26 includes deep monsters"
    (elem Dragon (spawnPool 26) && elem Jabberwock (spawnPool 26)
     && elem BlackUnicorn (spawnPool 26))

  check "monster count starts at 2" (monsterCount 1 == 2)
  check "monster count caps at 12" (monsterCount 26 == 12)
  check "depth 26 contains exactly one amulet"
    (let gl = generateLevel 26 1 1 (fromSeed 26)
     in length (filter (\i => i.kind == Amulet) gl.items) == 1)
  check "shallower levels contain no amulet"
    (all (\(_, gl) => not (any (\i => i.kind == Amulet) gl.items))
         (take 25 generated))
  check "item count starts at 2" (itemCount 1 == 2)
  check "item count caps at 8" (itemCount 26 == 8)

  check "overlapping rooms are detected"
    (roomsOverlap (MkRoom 0 0 5 5 False) (MkRoom 4 4 5 5 False))
  check "touching rooms do not overlap"
    (not (roomsOverlap (MkRoom 0 0 5 5 False) (MkRoom 5 0 5 5 False)))

  putStrLn "dungeon tests passed"
