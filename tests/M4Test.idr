||| M4 tests: scrolls, wands, rings, throwing, monster statuses and
||| per-run item appearances.
|||
||| The item tables are still provisional, so these tests pin down the
||| contract and the deterministic RNG plumbing rather than claiming
||| fidelity to Rogue 5.4.4.
module M4Test

import Data.List
import Data.Maybe
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Combat
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
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

contains : String -> String -> Bool
contains needle hay = isInfixOf (unpack needle) (unpack hay)

hasMessage : String -> Outcome -> Bool
hasMessage text out = any (\m => m.text == text) out.messages

hasMessageContaining : String -> Outcome -> Bool
hasMessageContaining text out = any (\m => contains text m.text) out.messages

hasEvent : (Event -> Bool) -> Outcome -> Bool
hasEvent p out = any p out.events

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

setTraps : List Trap -> Game -> Game
setTraps ts g =
  updateCurrentLevel (\l => { traps := ts } l) g

addToPack : List Item -> Game -> Game
addToPack items g =
  let p : Player
      p = { inventory := map (.id) items ++ g.player.inventory } g.player
  in { items := g.items ++ items, player := p } g

withStatus : StatusKind -> Int32 -> Game -> Game
withStatus k turns =
  setPlayerStats (\p => { statuses := MkStatus k turns :: p.statuses } p)

monsterAtCoord : Coord -> Game -> Maybe Monster
monsterAtCoord c g = find (\m => m.pos == c) (currentLevel g).monsters

monsterHas : StatusKind -> Monster -> Bool
monsterHas k m = any (\s => s.statusKind == k) m.statuses

monsterById : MonsterId -> Game -> Maybe Monster
monsterById i g = find (\m => m.id == i) (currentLevel g).monsters

scroll : ItemId -> ScrollKind -> Item
scroll iid k = MkItem iid (Scroll k) InPack 1 0 False 0 False

wand : ItemId -> WandKind -> Int32 -> Item
wand iid k charges = MkItem iid (Wand k) InPack 1 0 False charges False

ring : ItemId -> RingKind -> Int32 -> Bool -> Item
ring iid k ench cursed = MkItem iid (Ring k) InPack 1 ench cursed 0 False

weapon : ItemId -> WeaponKind -> Int32 -> Bool -> Item
weapon iid k ench cursed = MkItem iid (Weapon k) InPack 1 ench cursed 0 False

armor : ItemId -> ArmorKind -> Int32 -> Bool -> Item
armor iid k ench cursed = MkItem iid (Armor k) InPack 1 ench cursed 0 False

potion : ItemId -> PotionKind -> Item
potion iid k = MkItem iid (Potion k) InPack 1 0 False 0 False

base : Game
base = withoutMonsters sampleGame

sameState : Rng -> Rng -> Bool
sameState a b = stateHex a == stateHex b

appearanceTests : IO ()
appearanceTests = do
  let (a1, r1) = rollAppearances (fromSeed 12345)
      (a2, r2) = rollAppearances (fromSeed 12345)
      (a3, r3) = rollAppearances (fromSeed 54321)
      g1 = newGame 12345
      g2 = newGame 12345
  check "appearance shuffling is deterministic"
    (a1 == a2 && sameState r1 r2)
  check "different seeds give different appearance mappings"
    (a1 /= a3)
  check "a run stores one appearance per item kind"
    (length g1.appearances == 60)
  check "newGame is deterministic"
    (g1.appearances == g2.appearances && sameState g1.rng g2.rng)
  check "appearanceOf uses the run mapping"
    (appearanceOf g1 (Potion PotionHealing)
     == fromMaybe "" (lookup (Potion PotionHealing) g1.appearances))

  let sc = scroll 200 ScrollMagicMapping
      gSc = addToPack [sc] g1
  check "an unidentified scroll shows a run-specific label"
    (contains "scroll labeled" (itemDisplayNameIn gSc sc))
  let gKnown : Game
      gKnown = { knownKinds := Scroll ScrollMagicMapping :: gSc.knownKinds } gSc
  check "a known scroll shows its real name"
    (itemDisplayNameIn gKnown sc == "scroll of magic mapping")

  let wandItem = fst (makeItem 10 201 (Wand WandLightning) (MkCoord 1 1)
                        (fromSeed 77))
  check "ordinary wands start with 3..7 charges"
    (wandItem.charges >= 3 && wandItem.charges <= 7)
  let lightWand = fst (makeItem 10 202 (Wand WandLight) (MkCoord 1 1)
                        (fromSeed 77))
  check "a wand of light starts with 10..19 charges"
    (lightWand.charges >= 10 && lightWand.charges <= 19)
  check "an unidentified wand hides its charges"
    (not (contains "charges" (itemDisplayNameIn base wandItem)))
  let gWandKnown : Game
      gWandKnown = { knownKinds := Wand WandLightning :: base.knownKinds } base
  check "a known wand shows its remaining charges"
    (contains "charges" (itemDisplayNameIn gWandKnown wandItem))

  check "the depth-1 pool contains scrolls, wands and rings"
    (elem (Scroll ScrollConfuseMonster) (itemPool 1)
     && elem (Wand WandLight) (itemPool 1)
     && elem (Ring RingProtection) (itemPool 1))
  check "deep pools contain the deeper item kinds"
    (elem (Scroll ScrollProtectArmor) (itemPool 26)
     && elem (Wand WandCancellation) (itemPool 26)
     && elem (Ring RingMaintainArmor) (itemPool 26))

