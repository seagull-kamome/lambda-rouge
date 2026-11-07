||| M3 tests: items, identification, equipment, hunger, statuses, the
||| Amulet of Yendor and the ascent/win condition.
|||
||| The numeric rules are provisional M3 rules, so the tests pin down the
||| contract rather than claiming fidelity to Rogue 5.4.4.
module M3Test

import Data.List
import Data.Maybe
import Data.Vect
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Item
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Survival
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

hasWonEvent : Outcome -> Bool
hasWonEvent out = any (\e => case e of
                                PlayerWon => True
                                _ => False)
                      out.events

sameRng : Rng -> Rng -> Bool
sameRng a b = stateHex a == stateHex b

setPlayerStats : (Player -> Player) -> Game -> Game
setPlayerStats f g =
  let p : Player
      p = f g.player
  in { player := p } g

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

addToPack : List Item -> Game -> Game
addToPack items g =
  let p : Player
      p = { inventory := map (.id) items ++ g.player.inventory } g.player
  in { items := g.items ++ items, player := p } g

setItems : List Item -> Game -> Game
setItems items g = { items := items } g

setDepth : Depth -> Game -> Game
setDepth d g = { depth := d } g

withStatus : StatusKind -> Int32 -> Game -> Game
withStatus k turns =
  setPlayerStats (\p => { statuses := MkStatus k turns :: p.statuses } p)

itemAt : Coord -> Game -> Maybe Item
itemAt c g = find (\i => i.location == OnFloor g.depth c) g.items

potion : ItemId -> PotionKind -> Item
potion iid k = MkItem iid (Potion k) InPack 1 0 False 0 False

food : ItemId -> Item
food iid = MkItem iid (Food FoodRation) InPack 1 0 False 0 False

weapon : ItemId -> WeaponKind -> Int32 -> Bool -> Item
weapon iid k ench cursed = MkItem iid (Weapon k) InPack 1 ench cursed 0 False

armor : ItemId -> ArmorKind -> Int32 -> Bool -> Item
armor iid k ench cursed = MkItem iid (Armor k) InPack 1 ench cursed 0 False

base : Game
base = withoutMonsters sampleGame

potionTests : IO ()
potionTests = do
  let start = MkCoord 4 5

  -- Identification and potion effects -------------------------------------
  let heal = potion 100 PotionHealing
      gHeal = setPlayerStats (\p => { hp := 5 } p) (addToPack [heal] base)
      outHeal = step (Quaff 100) gHeal
      healMsg = itemDisplayName outHeal.game.knownKinds heal
  check "quaffing consumes a turn" outHeal.turnConsumed
  check "a healing potion restores HP"
    (outHeal.game.player.hp > gHeal.player.hp
     && outHeal.game.player.hp <= outHeal.game.player.maxHp)
  check "a quaffed potion leaves the pack"
    (null outHeal.game.player.inventory
     && not (any (\i => i.id == 100) outHeal.game.items))
  check "quaffing identifies the potion kind"
    (elem (Potion PotionHealing) outHeal.game.knownKinds)
  check "an unidentified potion shows its appearance"
    (hasMessage ("You quaff the "
                  ++ appearanceOf base (Potion PotionHealing) ++ ".") outHeal)
  check "a known potion shows its real name"
    (healMsg == "potion of healing")

  let heal2 = potion 101 PotionHealing
      gHeal2 = setPlayerStats (\p => { hp := 5 } p)
                 (addToPack [heal2] outHeal.game)
      outHeal2 = step (Quaff 101) gHeal2
  check "the second potion of a known kind is named"
    (hasMessage "You quaff the potion of healing." outHeal2)

  let extra = potion 102 PotionExtraHealing
      gExtra = setPlayerStats (\p => { hp := 1 } p) (addToPack [extra] base)
      outExtra = step (Quaff 102) gExtra
  check "extra healing restores more HP"
    (outExtra.game.player.hp == outExtra.game.player.maxHp)

  let strength = potion 103 PotionStrength
      gStrength = addToPack [strength] base
      outStrength = step (Quaff 103) gStrength
  check "a strength potion raises strength by one"
    (outStrength.game.player.strength == 17
     && outStrength.game.player.maxStrength == 17)

  let restore = potion 104 PotionRestoreStrength
      gRestore = setPlayerStats (\p => { strength := 9, maxStrength := 16 } p)
                   (addToPack [restore] base)
      outRestore = step (Quaff 104) gRestore
  check "a restore-strength potion restores the maximum"
    (outRestore.game.player.strength == 16)

  let poison = potion 105 PotionPoison
      gPoison = addToPack [poison]
                  (setPlayerStats
                    (\p => { statuses := MkStatus Hallucinating 10 :: p.statuses } p)
                    base)
      outPoison = step (Quaff 105) gPoison
  check "a poison potion drains 1d3 strength"
    (outPoison.game.player.strength < gPoison.player.strength
     && outPoison.game.player.strength >= gPoison.player.strength - 3)
  check "a poison potion cures hallucination"
    (not (hasStatus Hallucinating outPoison.game.player))

  let confusion = potion 106 PotionConfusion
      outConfusion = step (Quaff 106) (addToPack [confusion] base)
  check "a confusion potion confuses the player"
    (hasStatus Confused outConfusion.game.player)

  let blindness = potion 107 PotionBlindness
      outBlindness = step (Quaff 107) (addToPack [blindness] base)
  check "a blindness potion blinds the player"
    (hasStatus Blinded outBlindness.game.player)

  let detect = potion 108 PotionDetectMonsters
      outDetect = step (Quaff 108) (addToPack [detect] base)
  check "a detect-monsters potion grants the status"
    (hasStatus DetectMonsters outDetect.game.player)

  let haste = potion 109 PotionHasteSelf
      outHaste = step (Quaff 109) (addToPack [haste] base)
  check "a haste potion grants the hasted status"
    (hasStatus Hasted outHaste.game.player)

  let see = potion 110 PotionSeeInvisible
      outSee = step (Quaff 110) (addToPack [see] base)
  check "a see-invisible potion grants the status"
    (hasStatus SeeInvisible outSee.game.player)

  let raise = potion 111 PotionRaiseLevel
      outRaise = step (Quaff 111) (addToPack [raise] base)
  check "a raise-level potion raises the level"
    (outRaise.game.player.level == 2
     && hasMessage "You feel more experienced." outRaise)

  let levitation = potion 112 PotionLevitation
      outLevitation = step (Quaff 112) (addToPack [levitation] base)
  check "a levitation potion lifts the player"
    (hasStatus Levitated outLevitation.game.player)


