||| M5 tests: the search command, the searching ring, and the first
||| fidelity fixes to potion healing and the wand of magic missile.
module M5Test

import Data.List
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

contains : String -> String -> Bool
contains needle hay = isInfixOf (unpack needle) (unpack hay)

hasMessage : String -> Outcome -> Bool
hasMessage text out = any (\m => m.text == text) out.messages

hasMessageContaining : String -> Outcome -> Bool
hasMessageContaining text out = any (\m => contains text m.text) out.messages

withoutMonsters : Game -> Game
withoutMonsters g =
  let lvl : Level
      lvl = { monsters := [] } (currentLevel g)
  in updateCurrentLevel (const lvl) g

setPlayerStats : (Player -> Player) -> Game -> Game
setPlayerStats f g =
  let p : Player
      p = f g.player
  in { player := p } g

setTraps : List Trap -> Game -> Game
setTraps ts g = updateCurrentLevel (\l => { traps := ts } l) g

setTileAt : Coord -> Tile -> Game -> Game
setTileAt c t g =
  updateCurrentLevel (\l => { tiles := setTile c t l.tiles } l) g

tileAtCoord : Coord -> Game -> Maybe Tile
tileAtCoord c g = tileAt (currentLevel g).tiles c

setMonster : Monster -> Game -> Game
setMonster m g =
  let lvl : Level
      lvl = { monsters := [m] } (currentLevel g)
  in updateCurrentLevel (const lvl) g

addToPack : List Item -> Game -> Game
addToPack items g =
  let p : Player
      p = { inventory := map (.id) items ++ g.player.inventory } g.player
  in { items := g.items ++ items, player := p } g

ringItem : ItemId -> RingKind -> Item
ringItem iid k = MkItem iid (Ring k) InPack 1 0 False 0 False

equipLeft : Item -> Game -> Game
equipLeft it g =
  let p : Player
      p = { inventory := it.id :: g.player.inventory
          , leftRing := Just it.id } g.player
  in { items := it :: g.items, player := p } g

wand : ItemId -> WandKind -> Int32 -> Item
wand iid k charges = MkItem iid (Wand k) InPack 1 0 False charges False

potion : ItemId -> PotionKind -> Item
potion iid k = MkItem iid (Potion k) InPack 1 0 False 0 False

allDirs : List Dir
allDirs = [N, NE, E, SE, S, SW, W, NW]

adjacentTraps : List Trap
adjacentTraps =
  map (\c => MkTrap c ArrowTrap False)
      (map (\d => add (MkCoord 4 5) (delta d)) allDirs)

farTrap : Trap
farTrap = MkTrap (MkCoord 10 5) DartTrap False

trapAt : Coord -> Game -> Maybe Trap
trapAt c g = find (\t => t.pos == c) (currentLevel g).traps

revealedAt : Coord -> Game -> Bool
revealedAt c g = maybe False (\t => t.revealed) (trapAt c g)

base : Game
base = withoutMonsters sampleGame

searchTests : IO ()
searchTests = do
  let g = { rng := fromSeed 1 } (setTraps (adjacentTraps ++ [farTrap]) base)
      out = step Search g
  check "search consumes a turn" out.turnConsumed
  check "search does not move the player"
    (out.game.player.pos == g.player.pos)
  check "search reveals an adjacent trap"
    (any (\t => t.revealed) (currentLevel out.game).traps)
  check "search reports what it found"
    (hasMessageContaining "You found" out)
  check "search leaves distant traps hidden"
    (not (revealedAt (MkCoord 10 5) out.game))

  let quiet = step Search base
  check "searching an empty area says so"
    (hasMessage "You search but find nothing." quiet)
  check "searching an empty area still consumes a turn" quiet.turnConsumed

  let secretGame = { rng := fromSeed 1 }
                     (setTileAt (MkCoord 5 5) (Door Secret) base)
      hiddenMove = step (Move E) secretGame
  check "a hidden secret door blocks movement"
    (not hiddenMove.turnConsumed
     && hiddenMove.game.player.pos == secretGame.player.pos
     && hasMessage "There is a wall there." hiddenMove)
  check "bumping a secret door leaves it hidden"
    (tileAtCoord (MkCoord 5 5) hiddenMove.game == Just (Door Secret))

  let secretSearch = step Search secretGame
  check "search reveals an adjacent secret door as a closed door"
    (tileAtCoord (MkCoord 5 5) secretSearch.game == Just (Door Closed))
  check "search reports the secret door"
    (hasMessage "You found a secret door." secretSearch)
  check "searching for a secret door consumes a turn"
    secretSearch.turnConsumed

  let openedSecret = step (Move E) secretSearch.game
  check "a revealed secret door opens normally"
    (tileAtCoord (MkCoord 5 5) openedSecret.game == Just (Door Open)
     && hasMessage "You open the door." openedSecret)

  let farSecret = { rng := fromSeed 1 }
                    (setTileAt (MkCoord 10 5) (Door Secret) base)
      farSearch = step Search farSecret
  check "search leaves distant secret doors hidden"
    (tileAtCoord (MkCoord 10 5) farSearch.game == Just (Door Secret))