scrollTests : IO ()
scrollTests = do
  -- Magic mapping reveals the whole level.
  let gMap = addToPack [scroll 300 ScrollMagicMapping] base
      outMap = step (Read 300) gMap
  check "reading a scroll consumes a turn" outMap.turnConsumed
  check "a read scroll leaves the pack"
    (not (any (\i => i.id == 300) outMap.game.items))
  check "reading identifies the scroll kind"
    (elem (Scroll ScrollMagicMapping) outMap.game.knownKinds)
  check "magic mapping reveals the whole level"
    (count (currentLevel outMap.game).explored == 1760)

  -- Identification scrolls identify the first matching carried item.
  let sword = weapon 301 LongSword 2 False
      gId = addToPack [sword, scroll 302 ScrollIdentifyWeapon] base
      outId = step (Read 302) gId
  check "identify weapon learns the first weapon kind"
    (elem (Weapon LongSword) outId.game.knownKinds)
  check "identify weapon announces the item"
    (hasMessageContaining "You identify the long sword" outId)

  let ringItem = ring 303 RingProtection 1 False
      wandItem = wand 304 WandLightning 4
      gIdRW = addToPack [ringItem, wandItem, scroll 305 ScrollIdentifyRingOrWand] base
      outIdRW = step (Read 305) gIdRW
  check "identify ring or wand learns the first matching kind"
    (elem (Ring RingProtection) outIdRW.game.knownKinds)

  -- Enchant weapon improves the equipped weapon.
  let sword2 = weapon 306 LongSword 0 False
      gEnch = addToPack [sword2, scroll 307 ScrollEnchantWeapon] base
      outWield = step (Wield 306) gEnch
      outEnch = step (Read 307) outWield.game
      enchItem = findPackItem outEnch.game 306
  check "enchant weapon raises the weapon enchantment"
    (maybe False (\i => i.enchant == 1) enchItem)
  check "enchant weapon updates the combat profile"
    (outEnch.game.player.weaponBonus == 1)

  -- Enchant armor improves the worn armor.
  let leather = armor 308 LeatherArmor 0 False
      gArm = addToPack [leather, scroll 309 ScrollEnchantArmor] base
      outWear = step (Wear 308) gArm
      outArm = step (Read 309) outWear.game
      armItem = findPackItem outArm.game 308
  check "enchant armor raises the armor enchantment"
    (maybe False (\i => i.enchant == 1) armItem)
  check "enchant armor improves AC by one"
    (outArm.game.player.armor == 7)

  -- Teleportation moves the player somewhere else.
  let outTel = step (Read 310) (addToPack [scroll 310 ScrollTeleportation] base)
  check "teleportation moves the player"
    (outTel.game.player.pos /= base.player.pos)
  check "teleportation lands on a walkable cell"
    (maybe False walkable (tileAt (currentLevel outTel.game).tiles
                              outTel.game.player.pos))

  -- Food detection grants the status.
  let outFood = step (Read 311)
                 (addToPack [scroll 311 ScrollFoodDetection] base)
  check "food detection grants the status"
    (hasStatus DetectFood outFood.game.player
     && statusTurns DetectFood outFood.game.player > 0)

  -- Remove curse clears cursed pack items.
  let cursedSword = weapon 312 LongSword 0 True
      gCurse = addToPack [cursedSword, scroll 313 ScrollRemoveCurse] base
      outCurse = step (Read 313) gCurse
  check "remove curse clears the curse"
    (maybe False (\i => not i.cursed) (findPackItem outCurse.game 312))

  -- Protect armor prevents rust damage.
  let protectedArmor = armor 314 LeatherArmor 0 False
      gProt = addToPack [protectedArmor, scroll 315 ScrollProtectArmor] base
      outWear2 = step (Wear 314) gProt
      outProt = step (Read 315) outWear2.game
      gTrap = setTraps [MkTrap (MkCoord 5 5) Rust False] outProt.game
      outRust = step (Move E) gTrap
      protItem = findPackItem outRust.game 314
  check "protect armor marks the armor"
    (maybe False (\i => i.protected) (findPackItem outProt.game 314))
  check "protected armor resists rust"
    (maybe False (\i => i.enchant == 0) protItem)
  check "protected armor announces the resistance"
    (hasMessageContaining "protected from the rust" outRust)

  let plainArmor = armor 316 LeatherArmor 0 False
      gPlain = addToPack [plainArmor] base
      outWear3 = step (Wear 316) gPlain
      gRust = setTraps [MkTrap (MkCoord 5 5) Rust False] outWear3.game
      outPlain = step (Move E) gRust
      plainItem = findPackItem outPlain.game 316
  check "unprotected armor rusts"
    (maybe False (\i => i.enchant == -1) plainItem)

  -- Create monster adds a monster.
  let outCreate = step (Read 317)
                    (addToPack [scroll 317 ScrollCreateMonster] base)
  check "create monster adds a monster"
    (length (currentLevel outCreate.game).monsters == 1)

  -- Monster-affecting scrolls.
  let rat = MkMonster 1 Emu (MkCoord 6 5) 4 4 Chasing []
      gScare = setMonster rat (addToPack [scroll 318 ScrollScareMonster] base)
      outScare = step (Read 318) gScare
      scareM = monsterById 1 outScare.game
  check "scare monster makes monsters flee"
    (maybe False (\m => m.state == Fleeing && monsterHas Scared m) scareM)

  let gHold = setMonster rat (addToPack [scroll 319 ScrollHoldMonster] base)
      outHold = step (Read 319) gHold
      holdM = monsterById 1 outHold.game
  check "hold monster stops monsters"
    (maybe False (\m => monsterHas Held m) holdM)
  check "a held monster does not move"
    (maybe False (\m => m.pos == MkCoord 6 5) holdM)

  let gSleep = setMonster rat (addToPack [scroll 320 ScrollSleep] base)
      outSleep = step (Read 320) gSleep
  check "sleep puts monsters to sleep"
    (maybe False (\m => m.state == Asleep) (monsterById 1 outSleep.game))

  let gAgg = setMonster ({ state := Asleep } rat)
               (addToPack [scroll 321 ScrollAggravateMonsters] base)
      outAgg = step (Read 321) gAgg
  check "aggravate monsters wakes and chases"
    (maybe False (\m => m.state == Chasing) (monsterById 1 outAgg.game))

  let gConf = setMonster rat (addToPack [scroll 322 ScrollConfuseMonster] base)
      outConf = step (Read 322) gConf
  check "confuse monster arms the next hit"
    (hasStatus ConfuseNext outConf.game.player)
  let adjacentRat = MkMonster 1 Emu (MkCoord 5 5) 4 4 Chasing []
      sureHit = setPlayerStats (\p => { level := 100 } p) outConf.game
      outConfHit = step (Move E) (setMonster adjacentRat sureHit)
  check "the next hit confuses the monster"
    (maybe False (monsterHas Confused) (monsterById 1 outConfHit.game))
  check "the confuse-next status is consumed"
    (not (hasStatus ConfuseNext outConfHit.game.player))