foodTests : IO ()
foodTests = do
  -- Food and hunger -------------------------------------------------------
  let ration = food 120
      gFood = setPlayerStats (\p => { hunger := 100 } p) (addToPack [ration] base)
      outFood = step (Eat 120) gFood
  check "eating consumes a turn" outFood.turnConsumed
  check "eating adds a full ration of nutrition"
    (outFood.game.player.hunger == 100 + hungerMax - 1)
  check "eating removes the food from the pack"
    (null outFood.game.player.inventory)

  let rHungry = tickSurvival ({ hunger := hungryAt + 1 } base.player)
  check "crossing the hunger threshold warns"
    (elem "You are hungry." rHungry.messages)
  check "hunger decreases by one per turn"
    (rHungry.player.hunger == hungryAt)

  let rWeak = tickSurvival ({ hunger := weakAt + 1 } base.player)
  check "crossing the weak threshold warns"
    (elem "You are weak." rWeak.messages)
  check "weakness alone does not damage the player"
    (rWeak.player.hp == base.player.hp)

  let rFaint = tickSurvival ({ hunger := starvingAt + 1 } base.player)
  check "starvation starts with a faint warning"
    (elem "You faint from lack of food." rFaint.messages)
  check "starvation damages the player"
    (rFaint.player.hp == base.player.hp - 1)

  let rStarve = tickSurvival ({ hunger := starvingAt, hp := 1 } base.player)
  check "starvation can kill the player" (rStarve.died == Just Starved)
  check "starvation leaves HP at zero" (rStarve.player.hp == 0)

  let poisonedPlayer = { statuses := [MkStatus Poisoned 2], hp := 10 }
                         base.player
      rPoison1 = tickSurvival poisonedPlayer
      rPoison2 = tickSurvival rPoison1.player
  check "poison deals one damage per turn"
    (rPoison1.player.hp == 9 && rPoison2.player.hp == 8)
  check "poison expires after its timer"
    (not (hasStatus Poisoned rPoison2.player)
     && elem "The poison wears off." rPoison2.messages)


