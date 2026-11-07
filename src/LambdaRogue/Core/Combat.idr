||| Combat resolution and experience.
|||
||| The formulas are the Rogue 5.4.4 rules described in the public guide:
||| the player hits with `5 + 5*level + 5*monsterAC` percent, a monster
||| hits with `20 + 5*level + 5*playerAC` percent, and strength modifies
||| both hit chance and damage.  Armor class counts down from 10, so lower
||| is better.  Multi-attack monsters roll each attack separately.
module LambdaRogue.Core.Combat

import LambdaRogue.Core.Monster
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types

%default covering

public export
data AttackResult
  = Miss
  | Hit Int32
  | Killed Int32

public export
Eq AttackResult where
  Miss == Miss = True
  Hit a == Hit b = a == b
  Killed a == Killed b = a == b
  _ == _ = False

public export
Show AttackResult where
  show Miss = "Miss"
  show (Hit d) = "Hit " ++ show d
  show (Killed d) = "Killed " ++ show d

||| Strength damage adjustment from the 5.4.4 strength table.
public export
strengthDamageBonus : Int32 -> Int32
strengthDamageBonus s =
  if s <= 6 then s - 7
  else if s <= 15 then 0
  else if s <= 17 then 1
  else if s <= 18 then 2
  else if s <= 20 then 3
  else if s <= 21 then 4
  else if s <= 30 then 5
  else 6

||| The player's effective armor class: base armor class minus protective
||| rings and dexterity.  Lower is better; unarmored is 10.
public export
playerArmorClass : Player -> Int32
playerArmorClass p = p.armor - p.ringArmor

clampPercent : Int32 -> Int32
clampPercent n = max 0 (min 100 n)

||| Player attack: `5 + 5*level + 5*monsterAC` percent, adjusted by the
||| dexterity ring bonus.  Damage is the equipped weapon's dice plus
||| strength, enchantment and ring damage.  Strength affects damage only;
||| the Rogue Vade-Mecum to-hit formula does not mention strength.
public export
playerAttack : Player -> Monster -> Rng -> (AttackResult, Rng)
playerAttack p m g =
  let spec = monsterSpec m.kind
      chance = clampPercent
                 (5 + 5 * p.level + 5 * spec.ac + p.ringAccuracy)
      (hitRoll, g1) = roll 1 100 g
  in if hitRoll > chance
       then (Miss, g1)
       else let (dmg0, g2) = roll p.weaponDice p.weaponSides g1
                dmg = max 1 (dmg0 + strengthDamageBonus (effectiveStrength p)
                             + p.weaponBonus + p.ringDamage)
            in if m.hp - dmg <= 0
                  then (Killed dmg, g2)
                  else (Hit dmg, g2)

monsterChance : Player -> Monster -> Int32
monsterChance p m =
  clampPercent (20 + 5 * (monsterSpec m.kind).level + 5 * playerArmorClass p)

||| One monster attack roll.  Zero-damage attacks still count as hits so
||| their special ability (rust, steal, freeze) can trigger.
attackRoll : Player -> Monster -> (Int32, Int32) -> Rng
           -> (Bool, Int32, Rng)
attackRoll p m (dice, sides) g =
  let chance = monsterChance p m
      (hitRoll, g1) = roll 1 100 g
  in if hitRoll > chance
       then (False, 0, g1)
       else let (dmg, g2) = roll dice sides g1
            in (True, dmg, g2)

||| A monster may have several attacks; each is rolled separately.  The
||| total damage is returned with a single `Hit`/`Killed` result.
monsterAttackRolls : Player -> Monster -> List (Int32, Int32) -> Bool -> Int32 -> Rng -> (Bool, Int32, Rng)
monsterAttackRolls p m [] hit acc g = (hit, acc, g)
monsterAttackRolls p m (a :: as) hit acc g =
  let (h, d, g') = attackRoll p m a g
  in monsterAttackRolls p m as (hit || h) (acc + d) g'

public export
monsterAttack : Player -> Monster -> Rng -> (AttackResult, Rng)
monsterAttack p m g0 =
  let (hit, dmg, g1) =
        monsterAttackRolls p m (monsterSpec m.kind).attacks False 0 g0
  in if not hit
       then (Miss, g1)
       else if p.hp - dmg <= 0
               then (Killed dmg, g1)
               else (Hit dmg, g1)

||| Experience needed to reach the next level, as a cumulative total.
||| Rogue 5.4.4 uses the 10, 20, 40, ... 8,000,000 table; experience is not
||| subtracted when a level is gained.
public export
expForNext : Int32 -> Int32
expForNext level =
  case level of
    1 => 10
    2 => 20
    3 => 40
    4 => 80
    5 => 160
    6 => 320
    7 => 640
    8 => 1300
    9 => 2600
    10 => 5200
    11 => 13000
    12 => 26000
    13 => 50000
    14 => 100000
    15 => 200000
    16 => 400000
    17 => 800000
    18 => 2000000
    19 => 4000000
    20 => 8000000
    _ => 2147483647

||| Cumulative experience required to be at `level`.
public export
expForLevel : Int32 -> Int32
expForLevel level = if level <= 1 then 0 else expForNext (level - 1)

public export
record ExpResult where
  constructor MkExpResult
  player : Player
  levelsGained : Nat
  hpGain : Int32
  rng : Rng

||| Add experience and apply every level-up it triggers.  Each level grants
||| 1d10 maximum HP (and the same amount of current HP); Rogue 5.4.4 does
||| not grant strength on level-up.
public export
gainExperience : Player -> Int32 -> Rng -> ExpResult
gainExperience p amount g =
  let p' = { exp := p.exp + max 0 amount } p
  in go p' 0 0 g
  where
    go : Player -> Nat -> Int32 -> Rng -> ExpResult
    go p n hpGain g =
      if p.level < 21 && p.exp >= expForNext p.level
         then let (gain, g') = roll 1 10 g
                  p' = { level := p.level + 1
                       , maxHp := p.maxHp + gain
                       , hp := p.hp + gain
                       } p
              in go p' (S n) (hpGain + gain) g'
         else MkExpResult p n hpGain g