wandTests : IO ()
wandTests = do
  let bigRat = MkMonster 1 Emu (MkCoord 6 5) 100 100 Awake []

  let gLight = addToPack [wand 400 WandLight 5] base
      outLight = step (Zap 400 E) gLight
  check "zapping consumes a turn" outLight.turnConsumed
  check "zapping consumes one charge"
    (maybe False (\i => i.charges == 4) (findPackItem outLight.game 400))
  check "zapping identifies the wand kind"
    (elem (Wand WandLight) outLight.game.knownKinds)
  check "the light wand reveals only the current room"
    (count (currentLevel outLight.game).explored == 220
     && not (getBit 35 5 (currentLevel outLight.game).explored))

  let damageWand : WandKind -> ItemId -> String -> IO ()
      damageWand k iid label = do
        let g = setMonster bigRat (addToPack [wand iid k 5] base)
            out = step (Zap iid E) g
        check label
          (case monsterById 1 out.game of
             Just m => m.hp < 100
             Nothing => True)

  damageWand WandLightning 401 "lightning damages a monster"
  damageWand WandFire 402 "fire damages a monster"
  damageWand WandCold 403 "cold damages a monster"
  damageWand WandMagicMissile 404 "magic missile damages a monster"

  let outInvis = step (Zap 405 E)
                   (addToPack [wand 405 WandInvisibility 5] base)
  check "invisibility grants the status"
    (hasStatus Invisible outInvis.game.player)

  let outHaste = step (Zap 406 E)
                   (setMonster bigRat
                     (addToPack [wand 406 WandHasteMonster 5] base))
  check "haste monster applies hasted"
    (maybe False (monsterHas Hasted) (monsterById 1 outHaste.game))

  let outSlow = step (Zap 407 E)
                  (setMonster bigRat
                    (addToPack [wand 407 WandSlowMonster 5] base))
  check "slow monster applies slowed"
    (maybe False (monsterHas Slowed) (monsterById 1 outSlow.game))

  let gDrain = setPlayerStats (\p => { hp := 5 } p)
                 (setMonster bigRat (addToPack [wand 408 WandDrainLife 5] base))
      outDrain = step (Zap 408 E) gDrain
  check "drain life heals the player"
    (outDrain.game.player.hp > 5)
  check "drain life damages the monster"
    (case monsterById 1 outDrain.game of
       Just m => m.hp < 100
       Nothing => True)

  let outNothing = step (Zap 409 E)
                     (addToPack [wand 409 WandNothing 5] base)
  check "wand of nothing does nothing"
    (hasMessage "Nothing happens." outNothing)

  let outEmpty = step (Zap 410 E)
                   (addToPack [wand 410 WandNothing 0] base)
  check "an empty wand sputters"
    (hasMessage "The wand sputters." outEmpty)
  check "an empty wand is not consumed or identified"
    (not outEmpty.turnConsumed
     && not (elem (Wand WandNothing) outEmpty.game.knownKinds))

  let outAway = step (Zap 411 E)
                  (setMonster bigRat
                    (addToPack [wand 411 WandTeleportAway 5] base))
  check "teleport away moves the monster"
    (maybe True (\m => m.pos /= MkCoord 6 5) (monsterById 1 outAway.game))

  let outTo = step (Zap 412 E)
                (addToPack [wand 412 WandTeleportTo 5] base)
  check "teleport to moves the player"
    (outTo.game.player.pos /= base.player.pos)

  let cancelled = { statuses := [MkStatus Held 5], state := Fleeing } bigRat
      outCancel = step (Zap 413 E)
                    (setMonster cancelled
                      (addToPack [wand 413 WandCancellation 5] base))
  check "cancellation clears monster statuses"
    (case monsterById 1 outCancel.game of
       Just m => null m.statuses && m.state == Chasing
       Nothing => False)

  let outPoly = step (Zap 414 E)
                  (setMonster bigRat
                    (addToPack [wand 414 WandPolymorph 5] base))
  check "polymorph announces a new monster"
    (hasMessageContaining "becomes a" outPoly)
  check "polymorph keeps one monster"
    (length (currentLevel outPoly.game).monsters == 1)

