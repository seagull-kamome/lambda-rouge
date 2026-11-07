||| Item spawning, identification and pack helpers.
|||
||| Rogue 5.4.4 has 14 potions, 18 scrolls, 14 rings and 14 wands, plus
||| 9 weapons and 8 armors.  The percentages and gold values below are the
||| published 5.4.4 item tables.  Every roll still goes through the
||| supplied `Rng`, and per-run appearances are derived deterministically
||| from the run seed.
module LambdaRogue.Core.Item

import Data.List
import Data.Maybe
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types

%default covering

||| The number of ordinary objects on a level.  The authentic per-room
||| placement is not part of the published tables; this M4 density keeps
||| the 80x22 map readable.
public export
itemCount : Depth -> Nat
itemCount d = cast (min 8 (2 + d `div` 3))

||| The number of gold piles placed on a level.
public export
goldPileCount : Depth -> Nat
goldPileCount d = cast (min 5 (1 + d `div` 5))

||| Generation weights out of 100 for each potion.
public export
potionWeight : PotionKind -> Nat
potionWeight PotionConfusion = 7
potionWeight PotionHallucination = 8
potionWeight PotionPoison = 8
potionWeight PotionStrength = 13
potionWeight PotionSeeInvisible = 3
potionWeight PotionHealing = 13
potionWeight PotionDetectMonsters = 6
potionWeight PotionMagicDetection = 6
potionWeight PotionRaiseLevel = 2
potionWeight PotionExtraHealing = 5
potionWeight PotionHasteSelf = 5
potionWeight PotionRestoreStrength = 13
potionWeight PotionBlindness = 5
potionWeight PotionLevitation = 6

public export
scrollWeight : ScrollKind -> Nat
scrollWeight ScrollConfuseMonster = 7
scrollWeight ScrollMagicMapping = 4
scrollWeight ScrollHoldMonster = 2
scrollWeight ScrollSleep = 3
scrollWeight ScrollEnchantArmor = 7
scrollWeight ScrollIdentifyPotion = 10
scrollWeight ScrollIdentifyScroll = 10
scrollWeight ScrollIdentifyWeapon = 6
scrollWeight ScrollIdentifyArmor = 7
scrollWeight ScrollIdentifyRingOrWand = 10
scrollWeight ScrollScareMonster = 3
scrollWeight ScrollFoodDetection = 2
scrollWeight ScrollTeleportation = 5
scrollWeight ScrollEnchantWeapon = 8
scrollWeight ScrollCreateMonster = 4
scrollWeight ScrollRemoveCurse = 7
scrollWeight ScrollAggravateMonsters = 3
scrollWeight ScrollProtectArmor = 2

public export
ringWeight : RingKind -> Nat
ringWeight RingProtection = 9
ringWeight RingAddStrength = 9
ringWeight RingSustainStrength = 5
ringWeight RingSearching = 10
ringWeight RingSeeInvisible = 10
ringWeight RingAdornment = 1
ringWeight RingAggravateMonster = 10
ringWeight RingDexterity = 8
ringWeight RingIncreaseDamage = 8
ringWeight RingRegeneration = 4
ringWeight RingSlowDigestion = 9
ringWeight RingTeleportation = 5
ringWeight RingStealth = 7
ringWeight RingMaintainArmor = 5

public export
wandWeight : WandKind -> Nat
wandWeight WandLight = 12
wandWeight WandInvisibility = 6
wandWeight WandLightning = 3
wandWeight WandFire = 3
wandWeight WandCold = 3
wandWeight WandPolymorph = 15
wandWeight WandMagicMissile = 10
wandWeight WandHasteMonster = 10
wandWeight WandSlowMonster = 11
wandWeight WandDrainLife = 9
wandWeight WandNothing = 1
wandWeight WandTeleportAway = 6
wandWeight WandTeleportTo = 6
wandWeight WandCancellation = 5