equipmentTests : IO ()
equipmentTests = do
  let start = MkCoord 4 5
  -- Equipment -------------------------------------------------------------
  let dagger = weapon 130 Dagger 1 False
      gWield = addToPack [dagger] base
      outWield = step (Wield 130) gWield
  check "wielding consumes a turn" outWield.turnConsumed
  check "wielding equips the weapon"
    (outWield.game.player.wielded == Just 130)
  check "a weapon profile comes from the weapon table"
    (outWield.game.player.weaponDice == 1
     && outWield.game.player.weaponSides == 6
     && outWield.game.player.weaponBonus == 1)
  check "wielding identifies the weapon kind"
    (elem (Weapon Dagger) outWield.game.knownKinds)
  check "wielding reports the enchantment"
    (hasMessage "You wield the dagger +1." outWield)

  let leather = armor 131 LeatherArmor 1 False
      outWear = step (Wear 131) (addToPack [leather] outWield.game)
  check "wearing armor sets its AC minus the enchantment"
    (outWear.game.player.worn == Just 131
     && outWear.game.player.armor == 7)
  check "wearing identifies the armor kind"
    (elem (Armor LeatherArmor) outWear.game.knownKinds)

  let outOff = step (TakeOff 131) outWear.game
  check "taking off armor returns to unarmored AC 10"
    (outOff.game.player.worn == Nothing && outOff.game.player.armor == 10)

  let mace = weapon 132 Mace 0 False
      outSwap = step (Wield 132) (addToPack [mace] outWield.game)
  check "a weapon can be swapped"
    (outSwap.game.player.wielded == Just 132
     && outSwap.game.player.weaponSides == 4)

  let cursedDagger = weapon 133 Dagger 0 True
      gCursed = step (Wield 133) (addToPack [cursedDagger] base)
      outCursedSwap = step (Wield 132) (addToPack [mace] gCursed.game)
  check "a cursed weapon welds itself to the hand"
    (gCursed.game.player.wielded == Just 133
     && hasMessageContaining "weld itself to your hand" gCursed)
  check "a cursed weapon cannot be swapped"
    (outCursedSwap.game.player.wielded == Just 133
     && hasMessage "Your weapon is welded to your hand!" outCursedSwap)
  check "a cursed weapon cannot be dropped"
    (let out = step (Drop 133) gCursed.game
     in out.game.player.wielded == Just 133
        && hasMessage "You cannot let go of the cursed item!" out)

  let cursedArmor = armor 134 ChainMail 0 True
      gCursedArmor = step (Wear 134) (addToPack [cursedArmor] base)
      outCursedOff = step (TakeOff 134) gCursedArmor.game
  check "a cursed armor cannot be removed"
    (outCursedOff.game.player.worn == Just 134
     && hasMessage "You cannot remove the cursed armor!" outCursedOff)

  let outDrop = step (Drop 130) outWield.game
      dropped = find (\i => i.id == 130) outDrop.game.items
  check "dropping an equipped weapon clears the profile"
    (outDrop.game.player.wielded == Nothing
     && outDrop.game.player.weaponDice == 1
     && outDrop.game.player.weaponSides == 4
     && outDrop.game.player.weaponBonus == 0)
  check "a dropped item lands on the player's cell"
    (case dropped of
       Just i => i.location == OnFloor 1 start
                 && not (elem 130 outDrop.game.player.inventory)
       Nothing => False)

  -- Identification of equipment ------------------------------------------
  let hidden = weapon 140 LongSword 2 True
  check "an unidentified weapon hides enchantment and curse"
    (itemDisplayName [] hidden == "long sword")
  check "a known weapon shows enchantment and curse"
    (itemDisplayName [Weapon LongSword] hidden == "long sword +2 (cursed)")
  check "gold and the amulet are always known"
    (itemKnown [] (MkItem 141 Gold InPack 1 0 False 0 False)
     && itemKnown [] (MkItem 142 Amulet InPack 1 0 False 0 False))


amuletTests : IO ()
amuletTests = do
  let start = MkCoord 4 5
  -- Amulet generation and pickup -----------------------------------------
  let deep = generateLevel 26 1 1 (fromSeed 2600)
      amulets = filter (\i => i.kind == Amulet) deep.items
  check "depth 26 generates exactly one amulet"
    (length amulets == 1)
  check "the amulet lies on the floor of depth 26"
    (case amulets of
       [a] => a.count == 1 && a.enchant == 0 && not a.cursed
              && (case a.location of
                    OnFloor 26 _ => True
                    _ => False)
       _ => False)

  let amulet = MkItem 150 Amulet (OnFloor 1 start) 1 0 False 0 False
      gAmulet = setItems [amulet] base
      outAmulet = step PickUp gAmulet
  check "picking up the amulet consumes a turn" outAmulet.turnConsumed
  check "the amulet enters the pack"
    (outAmulet.game.player.inventory == [150]
     && case find (\i => i.id == 150) outAmulet.game.items of
          Just i => i.location == InPack
          Nothing => False)
  check "the amulet pickup is announced"
    (hasMessage "You pick up the Amulet of Yendor!" outAmulet)

  -- Win condition ---------------------------------------------------------
  let gWin = setPlayerStats (\p => { inventory := [150] } p)
               (setDepth 1 (setItems [MkItem 150 Amulet InPack 1 0 False 0 False]
                 (withoutMonsters (setPlayerStats (\p => { pos := MkCoord 3 8 } p)
                    base))))
      outWin = step Ascend gWin
  check "ascending on depth 1 with the amulet wins"
    (outWin.game.over == Just Won)
  check "winning is an event"
    (hasWonEvent outWin)
  check "winning is announced"
    (hasMessageContaining "You win" outWin)