ringTests : IO ()
ringTests = do
  let protection = ring 500 RingProtection 2 False
      strength = ring 501 RingAddStrength 1 False
      extra = ring 502 RingIncreaseDamage 0 False
      gRings = addToPack [protection, strength, extra] base
      outFirst = step (PutOnRing 500) gRings
  check "putting on a ring consumes a turn" outFirst.turnConsumed
  check "the first ring goes on the left hand"
    (outFirst.game.player.leftRing == Just 500)
  check "a +2 protection ring adds two points of ring AC"
    (outFirst.game.player.ringArmor == 2)
  check "ring AC feeds the armor class"
    (playerArmorClass outFirst.game.player
     == outFirst.game.player.armor - 2)

  let outSecond = step (PutOnRing 501) outFirst.game
  check "the second ring goes on the right hand"
    (outSecond.game.player.rightRing == Just 501)
  check "an add-strength ring raises effective strength"
    (outSecond.game.player.ringStrength == 1
     && effectiveStrength outSecond.game.player == 17)

  let outThird = step (PutOnRing 502) outSecond.game
  check "a third ring is refused"
    (hasMessageContaining "fingers are already full" outThird)
  check "a refused ring does not consume a turn"
    (not outThird.turnConsumed)

  let outOff = step (TakeOff 500) outSecond.game
  check "taking off a ring clears its bonus"
    (outOff.game.player.leftRing == Nothing
     && outOff.game.player.ringArmor == 0)

  let cursedRing = ring 503 RingProtection 0 True
      gCursed = addToPack [cursedRing] base
      outCursed = step (PutOnRing 503) gCursed
      outRemove = step (TakeOff 503) outCursed.game
  check "a cursed ring cannot be removed"
    (hasMessageContaining "cursed ring" outRemove
     && outRemove.game.player.leftRing == Just 503)

  let seeRing = ring 504 RingSeeInvisible 0 False
      outSee = step (PutOnRing 504) (addToPack [seeRing] base)
  check "a see-invisible ring grants sight"
    (playerSeesInvisible outSee.game)

  let dexRing = ring 513 RingDexterity 2 False
      outDex = step (PutOnRing 513) (addToPack [dexRing] base)
  check "a dexterity ring improves accuracy but not AC"
    (outDex.game.player.ringAccuracy == 2
     && outDex.game.player.ringArmor == 0)

  let aggroRing = ring 505 RingAggravateMonster 0 False
      asleepRat = MkMonster 1 Emu (MkCoord 8 5) 4 4 Asleep []
      outAggro = step (PutOnRing 505)
                   (setMonster asleepRat (addToPack [aggroRing] base))
  check "an aggravate ring wakes monsters"
    (maybe False (\m => m.state == Chasing) (monsterById 1 outAggro.game))

  let regenRing = ring 506 RingRegeneration 0 False
      gRegen = setPlayerStats (\p => { hp := 5 } p)
                 (addToPack [regenRing] base)
      outRegen0 = step (PutOnRing 506) gRegen
      outRegen1 = step Wait outRegen0.game
      outRegen2 = step Wait outRegen1.game
      outRegen3 = step Wait outRegen2.game
  check "regeneration heals one HP per turn"
    (outRegen1.game.player.hp == 7 && outRegen3.game.player.hp == 9)

  let slowRing = ring 507 RingSlowDigestion 0 False
      outSlow0 = step (PutOnRing 507) (addToPack [slowRing] base)
      outSlow1 = step Wait outSlow0.game
      outSlow2 = step Wait outSlow1.game
  check "slow digestion halves hunger drain"
    (outSlow2.game.player.hunger == 1298)

  let slowRing2 = ring 508 RingSlowDigestion 0 False
      gSlow2 = addToPack [slowRing2] outSlow0.game
      outSlow3 = step (PutOnRing 508) gSlow2
      outSlow4 = step Wait outSlow3.game
  check "two slow-digestion rings stop hunger"
    (outSlow4.game.player.hunger == 1299)

  let maintainRing = ring 509 RingMaintainArmor 0 False
      leather = armor 510 LeatherArmor 0 False
      gMaint = addToPack [maintainRing, leather] base
      outMaint0 = step (PutOnRing 509) gMaint
      outMaint1 = step (Wear 510) outMaint0.game
      gRust = setTraps [MkTrap (MkCoord 5 5) Rust False] outMaint1.game
      outMaint = step (Move E) gRust
      maintItem = findPackItem outMaint.game 510
  check "maintain armor protects worn armor"
    (maybe False (\i => i.enchant == 0) maintItem)

  let stealthRing = ring 511 RingStealth 0 False
      farRat = MkMonster 1 Emu (MkCoord 14 5) 4 4 Asleep []
      gNoStealth = setMonster farRat base
      outNoStealth = step Wait gNoStealth
      gStealth = step (PutOnRing 511) (setMonster farRat
                    (addToPack [stealthRing] base))
      outStealth = step Wait gStealth.game
  check "a distant monster wakes without stealth"
    (maybe False (\m => m.state == Chasing) (monsterById 1 outNoStealth.game))
  check "a stealth ring shortens the wake radius"
    (maybe False (\m => m.state == Asleep) (monsterById 1 outStealth.game))

  let teleRing = ring 512 RingTeleportation 0 False
      gTele = addToPack [teleRing] base
      outTele0 = step (PutOnRing 512) gTele
  check "a teleportation ring is equipped"
    (outTele0.game.player.leftRing == Just 512)
  let teleportLoop : Nat -> Game -> Game
      teleportLoop Z g = g
      teleportLoop (S k) g =
        let g' = (step Wait g).game
        in if g'.player.pos /= base.player.pos then g' else teleportLoop k g'
      teleported = teleportLoop 500 outTele0.game
  check "a teleportation ring eventually moves the player"
    (teleported.player.pos /= base.player.pos)