public export
allPotions : List PotionKind
allPotions =
  [PotionConfusion, PotionHallucination, PotionPoison, PotionStrength,
   PotionSeeInvisible, PotionHealing, PotionDetectMonsters,
   PotionMagicDetection, PotionRaiseLevel, PotionExtraHealing,
   PotionHasteSelf, PotionRestoreStrength, PotionBlindness, PotionLevitation]

public export
allScrolls : List ScrollKind
allScrolls =
  [ScrollConfuseMonster, ScrollMagicMapping, ScrollHoldMonster, ScrollSleep,
   ScrollEnchantArmor, ScrollIdentifyPotion, ScrollIdentifyScroll,
   ScrollIdentifyWeapon, ScrollIdentifyArmor, ScrollIdentifyRingOrWand,
   ScrollScareMonster, ScrollFoodDetection, ScrollTeleportation,
   ScrollEnchantWeapon, ScrollCreateMonster, ScrollRemoveCurse,
   ScrollAggravateMonsters, ScrollProtectArmor]

public export
allWands : List WandKind
allWands =
  [WandLight, WandInvisibility, WandLightning, WandFire, WandCold,
   WandPolymorph, WandMagicMissile, WandHasteMonster, WandSlowMonster,
   WandDrainLife, WandNothing, WandTeleportAway, WandTeleportTo,
   WandCancellation]

public export
allRings : List RingKind
allRings =
  [RingProtection, RingAddStrength, RingSustainStrength, RingSearching,
   RingSeeInvisible, RingAdornment, RingAggravateMonster, RingDexterity,
   RingIncreaseDamage, RingRegeneration, RingSlowDigestion,
   RingTeleportation, RingStealth, RingMaintainArmor]

public export
allWeapons : List WeaponKind
allWeapons =
  [Mace, LongSword, ShortBow, Arrow, Dagger, TwoHandedSword, Dart,
   Shuriken, Spear]

public export
allArmors : List ArmorKind
allArmors =
  [LeatherArmor, RingMail, StuddedLeather, ScaleMail, ChainMail,
   SplintMail, BandedMail, PlateMail]

||| Every ordinary item kind can appear on any level.  This list is used by
||| tests and by the palette/reference views; actual generation uses the
||| authentic class and kind weights in `randomItemKind`.
public export
itemPool : Depth -> List ItemKind
itemPool d =
  map Weapon allWeapons
  ++ map Armor allArmors
  ++ [Food FoodRation]
  ++ map Potion allPotions
  ++ map Scroll allScrolls
  ++ map Wand allWands
  ++ map Ring allRings
  ++ [Gold, Amulet]