ascentTests : IO ()
ascentTests = do
  -- Ascent, descent and level persistence --------------------------------
  let gDescent0 = withoutMonsters (newGame 42)
      down1 = fromMaybe (MkCoord 1 1) (currentLevel gDescent0).downStairs
      gAtDown = setPlayerStats (\p => { pos := down1 } p) gDescent0
      outDown1 = step Descend gAtDown
      level2 = currentLevel outDown1.game
      up2 = fromMaybe (MkCoord 1 1) level2.upStairs
      gAmulet2 = addToPack [MkItem 151 Amulet InPack 1 0 False 0 False]
                   outDown1.game
      gAtUp2 = setPlayerStats (\p => { pos := up2 } p) gAmulet2
      outUp1 = step Ascend gAtUp2
  check "ascending returns to depth 1"
    (outUp1.game.depth == 1 && (currentLevel outUp1.game).depth == 1)
  check "ascending reorders the visited levels"
    (map (.depth) outUp1.game.levels == [1, 2])
  check "the ascended-from level is preserved"
    (case last' outUp1.game.levels of
       Just lvl => lvl == level2
       Nothing => False)
  check "the player arrives on the down stairs of depth 1"
    (Just outUp1.game.player.pos == (currentLevel outUp1.game).downStairs)
  check "the amulet stays in the pack during the ascent"
    (elem 151 outUp1.game.player.inventory)

  let down1' = fromMaybe (MkCoord 1 1) (currentLevel outUp1.game).downStairs
      outDownAgain = step Descend
                       (setPlayerStats (\p => { pos := down1' } p) outUp1.game)
  check "descending again reuses the visited level"
    (currentLevel outDownAgain.game == level2)
  check "the reused level still has the same depth"
    (outDownAgain.game.depth == 2
     && map (.depth) outDownAgain.game.levels == [2, 1])


statusTests : IO ()
statusTests = do
  -- Statuses and FOV ------------------------------------------------------
  let gBlind = withStatus Blinded 5 base
      outBlind = step Wait gBlind
  check "blindness limits the visible area"
    (count outBlind.game.visible < count base.visible)
  check "blindness hides the far side of a lit room"
    (not (getBit 20 8 outBlind.game.visible))
  check "a blinded player still sees adjacent cells"
    (getBit 5 5 outBlind.game.visible)
  check "the blindness timer counts down"
    (statusTurns Blinded outBlind.game.player == 4)

  let gConfused = withStatus Confused 5 base
      outConfused = step (Move E) gConfused
  check "confusion randomises movement"
    (not (sameRng outConfused.game.rng gConfused.rng))
  check "the confusion timer counts down"
    (statusTurns Confused outConfused.game.player == 4)

  let hastedPlayer = withStatus Hasted 5
                       (setPlayerStats (\p => { hp := 100, maxHp := 100,
                                                armor := 100 } p)
                         (setMonster (MkMonster 1 Kestrel (MkCoord 5 5)
                                          4 4 Chasing [])
                           (withoutMonsters base)))
      outHaste1 = step Wait hastedPlayer
      outHaste2 = step Wait outHaste1.game
  check "a hasted player still lets monsters act on odd turns"
    (outHaste1.game.player.hp < hastedPlayer.player.hp)
  check "haste skips the monster turn on even turns"
    (outHaste2.game.player.hp == outHaste1.game.player.hp)
  check "the haste timer counts down"
    (statusTurns Hasted outHaste2.game.player == 3)

public export
run : IO ()
run = do
  potionTests
  foodTests
  equipmentTests
  amuletTests
  ascentTests
  statusTests
  putStrLn "M3 tests passed"
