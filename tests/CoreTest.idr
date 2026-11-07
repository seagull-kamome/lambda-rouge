||| Core turn-resolution tests for M2.
|||
||| The hand-built `sampleGame` remains the fixture for movement, doors,
||| combat, items and stairs.  Generated-dungeon properties live in
||| `DungeonTest`; combat formulas and experience live in `CombatTest`.
module CoreTest

import Data.List
import Data.Maybe
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Fov
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

runCommands : List Command -> Game -> Game
runCommands cs g = foldl (\gg, c => (step c gg).game) g cs

setPlayer : Coord -> Game -> Game
setPlayer c g =
  let p : Player
      p = { pos := c } g.player
  in { player := p } g

setArmor : Int32 -> Game -> Game
setArmor a g =
  let p : Player
      p = { armor := a } g.player
  in { player := p } g

setPlayerStats : (Player -> Player) -> Game -> Game
setPlayerStats f g =
  let p : Player
      p = f g.player
  in { player := p } g

setItems : List Item -> Game -> Game
setItems items g = { items := items } g

setTileAt : Coord -> Tile -> Game -> Game
setTileAt c t g =
  let lvl0 = currentLevel g
      lvl : Level
      lvl = { tiles := setTile c t lvl0.tiles } lvl0
  in updateCurrentLevel (const lvl) g

setTraps : List Trap -> Game -> Game
setTraps ts g =
  let lvl0 = currentLevel g
      lvl : Level
      lvl = { traps := ts } lvl0
  in updateCurrentLevel (const lvl) g

withoutMonsters : Game -> Game
withoutMonsters g =
  let lvl0 = currentLevel g
      lvl : Level
      lvl = { monsters := [] } lvl0
  in updateCurrentLevel (const lvl) g

setMonster : Monster -> Game -> Game
setMonster m g =
  let lvl0 = currentLevel g
      lvl : Level
      lvl = { monsters := [m] } lvl0
  in updateCurrentLevel (const lvl) g

monsterOf : Game -> Maybe Monster
monsterOf g = head' (currentLevel g).monsters

visibleAt : Coord -> Game -> Bool
visibleAt c g = getBit c.x c.y g.visible

exploredAt : Coord -> Game -> Bool
exploredAt c g = getBit c.x c.y (currentLevel g).explored

contains : String -> String -> Bool
contains needle hay = isInfixOf (unpack needle) (unpack hay)

hasMessage : String -> Outcome -> Bool
hasMessage text out = any (\m => m.text == text) out.messages

hasMessageContaining : String -> Outcome -> Bool
hasMessageContaining text out = any (\m => contains text m.text) out.messages

hasDoorOpened : Outcome -> Bool
hasDoorOpened out = any (\e => case e of
                                  DoorOpened _ => True
                                  _ => False)
                        out.events

hasTrapTriggered : Outcome -> Bool
hasTrapTriggered out = any (\e => case e of
                                     TrapTriggered _ _ => True
                                     _ => False)
                           out.events

sameRng : Rng -> Rng -> Bool
sameRng a b = stateHex a == stateHex b