isFloorItem : Item -> Bool
isFloorItem i = case i.location of
                  OnFloor _ _ => True
                  InPack => False
                  CarriedBy _ => False

throwTests : IO ()
throwTests = do
  let bigRat = MkMonster 1 Emu (MkCoord 6 5) 100 100 Awake []
      dagger = weapon 600 Dagger 0 False
      gThrow = setMonster bigRat (addToPack [dagger] base)
      outThrow = step (Throw 600 E) gThrow
  check "throwing consumes a turn" outThrow.turnConsumed
  check "a thrown weapon damages the target"
    (case monsterById 1 outThrow.game of
       Just m => m.hp < 100
       Nothing => True)
  check "a thrown weapon leaves the pack"
    (not (any (\i => i.id == 600 && i.location == InPack) outThrow.game.items))
  check "a thrown weapon lands on the floor"
    (any (\i => i.id == 600 && i.location == OnFloor 1 (MkCoord 5 5))
         outThrow.game.items)

  let potionItem = potion 601 PotionHealing
      gPotion = setMonster bigRat (addToPack [potionItem] base)
      outPotion = step (Throw 601 E) gPotion
  check "a thrown potion damages the target"
    (case monsterById 1 outPotion.game of
       Just m => m.hp < 100
       Nothing => True)
  check "a thrown potion shatters and disappears"
    (not (any (\i => i.id == 601) outPotion.game.items))

  let equipped = weapon 602 Dagger 0 False
      gEquipped = addToPack [equipped] base
      outWield = step (Wield 602) gEquipped
      outEquippedThrow = step (Throw 602 E) outWield.game
  check "an equipped item cannot be thrown"
    (hasMessageContaining "Take it off" outEquippedThrow)
  check "a refused throw does not consume a turn"
    (not outEquippedThrow.turnConsumed)

  let floorDagger = weapon 603 Dagger 0 False
      outFloor = step (Throw 603 E) (addToPack [floorDagger] base)
  check "throwing at empty space lands on the floor"
    (any (\i => i.id == 603 && isFloorItem i) outFloor.game.items)