||| Pick one entry from a weighted list.  Returns `Nothing` only for an
||| empty list or zero total weight, without consuming the generator.
weightedPick : List (Nat, a) -> Rng -> (Maybe a, Rng)
weightedPick [] g = (Nothing, g)
weightedPick xs g =
  let weightSum = foldl (\acc, p => acc + fst p) 0 xs
  in if weightSum == 0
        then (Nothing, g)
        else let (v, g') = uniform (cast weightSum) g
             in go (cast v) xs g'
  where
    go : Nat -> List (Nat, a) -> Rng -> (Maybe a, Rng)
    go _ [] g = (Nothing, g)
    go n ((w, x) :: rest) g =
      if n < w then (Just x, g) else go (minus n w) rest g

pickPotion : Rng -> (Maybe PotionKind, Rng)
pickPotion = weightedPick (map (\p => (potionWeight p, p)) allPotions)

pickScroll : Rng -> (Maybe ScrollKind, Rng)
pickScroll = weightedPick (map (\s => (scrollWeight s, s)) allScrolls)

pickRing : Rng -> (Maybe RingKind, Rng)
pickRing = weightedPick (map (\r => (ringWeight r, r)) allRings)

pickWand : Rng -> (Maybe WandKind, Rng)
pickWand = weightedPick (map (\w => (wandWeight w, w)) allWands)

pickWeapon : Rng -> (Maybe WeaponKind, Rng)
pickWeapon = weightedPick (map (\w => (weaponWeight w, w)) allWeapons)

pickArmor : Rng -> (Maybe ArmorKind, Rng)
pickArmor = weightedPick (map (\a => (armorWeight a, a)) allArmors)

||| Object-class distribution from the 5.4.4 `things` table:
||| potion 26, scroll 36, food 16, weapon 7, armor 7, ring 4, stick 4.
||| Gold is placed separately by `spawnItems`, so it is not part of this
||| 100-point distribution.  The source's "starving players get food"
||| override (`no_food > 3`) is intentionally not modelled.
public export
randomItemKind : Rng -> (Maybe ItemKind, Rng)
randomItemKind g0 =
  let (roll, g1) = uniform 100 g0
      r = cast roll
  in if r < 26
        then let (k, g2) = pickPotion g1 in (map Potion k, g2)
        else if r < 62
                then let (k, g2) = pickScroll g1 in (map Scroll k, g2)
                else if r < 78
                        then (Just (Food FoodRation), g1)
                        else if r < 85
                                then let (k, g2) = pickWeapon g1 in (map Weapon k, g2)
                                else if r < 92
                                        then let (k, g2) = pickArmor g1 in (map Armor k, g2)
                                        else if r < 96
                                                then let (k, g2) = pickRing g1 in (map Ring k, g2)
                                                else let (k, g2) = pickWand g1 in (map Wand k, g2)

||| Gold value of one item, from the 5.4.4 item tables.
public export
itemGoldValue : ItemKind -> Int32
itemGoldValue (Weapon w) = weaponValue w
itemGoldValue (Armor a) = armorGoldValue a
itemGoldValue (Food FoodRation) = 2
itemGoldValue (Potion p) =
  case p of
    PotionConfusion => 5
    PotionHallucination => 5
    PotionPoison => 5
    PotionStrength => 150
    PotionSeeInvisible => 100
    PotionHealing => 130
    PotionDetectMonsters => 130
    PotionMagicDetection => 105
    PotionRaiseLevel => 250
    PotionExtraHealing => 200
    PotionHasteSelf => 190
    PotionRestoreStrength => 130
    PotionBlindness => 5
    PotionLevitation => 75
itemGoldValue (Scroll s) =
  case s of
    ScrollConfuseMonster => 140
    ScrollMagicMapping => 150
    ScrollHoldMonster => 180
    ScrollSleep => 5
    ScrollEnchantArmor => 160
    ScrollIdentifyPotion => 80
    ScrollIdentifyScroll => 80
    ScrollIdentifyWeapon => 80
    ScrollIdentifyArmor => 100
    ScrollIdentifyRingOrWand => 115
    ScrollScareMonster => 200
    ScrollFoodDetection => 60
    ScrollTeleportation => 165
    ScrollEnchantWeapon => 150
    ScrollCreateMonster => 75
    ScrollRemoveCurse => 105
    ScrollAggravateMonsters => 20
    ScrollProtectArmor => 250
itemGoldValue (Ring r) =
  case r of
    RingProtection => 400
    RingAddStrength => 400
    RingSustainStrength => 280
    RingSearching => 420
    RingSeeInvisible => 310
    RingAdornment => 10
    RingAggravateMonster => 10
    RingDexterity => 440
    RingIncreaseDamage => 400
    RingRegeneration => 460
    RingSlowDigestion => 240
    RingTeleportation => 30
    RingStealth => 470
    RingMaintainArmor => 380
itemGoldValue (Wand w) =
  case w of
    WandLight => 250
    WandInvisibility => 5
    WandLightning => 330
    WandFire => 330
    WandCold => 330
    WandPolymorph => 310
    WandMagicMissile => 170
    WandHasteMonster => 5
    WandSlowMonster => 350
    WandDrainLife => 300
    WandNothing => 5
    WandTeleportAway => 340
    WandTeleportTo => 50
    WandCancellation => 280
itemGoldValue Gold = 1
itemGoldValue Amulet = 0

||| Weapon/armor enchantment from the 5.4.4 `new_thing` table.  Weapons
||| are cursed 10% of the time and blessed 5% of the time; armor is
||| cursed 20% and blessed 8%.  A cursed roll subtracts `rnd(3)+1`, a
||| blessed roll adds `rnd(3)+1`, and an ordinary roll is +0.  One
||| hundred-sided roll is always consumed; the magnitude roll only
||| happens for cursed or blessed equipment.
enchantRoll : ItemKind -> Rng -> (Int32, Bool, Rng)
enchantRoll kind g0 =
  let (roll, g1) = uniform 100 g0
      r = cast roll
      (cursedAt, blessedAt) =
        case kind of
          Armor _ => (20, 28)
          _ => (10, 15)
  in if r < cursedAt
        then let (n, g2) = uniform 3 g1
             in (negate (cast n + 1), True, g2)
        else if r < blessedAt
                then let (n, g2) = uniform 3 g1
                     in (cast n + 1, False, g2)
                else (0, False, g1)

||| Ring increments.  Only protection, add strength, dexterity (the
||| 5.4.4 "increase hit" ring) and increase damage roll `rnd(3)`: a zero
||| becomes -1 and curses the ring.  Aggravate-monster and teleportation
||| rings are always cursed but have no increment; every other ring is
||| plain +0.  No RNG is consumed for the plain rings.
ringEnchantRoll : RingKind -> Rng -> (Int32, Bool, Rng)
ringEnchantRoll kind g0 =
  case kind of
    RingProtection =>
      let (n, g1) = uniform 3 g0
      in if n == 0 then (-1, True, g1) else (cast n, False, g1)
    RingAddStrength =>
      let (n, g1) = uniform 3 g0
      in if n == 0 then (-1, True, g1) else (cast n, False, g1)
    RingDexterity =>
      let (n, g1) = uniform 3 g0
      in if n == 0 then (-1, True, g1) else (cast n, False, g1)
    RingIncreaseDamage =>
      let (n, g1) = uniform 3 g0
      in if n == 0 then (-1, True, g1) else (cast n, False, g1)
    RingAggravateMonster => (0, True, g0)
    RingTeleportation => (0, True, g0)
    _ => (0, False, g0)

weaponOrArmor : ItemKind -> Bool
weaponOrArmor (Weapon _) = True
weaponOrArmor (Armor _) = True
weaponOrArmor _ = False

itemAmount : Depth -> ItemKind -> Rng -> (Int32, Rng)
itemAmount depth Gold g =
  let (n, g') = roll 1 10 g
  in (max 1 (n * depth), g')
itemAmount _ _ g = (1, g)

||| Wand charges from `fix_stick`: a wand of light starts with 10..19
||| charges, every other wand with 3..7.  Scrolls, potions and rings have
||| none.
wandCharges : ItemKind -> Rng -> (Int32, Rng)
wandCharges (Wand WandLight) g =
  let (n, g') = uniform 10 g
  in (cast n + 10, g')
wandCharges (Wand _) g =
  let (n, g') = roll 1 5 g
  in (n + 2, g')
wandCharges _ g = (0, g)

||| Build one item, rolling enchantment/curses for equipment, the gold
||| amount for gold and charges for wands.  Every roll goes through the
||| supplied `Rng`.
public export
makeItem : Depth -> ItemId -> ItemKind -> Coord -> Rng -> (Item, Rng)
makeItem depth iid kind c g0 =
  let (count, g1) = itemAmount depth kind g0
      (charges, g2) = wandCharges kind g1
  in if weaponOrArmor kind
        then let (enchant, cursed, g3) = enchantRoll kind g2
                 item : Item
                 item = MkItem iid kind (OnFloor depth c) count enchant
                               cursed charges False
             in (item, g3)
        else case kind of
               Ring r =>
                 let (enchant, cursed, g3) = ringEnchantRoll r g2
                     item : Item
                     item = MkItem iid kind (OnFloor depth c) count enchant
                                   cursed charges False
                 in (item, g3)
               _ => (MkItem iid kind (OnFloor depth c) count 0 False charges False,
                     g2)

||| Spawn ordinary objects and gold on the given candidate cells, removing
||| each used cell.  Gold piles are placed after the ordinary objects so
||| the object-class percentages stay authentic.
public export
spawnItems : Depth -> List Coord -> ItemId -> Rng
          -> (List Item, ItemId, Rng)
spawnItems depth candidates nextId g0 =
  let (ordinary, nextId1, g1, remaining) =
        spawnOrdinary (itemCount depth) candidates nextId g0 []
      (gold, nextId2, g2) =
        spawnGold (goldPileCount depth) remaining nextId1 g1 []
  in (ordinary ++ gold, nextId2, g2)
  where
    spawnOrdinary : Nat -> List Coord -> ItemId -> Rng -> List Item
                 -> (List Item, ItemId, Rng, List Coord)
    spawnOrdinary Z cs nextId g acc = (reverse acc, nextId, g, cs)
    spawnOrdinary (S k) [] nextId g acc = (reverse acc, nextId, g, [])
    spawnOrdinary (S k) cs nextId g acc =
      let (kindOpt, g1) = randomItemKind g
          (coordOpt, g2) = pick cs g1
      in case (kindOpt, coordOpt) of
           (Just kind, Just c) =>
             let (item, g3) = makeItem depth nextId kind c g2
                 cs' = filter (/= c) cs
             in spawnOrdinary k cs' (nextId + 1) g3 (item :: acc)
           _ => (reverse acc, nextId, g2, cs)

    spawnGold : Nat -> List Coord -> ItemId -> Rng -> List Item
             -> (List Item, ItemId, Rng)
    spawnGold Z _ nextId g acc = (reverse acc, nextId, g)
    spawnGold (S k) [] nextId g acc = (reverse acc, nextId, g)
    spawnGold (S k) cs nextId g acc =
      let (coordOpt, g1) = pick cs g
      in case coordOpt of
           Just c =>
             let (item, g2) = makeItem depth nextId Gold c g1
                 cs' = filter (/= c) cs
             in spawnGold k cs' (nextId + 1) g2 (item :: acc)
           Nothing => (reverse acc, nextId, g1)

||| The fixed fallback appearance lists.  `rollAppearances` shuffles these
||| once per run, so the same kind always has the same appearance inside a
||| run while different runs get different mappings.
potionAppearanceNames : List String
potionAppearanceNames =
  ["blue potion", "red potion", "green potion", "yellow potion",
   "black potion", "purple potion", "white potion", "orange potion",
   "pink potion", "cyan potion", "silver potion", "golden potion",
   "brown potion", "clear potion"]

scrollAppearanceNames : List String
scrollAppearanceNames =
  ["scroll labeled VELOX NEB", "scroll labeled KIRJE",
   "scroll labeled FOOBIE BLETCH", "scroll labeled ZELGO MER",
   "scroll labeled GABLEC NOCH", "scroll labeled THARR",
   "scroll labeled ELBIB YLOH", "scroll labeled LEP GEX VEN ZEA",
   "scroll labeled PRIRUTSENIE", "scroll labeled TEMOV",
   "scroll labeled XIXAXA XOXAXA XUXAXA", "scroll labeled VERR YED HORRE",
   "scroll labeled DAI YUK", "scroll labeled PLUGH",
   "scroll labeled ANDOVA BEGARIN", "scroll labeled KERNOD WEL",
   "scroll labeled JUYED AWK YACC", "scroll labeled NR 9"]

wandAppearanceNames : List String
wandAppearanceNames =
  ["oak wand", "crystal wand", "silver wand", "golden wand",
   "ebony wand", "ivory wand", "copper wand", "iron wand",
   "maple wand", "willow wand", "jade wand", "obsidian wand",
   "pearl wand", "runed wand"]

ringAppearanceNames : List String
ringAppearanceNames =
  ["ruby ring", "sapphire ring", "emerald ring", "topaz ring",
   "wooden ring", "iron ring", "gold ring", "silver ring",
   "copper ring", "jade ring", "pearl ring", "opal ring",
   "obsidian ring", "crystal ring"]

rollCategory : List ItemKind -> List String -> Rng
            -> (List (ItemKind, String), Rng)
rollCategory kinds names g =
  let (shuffled, g') = shuffle names g
  in (zip kinds shuffled, g')

||| Shuffle each appearance list once for a run.  The resulting mapping is
||| stored in `Game.appearances` and is part of the deterministic state.
public export
rollAppearances : Rng -> (List (ItemKind, String), Rng)
rollAppearances g0 =
  let (potions, g1) = rollCategory (map Potion allPotions)
                                   potionAppearanceNames g0
      (scrolls, g2) = rollCategory (map Scroll allScrolls)
                                   scrollAppearanceNames g1
      (wands, g3) = rollCategory (map Wand allWands)
                                 wandAppearanceNames g2
      (rings, g4) = rollCategory (map Ring allRings)
                                 ringAppearanceNames g3
  in (potions ++ scrolls ++ wands ++ rings, g4)

||| The appearance of a kind in this run, falling back to the fixed
||| presentation table for fixtures that do not carry a mapping.
public export
appearanceOf : Game -> ItemKind -> String
appearanceOf g k = fromMaybe (itemAppearance k) (lookup k g.appearances)

||| Is the true kind of this item known to the player?  Gold and the Amulet
||| are always known; everything else is learned by using or identifying it.
public export
itemKnown : List ItemKind -> Item -> Bool
itemKnown known i =
  elem i.kind known || i.kind == Gold || i.kind == Amulet

enchantSuffix : Item -> String
enchantSuffix i =
  (if i.enchant > 0 then " +" ++ show i.enchant
   else if i.enchant < 0 then " " ++ show i.enchant
   else "")
  ++ (if i.cursed then " (cursed)" else "")

nameSuffix : Item -> String
nameSuffix i =
  case i.kind of
    Weapon _ => enchantSuffix i
    Armor _ => enchantSuffix i
    Ring _ => enchantSuffix i
    Wand _ => " (" ++ show i.charges ++ " charges)"
    _ => ""

||| The name shown in the pack and on the floor.  An unidentified item
||| keeps its appearance; an unidentified weapon/armor/ring hides
||| enchantment and curse state.  A known wand shows its remaining charges.
public export
itemDisplayName : List ItemKind -> Item -> String
itemDisplayName known i =
  if itemKnown known i
     then itemName i.kind ++ nameSuffix i
     else itemAppearance i.kind

||| The run-aware variant used by the game and the UI.  It consults the
||| per-run appearance mapping before falling back to the fixed table.
public export
itemDisplayNameIn : Game -> Item -> String
itemDisplayNameIn g i =
  if itemKnown g.knownKinds i
     then itemName i.kind ++ nameSuffix i
     else appearanceOf g i.kind

||| A longer description for the inventory panel.
public export
itemDetail : List ItemKind -> Item -> String
itemDetail known i =
  case i.kind of
    Gold => show i.count ++ " gold"
    _ => itemDisplayName known i

||| Run-aware inventory detail.
public export
itemDetailIn : Game -> Item -> String
itemDetailIn g i =
  case i.kind of
    Gold => show i.count ++ " gold"
    _ => itemDisplayNameIn g i

||| Items in pack order.  `Player.inventory` stores IDs newest-first.
public export
packItems : Game -> List Item
packItems g =
  mapMaybe (\iid => find (\i => i.id == iid) g.items) g.player.inventory

public export
findPackItem : Game -> ItemId -> Maybe Item
findPackItem g iid =
  find (\i => i.id == iid && i.location == InPack) g.items
