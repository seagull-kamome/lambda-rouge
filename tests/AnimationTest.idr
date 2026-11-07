||| Animation-policy tests: event-derived effects, tick ageing and the
||| guarantee that presentation never changes the game or the replay.
module AnimationTest

import Data.List
import LambdaRogue.App.Model
import LambdaRogue.App.Update
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Types
import LambdaRogue.UI.Animation
import LambdaRogue.UI.Theme
import System
import TermUI.Canvas
import TermUI.Len
import TermUI.Program

check : String -> Bool -> IO ()
check name ok =
  if ok
     then putStrLn ("ok   " ++ name)
     else do
       putStrLn ("FAIL " ++ name)
       exitFailure

monsterPos : Coord
monsterPos = MkCoord 5 5

withMonster : Game
withMonster =
  let m : Monster
      m = MkMonster 99 Rattlesnake monsterPos 3 3 Chasing []
      lvl : Level
      lvl = { monsters := [m] } (currentLevel sampleGame)
  in updateCurrentLevel (const lvl) sampleGame

public export
run : IO ()
run = do
  c <- newCanvas (the Len 80) (the Len 22)
  let g0 = sampleGame
      movedPlayer : Player
      movedPlayer = { pos := MkCoord 5 5 } g0.player
      afterMove : Game
      afterMove = { player := movedPlayer } g0
      moveEffects = effectsFor g0 afterMove
                      [PlayerMoved (MkCoord 5 5)]
      hitEffects = effectsFor withMonster withMonster
                     [PlayerAttacked 99 7]
      missEffects = effectsFor withMonster withMonster
                      [PlayerAttacked 99 0]
      deathEffects = effectsFor withMonster withMonster [MonsterDied 99]
      trapEffects = effectsFor g0 g0
                      [TrapTriggered Sleep (MkCoord 6 5)]

  check "a player step leaves a trail at the old cell"
    (case moveEffects of
       [e] => e.kind == Trail && e.pos == MkCoord 4 5
       _ => False)
  check "a hit paints the damage on the monster's cell"
    (case hitEffects of
       [e] => e.kind == Damage 7 && e.pos == monsterPos
       _ => False)
  check "a miss paints an impact without a number"
    (case missEffects of
       [e] => e.kind == Impact && e.pos == monsterPos
       _ => False)
  check "a death leaves a mark where the monster stood"
    (case deathEffects of
       [e] => e.kind == Death && e.pos == monsterPos
       _ => False)
  check "a trap marks its cell"
    (case trapEffects of
       [e] => e.kind == TrapMark && e.pos == MkCoord 6 5
       _ => False)

  let numberCells = effectCells
        [MkEffect (Damage 12) (MkCoord 70 3) 0 12]
  check "a two-digit damage number spans two cells"
    (map (\(x, _, ch, _) => (x, ch)) numberCells
       == [(70, '1'), (71, '2')])
  check "a damage number is clipped at the right edge"
    (map (\(x, _, ch, _) => (x, ch))
       (effectCells [MkEffect (Damage 12) (MkCoord 79 3) 0 12])
       == [(79, '1')])

  let fresh = mkEffect Trail (MkCoord 1 1)
      aged = advanceAnimations [fresh]
      old = { age := minus fresh.life 1 } fresh
  check "an effect ages by one tick"
    (case aged of
       [e] => e.age == 1 && e.life == 4
       _ => False)
  check "an effect expires after its life"
    (null (advanceAnimations [old]))
  check "the overlay keeps at most 24 effects"
    (length (mergeAnimations (replicate 30 fresh) []) == 24)
  check "the newest effect is first in the overlay"
    (case mergeAnimations [fresh] [old] of
       (e :: _) => e == fresh
       [] => False)

  let m0 = initModel c g0
      m1 : Model
      m1 = { animations := [mkEffect (Damage 3) monsterPos] } m0
      m2 = fst (update AnimationTick m1)
  check "a tick advances animation only"
    (case m2.animations of
       [e] => e.age == 1
              && m2.game.turn == m1.game.turn
              && m2.replay.commands == m1.replay.commands
       _ => False)

  let hit = step (Move E) g0
  check "the movement fixture emits an event"
    (not (null hit.events))
  let mOff : Model
      mOff = { animationsEnabled := False } m0
      mStepOff = fst (update (Do (Move E)) mOff)
      mStepOn = fst (update (Do (Move E)) m0)
  check "a step with animation off records no effects"
    (null mStepOff.animations)
  check "a step with animation on records the event effects"
    (not (null mStepOn.animations))
  check "animation does not change the game or the replay"
    (mStepOn.game.turn == mStepOff.game.turn
     && mStepOn.replay.commands == mStepOff.replay.commands)

  let mToggled = fst (update ToggleAnimations m1)
  check "turning animation off clears the overlay"
    (not mToggled.animationsEnabled && null mToggled.animations)
  check "turning animation off keeps the game state"
    (mToggled.game.turn == m1.game.turn)

  putStrLn "animation tests passed"
