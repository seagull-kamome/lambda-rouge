||| Combat-formula and experience tests.
|||
||| The formulas are the public Rogue 5.4.4 rules: player to-hit is
||| 5 + 5*level + 5*monsterAC, monster to-hit is 20 + 5*level +
||| 5*playerAC, and experience thresholds are cumulative.
module CombatTest

import LambdaRogue.Core.Combat
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

sameRng : Rng -> Rng -> Bool
sameRng a b = stateHex a == stateHex b

basePlayer : Player
basePlayer = initialPlayer (MkCoord 0 0)

||| A one-hit-die monster with AC 7 and 1d4 damage: the kestrel.
rat : Int32 -> Monster
rat hp = MkMonster 1 Kestrel (MkCoord 1 0) hp hp Awake []

public export
run : IO ()
run = do
  let g0 = fromSeed 0

  check "strength 3 gives -4 damage" (strengthDamageBonus 3 == -4)
  check "strength 6 gives -1 damage" (strengthDamageBonus 6 == -1)
  check "strength 10 gives no damage bonus" (strengthDamageBonus 10 == 0)
  check "strength 16 gives +1 damage" (strengthDamageBonus 16 == 1)
  check "strength 18 gives +2 damage" (strengthDamageBonus 18 == 2)
  check "strength 20 gives +3 damage" (strengthDamageBonus 20 == 3)
  check "strength 21 gives +4 damage" (strengthDamageBonus 21 == 4)
  check "strength 30 gives +5 damage" (strengthDamageBonus 30 == 5)
  check "strength 31 gives +6 damage" (strengthDamageBonus 31 == 6)
  check "player armor class is the armor value"
    (playerArmorClass ({ armor := 2 } basePlayer) == 2)
  check "rings of protection improve armor class"
    (playerArmorClass ({ armor := 10, ringArmor := 3 } basePlayer) == 7)
  check "experience threshold starts at 10" (expForNext 1 == 10)
  check "experience threshold is cumulative" (expForNext 5 == 160)
  check "experience threshold at level 21" (expForNext 20 == 8000000)
  check "cumulative experience for level 8" (expForLevel 8 == 640)

  let strong = { level := 100, strength := 100 } basePlayer
      (strongHit, strongRng) = playerAttack strong (rat 100) g0
  check "a strong player hits a low-AC monster"
    (case strongHit of
       Hit d => d >= 7 && d <= 10
       _ => False)
  check "a hit consumes the RNG" (not (sameRng strongRng g0))
  check "a strong hit can kill"
    (case fst (playerAttack strong (rat 1) g0) of
       Killed d => d >= 7
       _ => False)

  let weak = { level := -100, strength := 0 } basePlayer
      (weakResult, weakRng) = playerAttack weak (rat 4) g0
  check "a very weak player misses" (weakResult == Miss)
  check "a miss still consumes the hit roll" (not (sameRng weakRng g0))

  let minimum = { level := 100, strength := 10 } basePlayer
      (minimumResult, _) = playerAttack minimum (rat 100) g0
  check "damage is never below one"
    (case minimumResult of
       Hit d => d >= 1 && d <= 4
       _ => False)

  let armoured = { armor := -1000 } basePlayer
      (armouredResult, _) = monsterAttack armoured (rat 4) g0
  check "a low armor class avoids a monster hit" (armouredResult == Miss)

  let exposed = { armor := 100 } basePlayer
      (exposedResult, exposedRng) = monsterAttack exposed (rat 4) g0
  check "an exposed player is hit"
    (case exposedResult of
       Hit d => d >= 1 && d <= 4
       _ => False)
  check "a monster hit consumes the RNG" (not (sameRng exposedRng g0))

  let fragile = { armor := 100, hp := 1 } basePlayer
  check "a monster hit can kill the player"
    (case fst (monsterAttack fragile (rat 4) g0) of
       Killed _ => True
       _ => False)

  let (sameA, sameRngA) = playerAttack strong (rat 100) (fromSeed 42)
      (sameB, sameRngB) = playerAttack strong (rat 100) (fromSeed 42)
  check "attacks are deterministic"
    (sameA == sameB && sameRng sameRngA sameRngB)

  let noGain = gainExperience basePlayer 0 g0
  check "zero experience does not level up"
    (noGain.levelsGained == 0 && noGain.player.exp == 0
     && noGain.hpGain == 0 && sameRng noGain.rng g0)
  check "negative experience is ignored"
    ((gainExperience basePlayer (-5) g0).player.exp == 0)

  let near = { exp := 9 } basePlayer
      levelUp = gainExperience near 1 g0
  check "crossing the threshold raises the level"
    (levelUp.player.level == 2 && levelUp.player.exp == 10
     && levelUp.levelsGained == 1)
  check "a level-up does not grant strength"
    (levelUp.player.strength == 16)
  check "a level-up grants 1d10 HP"
    (levelUp.hpGain >= 1 && levelUp.hpGain <= 10
     && levelUp.player.maxHp == 12 + levelUp.hpGain
     && levelUp.player.hp == 12 + levelUp.hpGain)

  let double = gainExperience basePlayer 30 g0
  check "large experience can grant several levels"
    (double.levelsGained == 2 && double.player.level == 3
     && double.player.exp == 30)
  check "several level-ups keep strength unchanged"
    (double.player.strength == 16)
  check "several level-ups accumulate HP"
    (double.hpGain >= 2 && double.hpGain <= 20
     && double.player.maxHp == 12 + double.hpGain)

  let huge = gainExperience basePlayer 1000 g0
  check "a huge award terminates and raises many levels"
    (huge.player.level == 8 && huge.levelsGained == 7)

  putStrLn "combat tests passed"