ringTests : IO ()
ringTests = do
  let ringGame = equipLeft (ringItem 500 RingSearching) base
      trapped = { rng := fromSeed 1 }
                  (setTraps [MkTrap (MkCoord 5 5) ArrowTrap False] ringGame)
      moved = step (Move N) trapped
  check "a searching ring reveals a trap after a move"
    (revealedAt (MkCoord 5 5) moved.game)
  check "a searching ring's search does not add a turn"
    (moved.game.turn == trapped.turn + 1)

  let waited = foldl (\g, _ => (step Wait g).game) trapped
                     (replicate 20 ())
  check "a searching ring does not search while waiting"
    (not (revealedAt (MkCoord 5 5) waited))

  let ringSecret = { rng := fromSeed 1 }
                     (equipLeft (ringItem 505 RingSearching)
                       (setTileAt (MkCoord 5 5) (Door Secret) base))
      movedSecret = step (Move N) ringSecret
  check "a searching ring reveals an adjacent secret door"
    (tileAtCoord (MkCoord 5 5) movedSecret.game == Just (Door Closed))

potionTests : IO ()
potionTests = do
  let heal = potion 501 PotionHealing
      low = setPlayerStats (\p => { hp := 1, maxHp := 12 } p)
              (addToPack [heal] base)
      outLow = step (Quaff 501) low
  check "healing rolls level d4"
    (outLow.game.player.hp >= 2 && outLow.game.player.hp <= 5)
  check "healing below max HP leaves max HP alone"
    (outLow.game.player.maxHp == 12)

  let heal2 = potion 502 PotionHealing
      overflow = setPlayerStats (\p => { hp := 11, maxHp := 12, level := 10 } p)
                   (addToPack [heal2] base)
      outOverflow = step (Quaff 502) overflow
  check "excess healing raises max HP by one"
    (outOverflow.game.player.maxHp == 13
     && outOverflow.game.player.hp == 13)

  let extra = potion 503 PotionExtraHealing
      extraOverflow = setPlayerStats
                        (\p => { hp := 11, maxHp := 12, level := 10 } p)
                        (addToPack [extra] base)
      outExtra = step (Quaff 503) extraOverflow
  check "extra healing raises max HP by one or two"
    (outExtra.game.player.maxHp >= 13
     && outExtra.game.player.maxHp <= 14
     && outExtra.game.player.hp == outExtra.game.player.maxHp)

wandTests : IO ()
wandTests = do
  let target = MkMonster 1 Emu (MkCoord 6 5) 100 100 Awake []
      g = setMonster target (addToPack [wand 504 WandMagicMissile 5] base)
      out = step (Zap 504 E) g
  check "magic missile deals 1d4 damage"
    (case find (\m => m.id == 1) (currentLevel out.game).monsters of
       Just m => m.hp >= 96 && m.hp <= 99
       Nothing => False)

public export
run : IO ()
run = do
  searchTests
  ringTests
  potionTests
  wandTests
  putStrLn "m5 tests passed"