monsterStatusTests : IO ()
monsterStatusTests = do
  let ratAt : Coord -> MonsterState -> List Status -> Monster
      ratAt c s ss = MkMonster 1 Emu c 4 4 s ss

  let held = ratAt (MkCoord 6 5) Chasing [MkStatus Held 5]
      outHeld = step Wait (setMonster held base)
  check "a held monster stays put"
    (maybe False (\m => m.pos == MkCoord 6 5) (monsterById 1 outHeld.game))
  check "the held status is still active"
    (maybe False (monsterHas Held) (monsterById 1 outHeld.game))

  let confused = ratAt (MkCoord 6 5) Chasing [MkStatus Confused 10]
      outConfused = step Wait (setMonster confused base)
  check "a confused monster moves randomly"
    (maybe False (\m => m.pos /= MkCoord 6 5)
       (monsterById 1 outConfused.game))

  let scared = ratAt (MkCoord 8 5) Chasing [MkStatus Scared 10]
      outScared = step Wait (setMonster scared base)
  check "a scared monster flees"
    (maybe False (\m => m.pos /= MkCoord 8 5
                        && chebyshev m.pos base.player.pos >= 4)
       (monsterById 1 outScared.game))

  let hasted = ratAt (MkCoord 8 5) Chasing [MkStatus Hasted 10]
      outHasted = step Wait (setMonster hasted base)
  check "a hasted monster acts twice"
    (maybe False (\m => chebyshev m.pos base.player.pos == 2)
       (monsterById 1 outHasted.game))

  let slowed = ratAt (MkCoord 8 5) Chasing [MkStatus Slowed 10]
      outSlowed = step Wait (setMonster slowed base)
  check "a slowed monster skips its action"
    (maybe False (\m => m.pos == MkCoord 8 5) (monsterById 1 outSlowed.game))

  let paralyzed = ratAt (MkCoord 8 5) Chasing [MkStatus Paralyzed 10]
      outParalyzed = step Wait (setMonster paralyzed base)
  check "a paralyzed monster skips its action"
    (maybe False (\m => m.pos == MkCoord 8 5)
       (monsterById 1 outParalyzed.game))

  let gInvisible = withStatus Invisible 10
                     (setMonster (ratAt (MkCoord 8 5) Chasing []) base)
      outInvisible = step Wait gInvisible
  check "an invisible player is not chased at range"
    (maybe False (\m => m.pos == MkCoord 8 5)
       (monsterById 1 outInvisible.game))

  let shortHeld = ratAt (MkCoord 6 5) Chasing [MkStatus Held 1]
      outExpired = step Wait (setMonster shortHeld base)
  check "monster statuses expire"
    (maybe False (\m => not (monsterHas Held m))
       (monsterById 1 outExpired.game))

