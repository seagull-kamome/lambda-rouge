||| Deterministic command fuzzing for M2.
|||
||| The commands are generated from a separate RNG, so a failure is
||| reproducible from the seed and the command count.  The test checks
||| invariants after every run, not a particular map.
module FuzzTest

import Data.List
import Data.Maybe
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Geometry
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

directions : List Dir
directions = [N, NE, E, SE, S, SW, W, NW]

commandFor : Rng -> (Command, Rng)
commandFor g =
  let (n, g1) = uniform 10 g
  in case n of
       0 => (Wait, g1)
       1 => (PickUp, g1)
       2 => (Descend, g1)
       3 => (Ascend, g1)
       _ => let (d, g2) = pick directions g1
            in (Move (fromMaybe N d), g2)

runRandom : Nat -> Rng -> Game -> Game
runRandom Z _ g = g
runRandom (S k) r g =
  let (cmd, r') = commandFor r
  in runRandom k r' (step cmd g).game

monsterIds : Game -> List MonsterId
monsterIds g = concatMap (\lvl => map (.id) lvl.monsters) g.levels

itemIds : Game -> List ItemId
itemIds g = map (.id) g.items

levelDepths : Game -> List Depth
levelDepths g = map (.depth) g.levels

itemFloorDepths : List Item -> List Depth
itemFloorDepths [] = []
itemFloorDepths (i :: is) =
  case i.location of
    OnFloor d _ => d :: itemFloorDepths is
    InPack => itemFloorDepths is
    CarriedBy _ => itemFloorDepths is

inPackItems : List Item -> List Item
inPackItems [] = []
inPackItems (i :: is) =
  case i.location of
    InPack => i :: inPackItems is
    OnFloor _ _ => inPackItems is
    CarriedBy _ => inPackItems is

unique : Eq a => List a -> Bool
unique xs = length (nub xs) == length xs

invariant : Game -> Bool
invariant g =
  let lvl = currentLevel g
      monsters = lvl.monsters
      floorDepths = itemFloorDepths g.items
  in g.depth >= 1 && g.depth <= 26
     && not (null g.levels)
     && lvl.depth == g.depth
     && unique (levelDepths g)
     && unique (monsterIds g)
     && unique (itemIds g)
     && all (\i => i < g.nextMonsterId) (monsterIds g)
     && all (\i => i < g.nextItemId) (itemIds g)
     && all (\d => any (\l => l.depth == d) g.levels) floorDepths
     && g.player.hp >= 0
     && length g.player.inventory <= maxPack
     && length (inPackItems g.items) == length g.player.inventory
     && (case tileAt lvl.tiles g.player.pos of
           Just t => walkable t || openable t
           Nothing => False)
     && all (\m => maybe False walkable (tileAt lvl.tiles m.pos)) monsters
     && not (any (\m => m.pos == g.player.pos) monsters)
     && (case g.over of
           Just (Dead _) => g.player.hp == 0
           _ => True)

runFor : Bits64 -> Nat -> Game
runFor seed turns = runRandom turns (fromSeed (seed + 7)) (newGame seed)

seeds : List Bits64
seeds = [0, 1, 42, 12345, sampleSeed]

public export
run : IO ()
run = do
  checkAll "random command runs preserve the invariants"
    (\seed => invariant (runFor seed 1000)) seeds
  checkAll "random command runs are deterministic"
    (\seed => let a = runFor seed 500
                  b = runFor seed 500
              in currentLevel a == currentLevel b
                 && a.items == b.items
                 && a.rng == b.rng
                 && a.player.pos == b.player.pos
                 && a.player.hp == b.player.hp
                 && a.over == b.over)
    seeds
  check "a dead player stays dead"
    (let g = runFor 42 1000
     in case g.over of
          Just (Dead _) =>
            let g' = (step Wait g).game
            in g'.turn == g.turn && g'.rng == g.rng
               && g'.player.pos == g.player.pos
               && g'.player.hp == g.player.hp
               && g'.over == g.over
          _ => True)
  putStrLn "fuzz tests passed"