public export
run : IO ()
run = do
  let g0 = sampleGame
      start = MkCoord 4 5
      itemPos = MkCoord 7 5
      monsterPos = MkCoord 36 5
      upPos = MkCoord 3 8
      downPos = MkCoord 47 8

  check "sample starts on the floor"
    (tileAt (currentLevel g0).tiles start == Just Floor)
  check "sample starts at turn 0" (g0.turn == 0)
  check "sample player is at (4,5)" (g0.player.pos == start)
  check "sample has one monster" (length (currentLevel g0).monsters == 1)
  check "sample has one item" (length g0.items == 1)

  check "initial FOV sees the player" (visibleAt start g0)
  check "initial FOV explores the first room" (exploredAt (MkCoord 20 8) g0)
  check "initial FOV does not see the second room"
    (not (visibleAt monsterPos g0))
  check "initial FOV has some visible cells" (count g0.visible > 0)

  let outMove = step (Move E) g0
      gMove = outMove.game
  check "move east consumes a turn" outMove.turnConsumed
  check "move east increments turn" (gMove.turn == 1)
  check "move east moves the player" (gMove.player.pos == MkCoord 5 5)
  check "move east keeps the monster asleep"
    (maybe True (\m => m.state == Asleep) (monsterOf gMove))

  let gWall = setPlayer (MkCoord 2 5) g0
      outWall = step (Move W) gWall
  check "moving into rock does not consume a turn"
    (not outWall.turnConsumed && outWall.game.turn == 0)
  check "moving into rock keeps the player in place"
    (outWall.game.player.pos == MkCoord 2 5)
  check "moving into rock warns" (hasMessage "There is a wall there." outWall)
  check "moving into rock does not consume the RNG"
    (sameRng outWall.game.rng gWall.rng)

  let gDoor = setPlayer (MkCoord 21 5) g0
      outDoor = step (Move E) gDoor
  check "an open door is walkable"
    (outDoor.turnConsumed && outDoor.game.player.pos == MkCoord 22 5)

  let gClosed = setTileAt (MkCoord 22 5) (Door Closed)
                  (setPlayer (MkCoord 21 5) (withoutMonsters g0))
      outClosed = step (Move E) gClosed
  check "walking into a closed door opens it"
    (outClosed.turnConsumed
     && tileAt (currentLevel outClosed.game).tiles (MkCoord 22 5)
        == Just (Door Open))
  check "opening a door does not move the player"
    (outClosed.game.player.pos == MkCoord 21 5)
  check "opening a door is reported"
    (hasMessage "You open the door." outClosed && hasDoorOpened outClosed)

  let gLocked = setTileAt (MkCoord 22 5) (Door Locked)
                  (setPlayer (MkCoord 21 5) (withoutMonsters g0))
      outLocked = step (Move E) gLocked
  check "a locked door blocks the player"
    (not outLocked.turnConsumed
     && outLocked.game.player.pos == MkCoord 21 5
     && hasMessage "The door is locked." outLocked)

  let gMonsterDoor = setMonster
                       (MkMonster 1 Kestrel (MkCoord 21 5) 4 4 Chasing [])
                       (setPlayer (MkCoord 23 5)
                         (setTileAt (MkCoord 22 5) (Door Closed)
                           (withoutMonsters g0)))
      outMonsterDoor = step Wait gMonsterDoor
  check "a chasing monster opens a closed door"
    (tileAt (currentLevel outMonsterDoor.game).tiles (MkCoord 22 5)
       == Just (Door Open))
  check "a monster steps into the door it opened"
    (maybe False (\m => m.pos == MkCoord 22 5) (monsterOf outMonsterDoor.game))
  check "a monster door opening is reported"
    (hasMessage "The kestrel opens the door." outMonsterDoor)

  let gCorridor = runCommands [Move E, Move E, Move E, Move E, Move E, Move E,
                       Move E, Move E, Move E, Move E, Move E, Move E,
                       Move E, Move E, Move E, Move E, Move E] g0
  check "walking toward the door reveals the corridor"
    (visibleAt (MkCoord 23 5) gCorridor)
  check "the second room is still hidden from the corridor"
    (not (visibleAt monsterPos gCorridor))

  let gRoom = setPlayer (MkCoord 31 5) g0
      outWake = step Wait gRoom
  check "entering the second room wakes the monster"
    (maybe False (\m => m.state == Chasing) (monsterOf outWake.game))
  check "waking the monster adds a message"
    (hasMessage "The kestrel wakes up." outWake)

  let outChase = step Wait outWake.game
  check "an awake monster moves toward the player"
    (maybe False (\m => m.pos /= monsterPos) (monsterOf outChase.game))

  let adjacentMonster = MkMonster 1 Kestrel (MkCoord 6 5) 4 4 Chasing []
      gAdjacent = setMonster adjacentMonster
                    (setArmor 100 (setPlayer (MkCoord 5 5) g0))
      outBite = step Wait gAdjacent
  check "an adjacent monster attacks"
    (outBite.game.player.hp < gAdjacent.player.hp)
  check "a monster hit adds a message"
    (hasMessageContaining "The kestrel hits you for" outBite)

  let weakMonster = MkMonster 1 Kestrel (MkCoord 6 5) 1 1 Chasing []
      strongPlayer = setPlayerStats (\p => { strength := 100, level := 100 } p)
                       (setPlayer (MkCoord 5 5) g0)
      gKill = setMonster weakMonster strongPlayer
      outKill = step (Move E) gKill
  check "moving into a monster kills it when damage exceeds HP"
    (isNothing (monsterOf outKill.game)
     && hasMessage "You kill the kestrel." outKill)
  check "a kill awards experience" (outKill.game.player.exp == 1)

  let missPlayer = setPlayerStats (\p => { level := -100, strength := 0 } p)
                     (setPlayer (MkCoord 5 5) g0)
      gMiss = setMonster (MkMonster 1 Kestrel (MkCoord 6 5) 4 4 Chasing [])
                 missPlayer
      outMiss = step (Move E) gMiss
  check "a player attack can miss"
    (hasMessage "You miss the kestrel." outMiss
     && maybe False (\m => m.hp == 4) (monsterOf outMiss.game))

  let gLevel = setPlayerStats (\p => { exp := 9, strength := 100, ringAccuracy := 100 } p)
                 (setPlayer (MkCoord 5 5) g0)
      gLevelKill = setMonster (MkMonster 1 Kestrel (MkCoord 6 5) 1 1 Chasing [])
                      gLevel
      outLevel = step (Move E) gLevelKill
      pLevel = outLevel.game.player
  check "enough experience raises the player's level"
    (pLevel.level == 2 && pLevel.exp == 10)
  check "a level-up leaves strength unchanged" (pLevel.strength == 100)
  check "a level-up raises maximum and current HP"
    (pLevel.maxHp > 12 && pLevel.hp > 12)
  check "a level-up adds a message"
    (hasMessage "Welcome to level 2!" outLevel)

  let gPick = runCommands [Move E, Move E, Move E] g0
      outPick = step PickUp gPick
  check "pick up consumes a turn" outPick.turnConsumed
  check "pick up adds the item to the pack"
    (outPick.game.player.inventory == [1])
  check "pick up changes the item location"
    (case outPick.game.items of
       [i] => case i.location of
                InPack => True
                _ => False
       _ => False)
  check "pick up adds a message"
    (hasMessage "You pick up the food ration." outPick)

  let outEmptyPick = step PickUp g0
  check "pick up on an empty floor does not consume a turn"
    (not outEmptyPick.turnConsumed)
  check "pick up on an empty floor warns"
    (hasMessage "There is nothing here to pick up." outEmptyPick)

  let gFull = setPlayerStats (\p => { inventory := replicate 23 1 } p)
                (setPlayer itemPos g0)
      outFull = step PickUp gFull
  check "the pack cap is 23 items"
    (not outFull.turnConsumed && hasMessage "Your pack is full." outFull)
  check "a full pack leaves the item on the floor"
    (case outFull.game.items of
       [i] => case i.location of
                OnFloor 1 _ => True
                _ => False
       _ => False)

  let gold = MkItem 1 Gold (OnFloor 1 start) 37 0 False 0 False
      gGold = setItems [gold] g0
      outGold = step PickUp gGold
  check "picking up gold increases the purse"
    (outGold.game.player.gold == 37 && null outGold.game.items)
  check "picking up gold adds a message"
    (hasMessage "You pick up 37 gold." outGold)

  let gStairs = withoutMonsters (setPlayer downPos g0)
      outStairs = step Descend gStairs
      newLevel = currentLevel outStairs.game
  check "descending consumes a turn" outStairs.turnConsumed
  check "descending increases depth" (outStairs.game.depth == 2)
  check "descending keeps the previous level"
    (length outStairs.game.levels == 2
     && maybe False (\l => l.depth == 1) (last' outStairs.game.levels))
  check "the new level is generated at depth 2" (newLevel.depth == 2)
  check "the player arrives on the up stairs"
    (Just outStairs.game.player.pos == newLevel.upStairs)
  check "descending adds a message"
    (hasMessage "You descend to level 2." outStairs)

  let gUp = withoutMonsters (setPlayer upPos g0)
      outUp = step Ascend gUp
  check "ascent without the amulet is refused"
    (not outUp.turnConsumed
     && hasMessage "You cannot return without the Amulet of Yendor." outUp)
  check "ascending away from up stairs warns"
    (hasMessage "You are not standing on Up stairs." (step Ascend g0))
  check "descending away from down stairs warns"
    (hasMessage "You are not standing on Down stairs." (step Descend g0))

  let gDeep0 = withoutMonsters (setPlayer downPos g0)
      gDeep1 : Game
      gDeep1 = { depth := 26 } gDeep0
      gDeep2 : Game
      gDeep2 = updateCurrentLevel (\lvl => { depth := 26 } lvl) gDeep1
      outDeep = step Descend gDeep2
  check "depth 26 has no further descent"
    (not outDeep.turnConsumed
     && outDeep.game.depth == 26
     && hasMessage "You cannot descend further." outDeep)

  let gTrap = setTraps [MkTrap (MkCoord 5 5) ArrowTrap False]
                (setPlayer (MkCoord 4 5) (withoutMonsters g0))
      outTrap = step (Move E) gTrap
  check "an arrow trap damages the player"
    (outTrap.game.player.hp < gTrap.player.hp)
  check "a triggered trap is revealed"
    (case (currentLevel outTrap.game).traps of
       [t] => t.revealed && t.pos == MkCoord 5 5
       _ => False)
  check "a trap is reported"
    (hasTrapTriggered outTrap
     && hasMessageContaining "You trigger a arrow trap." outTrap)

  let gTrapDoor = setTraps [MkTrap (MkCoord 5 5) TrapDoor False]
                    (setPlayer (MkCoord 4 5) (withoutMonsters g0))
      outTrapDoor = step (Move E) gTrapDoor
  check "a trapdoor drops the player to the next level"
    (outTrapDoor.game.depth == 2
     && length outTrapDoor.game.levels == 2
     && hasMessageContaining "You trigger a trapdoor." outTrapDoor)

  let gTeleport = setTraps [MkTrap (MkCoord 5 5) Teleport False]
                    (setPlayer (MkCoord 4 5) (withoutMonsters g0))
      outTeleport = step (Move E) gTeleport
  check "a teleport trap moves the player"
    (outTeleport.game.player.pos /= MkCoord 5 5)
  check "a teleport destination is walkable"
    (case tileAt (currentLevel outTeleport.game).tiles outTeleport.game.player.pos of
       Just t => walkable t
       Nothing => False)

  let gTrapDeath = setPlayerStats (\p => { hp := 1 } p)
                     (setTraps [MkTrap (MkCoord 5 5) ArrowTrap False]
                       (setPlayer (MkCoord 4 5) (withoutMonsters g0)))
      outTrapDeath = step (Move E) gTrapDeath
  check "a trap can kill the player"
    (outTrapDeath.game.over == Just (Dead (KilledByTrap ArrowTrap)))
  check "trap death leaves HP at zero"
    (outTrapDeath.game.player.hp == 0)

  let gDying = setPlayerStats (\p => { hp := 1 } p)
                 (setArmor 100 (setPlayer (MkCoord 5 5) g0))
      gDyingMonster = setMonster
                        (MkMonster 1 Kestrel (MkCoord 6 5) 4 4 Chasing [])
                        gDying
      outDeath = step Wait gDyingMonster
  check "a killing blow sets game over"
    (outDeath.game.over == Just (Dead (KilledBy Kestrel)))
  check "death sets HP to zero" (outDeath.game.player.hp == 0)
  check "death adds a message"
    (hasMessageContaining "You die... Killed by a kestrel." outDeath)
  check "a dead player cannot act"
    (let out = step (Move E) outDeath.game
     in not out.turnConsumed && out.game.turn == outDeath.game.turn)

  let commands = [Move E, Move E, Move E, PickUp, Wait, Wait, Move E, Wait]
      a = runCommands commands (newGame 42)
      b = runCommands commands (newGame 42)
  check "same seed gives the same initial dungeon"
    (currentLevel (newGame 42) == currentLevel (newGame 42)
     && (newGame 42).items == (newGame 42).items
     && (newGame 42).player.pos == (newGame 42).player.pos)
  check "same seed and commands give the same RNG state"
    (sameRng a.rng b.rng)
  check "same seed and commands give the same player"
    (a.player.pos == b.player.pos && a.player.hp == b.player.hp
     && a.player.exp == b.player.exp)
  check "same seed and commands give the same level"
    (currentLevel a == currentLevel b)
  check "same seed and commands give the same messages"
    (map (.text) a.messages == map (.text) b.messages)

  putStrLn "core tests passed"