vulnerablePlayer : Game -> Game
vulnerablePlayer =
  setPlayerStats (\p => { armor := 100, hp := 100, maxHp := 100 } p)

monsterAbilityTests : IO ()
monsterAbilityTests = do
  let adjacent : MonsterId -> MonsterKind -> Int32 -> Monster
      adjacent i k hp = MkMonster i k (MkCoord 5 5) hp hp Chasing []

  let outPoison = step Wait
        (vulnerablePlayer
          (setMonster (adjacent 10 Rattlesnake 20) base))
  check "a rattlesnake drains strength on a hit"
    (outPoison.game.player.strength < 16)

  check "a medusa has three attacks"
    (length (monsterSpec Medusa).attacks == 3)

  let outHold = step Wait
        (vulnerablePlayer
          (setMonster (adjacent 12 VenusFlytrap 20) base))
  check "a venus flytrap holds on a hit"
    (hasStatus Held outHold.game.player)

  let outDrain = step Wait
        (vulnerablePlayer
          (setMonster (adjacent 13 Vampire 20) base))
  check "a vampire drains 1d5 maximum HP"
    (outDrain.game.player.maxHp < 100 && outDrain.game.player.maxHp >= 95)

  let gWraith = setPlayerStats (\p => { exp := 20 } p)
                  (vulnerablePlayer
                    (setMonster (adjacent 14 Wraith 20) base))
      outWraith = step Wait gWraith
  check "a wraith drains experience"
    (outWraith.game.player.exp < 20)

  let leather = armor 700 LeatherArmor 2 False
      outWear = step (Wear 700) (addToPack [leather] base)
      outRust = step Wait
        (vulnerablePlayer
          (setMonster (adjacent 15 Aquator 20) outWear.game))
  check "an aquator rusts worn armor"
    (maybe False (\i => i.enchant == 1) (findPackItem outRust.game 700))

  let gLep = setPlayerStats (\p => { gold := 100 } p)
               (vulnerablePlayer
                 (setMonster (adjacent 16 Leprechaun 20) base))
      outLep = step Wait gLep
  check "a leprechaun steals gold"
    (outLep.game.player.gold < 100)

  let gNymph = vulnerablePlayer
                 (setMonster (adjacent 17 Nymph 20)
                   (addToPack [potion 701 PotionHealing] base))
      outNymph = step Wait gNymph
  check "a nymph steals a pack item"
    (not (elem 701 outNymph.game.player.inventory)
     && (case find (\i => i.id == 701) outNymph.game.items of
           Just i => i.location == CarriedBy 17
           Nothing => False))

  let carried = MkItem 702 (Potion PotionHealing) (CarriedBy 18)
                          1 0 False 0 False
      gDrop = { items := [carried] }
                (setPlayerStats (\p => { strength := 100, level := 100 } p)
                  (setMonster (MkMonster 18 Nymph (MkCoord 5 5)
                                          1 1 Chasing []) base))
      outDrop = step (Move E) gDrop
  check "a killed monster drops carried items"
    (case find (\i => i.id == 702) outDrop.game.items of
       Just i => i.location == OnFloor 1 (MkCoord 5 5)
       Nothing => False)

  let outTroll = step Wait
        (setMonster (MkMonster 19 Troll (MkCoord 10 5)
                                5 20 Chasing []) base)
  check "a troll regenerates"
    (maybe False (\m => m.hp == 6) (monsterById 19 outTroll.game))

  let dragon = MkMonster 21 Dragon (MkCoord 10 5) 50 50 Chasing []
      breathOutcomes : List Outcome
      breathOutcomes =
        [ step Wait ({ rng := fromSeed k }
                      (vulnerablePlayer (setMonster dragon base)))
        | k <- [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15] ]
  check "a dragon sometimes breathes fire at range"
    (any (hasMessageContaining "breathes fire") breathOutcomes)

  let outFlytrap = step Wait
        (setMonster (MkMonster 22 VenusFlytrap (MkCoord 10 5)
                                20 20 Chasing []) base)
  check "a venus flytrap stays put"
    (maybe False (\m => m.pos == MkCoord 10 5)
       (monsterById 22 outFlytrap.game))

playerStatusTests : IO ()
playerStatusTests = do
  let outSleep = step (Move E) (withStatus Sleeping 5 base)
  check "a sleeping player cannot move"
    (outSleep.turnConsumed
     && outSleep.game.player.pos == base.player.pos
     && hasMessage "You are asleep." outSleep)

  let outPara = step (Move E) (withStatus Paralyzed 5 base)
  check "a paralyzed player cannot move"
    (outPara.turnConsumed
     && outPara.game.player.pos == base.player.pos
     && hasMessage "You are paralyzed." outPara)

  let outHeld = step (Move E) (withStatus Held 5 base)
  check "a held player cannot move"
    (outHeld.turnConsumed
     && outHeld.game.player.pos == base.player.pos
     && hasMessage "You are held in place." outHeld)

  let weak = MkMonster 30 Emu (MkCoord 5 5) 1 1 Chasing []
      gHeldAttack = setPlayerStats (\p => { strength := 100, level := 100 } p)
                      (withStatus Held 5 (setMonster weak base))
      outHeldAttack = step (Move E) gHeldAttack
  check "a held player can still attack"
    (outHeldAttack.turnConsumed
     && isNothing (monsterById 30 outHeldAttack.game))

trapEffectTests : IO ()
trapEffectTests = do
  let gSleep = setTraps [MkTrap (MkCoord 5 5) Sleep False] base
      outSleep = step (Move E) gSleep
  check "a sleep trap puts the player to sleep"
    (hasStatus Sleeping outSleep.game.player
     && hasMessage "You fall asleep." outSleep)
  check "a triggered sleep trap is revealed"
    (case (currentLevel outSleep.game).traps of
       [t] => t.revealed
       _ => False)

  let gBear = setTraps [MkTrap (MkCoord 5 5) Bear False] base
      outBear = step (Move E) gBear
  check "a bear trap holds the player"
    (hasStatus Held outBear.game.player
     && outBear.game.player.hp == base.player.hp)

  let gDart = setTraps [MkTrap (MkCoord 5 5) DartTrap False] base
      outDart = step (Move E) gDart
  check "a dart trap damages the player"
    (outDart.game.player.hp < base.player.hp
     && hasMessageContaining "You trigger a dart trap." outDart)

  let leather = armor 703 LeatherArmor 2 False
      gWorn = step (Wear 703) (addToPack [leather] base)
      gRust = setTraps [MkTrap (MkCoord 5 5) Rust False] gWorn.game
      outRustTrap = step (Move E) gRust
  check "a rust trap weakens unprotected armor"
    (maybe False (\i => i.enchant == 1) (findPackItem outRustTrap.game 703))

  let gMysterious = setTraps [MkTrap (MkCoord 5 5) Mysterious False] base
      outMysterious = step (Move E) gMysterious
  check "a mysterious trap only makes a noise"
    (hasMessageContaining "strange noise" outMysterious
     && outMysterious.game.player.pos == MkCoord 5 5)

public export
run : IO ()
run = do
  appearanceTests
  scrollTests
  wandTests
  ringTests
  throwTests
  monsterStatusTests
  monsterAbilityTests
  playerStatusTests
  trapEffectTests
  putStrLn "M4 tests passed"
