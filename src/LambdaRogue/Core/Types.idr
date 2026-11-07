||| The core types of the game.
|||
||| This module is pure: it imports neither `IO`, `termui` nor any
||| terminal or file API.  The full type set from `doc/core-api.md` grows
||| from here as the milestones land.
module LambdaRogue.Core.Types

import Data.Bits
import Data.Fin
import Data.List
import Data.Vect
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Rng

%default covering

public export
Depth : Type
Depth = Int32

public export
Turn : Type
Turn = Int32

public export
MonsterId : Type
MonsterId = Bits32

public export
ItemId : Type
ItemId = Bits32

||| The logical map is 80 columns by 22 rows.
public export
mapWidth, mapHeight : Int32
mapWidth = 80
mapHeight = 22

public export
record Coord where
  constructor MkCoord
  x, y : Int32

public export
Eq Coord where
  MkCoord x y == MkCoord x' y' = x == x' && y == y'

public export
Show Coord where
  show (MkCoord x y) = "(" ++ show x ++ ", " ++ show y ++ ")"

public export
data Dir = N | NE | E | SE | S | SW | W | NW

public export
Eq Dir where
  N == N = True
  NE == NE = True
  E == E = True
  SE == SE = True
  S == S = True
  SW == SW = True
  W == W = True
  NW == NW = True
  _ == _ = False

public export
Show Dir where
  show N = "N"
  show NE = "NE"
  show E = "E"
  show SE = "SE"
  show S = "S"
  show SW = "SW"
  show W = "W"
  show NW = "NW"

public export
data DoorState = Open | Closed | Secret | Locked

public export
data StairDir = Up | Down

public export
data Tile
  = Rock
  | Floor
  | Corridor
  | Door DoorState
  | Stairs StairDir

public export
Eq DoorState where
  Open == Open = True
  Closed == Closed = True
  Secret == Secret = True
  Locked == Locked = True
  _ == _ = False

public export
Eq StairDir where
  Up == Up = True
  Down == Down = True
  _ == _ = False

public export
Eq Tile where
  Rock == Rock = True
  Floor == Floor = True
  Corridor == Corridor = True
  Door a == Door b = a == b
  Stairs a == Stairs b = a == b
  _ == _ = False

public export
Show DoorState where
  show Open = "Open"
  show Closed = "Closed"
  show Secret = "Secret"
  show Locked = "Locked"

public export
Show StairDir where
  show Up = "Up"
  show Down = "Down"

public export
Show Tile where
  show Rock = "Rock"
  show Floor = "Floor"
  show Corridor = "Corridor"
  show (Door d) = "Door " ++ show d
  show (Stairs d) = "Stairs " ++ show d

||| Can the player and monsters step onto this tile?
public export
walkable : Tile -> Bool
walkable Floor = True
walkable Corridor = True
walkable (Door Open) = True
walkable (Stairs _) = True
walkable _ = False

||| A closed door can be opened by walking into it in M2.
public export
openable : Tile -> Bool
openable (Door Closed) = True
openable (Door Secret) = True
openable _ = False

||| The logical map grid: 22 rows of 80 tiles, row-major.
public export
Grid : Type
Grid = Vect 22 (Vect 80 Tile)

public export
record Room where
  constructor MkRoom
  x, y, w, h : Int32
  dark : Bool

public export
Eq Room where
  a == b = a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h
           && a.dark == b.dark

||| Rogue 5.4.4's 26 monsters, in alphabetical glyph order.  This is the
||| authentic 5.4.4 roster: the V4/V5.2 names (invisible stalker, jackal,
||| kobold, purple worm, ur-vile, xorn) were replaced by ice monster,
||| jabberwock, kestrel, phantom, black unicorn and xeroc.
public export
data MonsterKind
  = Aquator
  | Bat
  | Centaur
  | Dragon
  | Emu
  | VenusFlytrap
  | Griffin
  | Hobgoblin
  | IceMonster
  | Jabberwock
  | Kestrel
  | Leprechaun
  | Medusa
  | Nymph
  | Orc
  | Phantom
  | Quagga
  | Rattlesnake
  | Snake
  | Troll
  | BlackUnicorn
  | Vampire
  | Wraith
  | Xeroc
  | Yeti
  | Zombie

public export
Eq MonsterKind where
  Aquator == Aquator = True
  Bat == Bat = True
  Centaur == Centaur = True
  Dragon == Dragon = True
  Emu == Emu = True
  VenusFlytrap == VenusFlytrap = True
  Griffin == Griffin = True
  Hobgoblin == Hobgoblin = True
  IceMonster == IceMonster = True
  Jabberwock == Jabberwock = True
  Kestrel == Kestrel = True
  Leprechaun == Leprechaun = True
  Medusa == Medusa = True
  Nymph == Nymph = True
  Orc == Orc = True
  Phantom == Phantom = True
  Quagga == Quagga = True
  Rattlesnake == Rattlesnake = True
  Snake == Snake = True
  Troll == Troll = True
  BlackUnicorn == BlackUnicorn = True
  Vampire == Vampire = True
  Wraith == Wraith = True
  Xeroc == Xeroc = True
  Yeti == Yeti = True
  Zombie == Zombie = True
  _ == _ = False

public export
monsterName : MonsterKind -> String
monsterName Aquator = "aquator"
monsterName Bat = "bat"
monsterName Centaur = "centaur"
monsterName Dragon = "dragon"
monsterName Emu = "emu"
monsterName VenusFlytrap = "venus flytrap"
monsterName Griffin = "griffin"
monsterName Hobgoblin = "hobgoblin"
monsterName IceMonster = "ice monster"
monsterName Jabberwock = "jabberwock"
monsterName Kestrel = "kestrel"
monsterName Leprechaun = "leprechaun"
monsterName Medusa = "medusa"
monsterName Nymph = "nymph"
monsterName Orc = "orc"
monsterName Phantom = "phantom"
monsterName Quagga = "quagga"
monsterName Rattlesnake = "rattlesnake"
monsterName Snake = "snake"
monsterName Troll = "troll"
monsterName BlackUnicorn = "black unicorn"
monsterName Vampire = "vampire"
monsterName Wraith = "wraith"
monsterName Xeroc = "xeroc"
monsterName Yeti = "yeti"
monsterName Zombie = "zombie"

public export
monsterGlyph : MonsterKind -> Char
monsterGlyph Aquator = 'A'
monsterGlyph Bat = 'B'
monsterGlyph Centaur = 'C'
monsterGlyph Dragon = 'D'
monsterGlyph Emu = 'E'
monsterGlyph VenusFlytrap = 'F'
monsterGlyph Griffin = 'G'
monsterGlyph Hobgoblin = 'H'
monsterGlyph IceMonster = 'I'
monsterGlyph Jabberwock = 'J'
monsterGlyph Kestrel = 'K'
monsterGlyph Leprechaun = 'L'
monsterGlyph Medusa = 'M'
monsterGlyph Nymph = 'N'
monsterGlyph Orc = 'O'
monsterGlyph Phantom = 'P'
monsterGlyph Quagga = 'Q'
monsterGlyph Rattlesnake = 'R'
monsterGlyph Snake = 'S'
monsterGlyph Troll = 'T'
monsterGlyph BlackUnicorn = 'U'
monsterGlyph Vampire = 'V'
monsterGlyph Wraith = 'W'
monsterGlyph Xeroc = 'X'
monsterGlyph Yeti = 'Y'
monsterGlyph Zombie = 'Z'

public export
Show MonsterKind where
  show = monsterName

public export
data MonsterState = Asleep | Awake | Chasing | Fleeing

public export
Eq MonsterState where
  Asleep == Asleep = True
  Awake == Awake = True
  Chasing == Chasing = True
  Fleeing == Fleeing = True
  _ == _ = False

public export
Show MonsterState where
  show Asleep = "asleep"
  show Awake = "awake"
  show Chasing = "chasing"
  show Fleeing = "fleeing"

public export
data StatusKind
  = Confused
  | Blinded
  | Hasted
  | SeeInvisible
  | DetectMonsters
  | DetectFood
  | DetectMagic
  | Invisible
  | Poisoned
  | Held
  | Slowed
  | Paralyzed
  | Scared
  | Sleeping
  | Hallucinating
  | Levitated
  | ConfuseNext

public export
Eq StatusKind where
  Confused == Confused = True
  Blinded == Blinded = True
  Hasted == Hasted = True
  SeeInvisible == SeeInvisible = True
  DetectMonsters == DetectMonsters = True
  DetectFood == DetectFood = True
  DetectMagic == DetectMagic = True
  Invisible == Invisible = True
  Poisoned == Poisoned = True
  Held == Held = True
  Slowed == Slowed = True
  Paralyzed == Paralyzed = True
  Scared == Scared = True
  Sleeping == Sleeping = True
  Hallucinating == Hallucinating = True
  Levitated == Levitated = True
  ConfuseNext == ConfuseNext = True
  _ == _ = False

public export
Show StatusKind where
  show Confused = "confused"
  show Blinded = "blinded"
  show Hasted = "hasted"
  show SeeInvisible = "see invisible"
  show DetectMonsters = "detect monsters"
  show DetectFood = "detect food"
  show DetectMagic = "detect magic"
  show Invisible = "invisible"
  show Poisoned = "poisoned"
  show Held = "held"
  show Slowed = "slowed"
  show Paralyzed = "paralyzed"
  show Scared = "scared"
  show Sleeping = "sleeping"
  show Hallucinating = "hallucinating"
  show Levitated = "levitated"
  show ConfuseNext = "confusing hands"

public export
record Status where
  constructor MkStatus
  statusKind : StatusKind
  remaining : Int32

public export
Eq Status where
  a == b = a.statusKind == b.statusKind && a.remaining == b.remaining

public export
record Monster where
  constructor MkMonster
  id : MonsterId
  kind : MonsterKind
  pos : Coord
  hp, maxHp : Int32
  state : MonsterState
  statuses : List Status

public export
Eq Monster where
  a == b = a.id == b.id && a.kind == b.kind && a.pos == b.pos
           && a.hp == b.hp && a.maxHp == b.maxHp && a.state == b.state
           && a.statuses == b.statuses

public export
data FoodKind = FoodRation

public export
Eq FoodKind where
  FoodRation == FoodRation = True

public export
Show FoodKind where
  show FoodRation = "food ration"

||| The potion set for the M3 slice.  The exact Rogue 5.4.4 table and the
||| per-run colour randomisation are part of the fidelity pass.
||| Rogue 5.4.4's 14 potions.  The constructors are ordered by the
||| authentic generation percentage table, not alphabetically.
public export
data PotionKind
  = PotionConfusion
  | PotionHallucination
  | PotionPoison
  | PotionStrength
  | PotionSeeInvisible
  | PotionHealing
  | PotionDetectMonsters
  | PotionMagicDetection
  | PotionRaiseLevel
  | PotionExtraHealing
  | PotionHasteSelf
  | PotionRestoreStrength
  | PotionBlindness
  | PotionLevitation

public export
Eq PotionKind where
  PotionConfusion == PotionConfusion = True
  PotionHallucination == PotionHallucination = True
  PotionPoison == PotionPoison = True
  PotionStrength == PotionStrength = True
  PotionSeeInvisible == PotionSeeInvisible = True
  PotionHealing == PotionHealing = True
  PotionDetectMonsters == PotionDetectMonsters = True
  PotionMagicDetection == PotionMagicDetection = True
  PotionRaiseLevel == PotionRaiseLevel = True
  PotionExtraHealing == PotionExtraHealing = True
  PotionHasteSelf == PotionHasteSelf = True
  PotionRestoreStrength == PotionRestoreStrength = True
  PotionBlindness == PotionBlindness = True
  PotionLevitation == PotionLevitation = True
  _ == _ = False

public export
potionName : PotionKind -> String
potionName PotionConfusion = "potion of confusion"
potionName PotionHallucination = "potion of hallucination"
potionName PotionPoison = "potion of poison"
potionName PotionStrength = "potion of gain strength"
potionName PotionSeeInvisible = "potion of see invisible"
potionName PotionHealing = "potion of healing"
potionName PotionDetectMonsters = "potion of monster detection"
potionName PotionMagicDetection = "potion of magic detection"
potionName PotionRaiseLevel = "potion of raise level"
potionName PotionExtraHealing = "potion of extra healing"
potionName PotionHasteSelf = "potion of haste self"
potionName PotionRestoreStrength = "potion of restore strength"
potionName PotionBlindness = "potion of blindness"
potionName PotionLevitation = "potion of levitation"

public export
Show PotionKind where
  show = potionName

||| The scroll set.  Effects are resolved by `Core.Game`; names are
||| prefixed to keep them distinct from monster and status constructors.
public export
data ScrollKind
  = ScrollConfuseMonster
  | ScrollMagicMapping
  | ScrollHoldMonster
  | ScrollSleep
  | ScrollEnchantArmor
  | ScrollIdentifyPotion
  | ScrollIdentifyScroll
  | ScrollIdentifyWeapon
  | ScrollIdentifyArmor
  | ScrollIdentifyRingOrWand
  | ScrollScareMonster
  | ScrollFoodDetection
  | ScrollTeleportation
  | ScrollEnchantWeapon
  | ScrollCreateMonster
  | ScrollRemoveCurse
  | ScrollAggravateMonsters
  | ScrollProtectArmor

public export
Eq ScrollKind where
  ScrollConfuseMonster == ScrollConfuseMonster = True
  ScrollMagicMapping == ScrollMagicMapping = True
  ScrollHoldMonster == ScrollHoldMonster = True
  ScrollSleep == ScrollSleep = True
  ScrollEnchantArmor == ScrollEnchantArmor = True
  ScrollIdentifyPotion == ScrollIdentifyPotion = True
  ScrollIdentifyScroll == ScrollIdentifyScroll = True
  ScrollIdentifyWeapon == ScrollIdentifyWeapon = True
  ScrollIdentifyArmor == ScrollIdentifyArmor = True
  ScrollIdentifyRingOrWand == ScrollIdentifyRingOrWand = True
  ScrollScareMonster == ScrollScareMonster = True
  ScrollFoodDetection == ScrollFoodDetection = True
  ScrollTeleportation == ScrollTeleportation = True
  ScrollEnchantWeapon == ScrollEnchantWeapon = True
  ScrollCreateMonster == ScrollCreateMonster = True
  ScrollRemoveCurse == ScrollRemoveCurse = True
  ScrollAggravateMonsters == ScrollAggravateMonsters = True
  ScrollProtectArmor == ScrollProtectArmor = True
  _ == _ = False

public export
scrollName : ScrollKind -> String
scrollName ScrollConfuseMonster = "scroll of confuse monster"
scrollName ScrollMagicMapping = "scroll of magic mapping"
scrollName ScrollHoldMonster = "scroll of hold monster"
scrollName ScrollSleep = "scroll of sleep"
scrollName ScrollEnchantArmor = "scroll of enchant armor"
scrollName ScrollIdentifyPotion = "scroll of identify potion"
scrollName ScrollIdentifyScroll = "scroll of identify scroll"
scrollName ScrollIdentifyWeapon = "scroll of identify weapon"
scrollName ScrollIdentifyArmor = "scroll of identify armor"
scrollName ScrollIdentifyRingOrWand = "scroll of identify ring or wand"
scrollName ScrollScareMonster = "scroll of scare monster"
scrollName ScrollFoodDetection = "scroll of food detection"
scrollName ScrollTeleportation = "scroll of teleportation"
scrollName ScrollEnchantWeapon = "scroll of enchant weapon"
scrollName ScrollCreateMonster = "scroll of create monster"
scrollName ScrollRemoveCurse = "scroll of remove curse"
scrollName ScrollAggravateMonsters = "scroll of aggravate monsters"
scrollName ScrollProtectArmor = "scroll of protect armor"

public export
Show ScrollKind where
  show = scrollName

||| The wand set.  `charges` lives on the item, not on the kind.
public export
data WandKind
  = WandLight
  | WandInvisibility
  | WandLightning
  | WandFire
  | WandCold
  | WandPolymorph
  | WandMagicMissile
  | WandHasteMonster
  | WandSlowMonster
  | WandDrainLife
  | WandNothing
  | WandTeleportAway
  | WandTeleportTo
  | WandCancellation

public export
Eq WandKind where
  WandLight == WandLight = True
  WandInvisibility == WandInvisibility = True
  WandLightning == WandLightning = True
  WandFire == WandFire = True
  WandCold == WandCold = True
  WandPolymorph == WandPolymorph = True
  WandMagicMissile == WandMagicMissile = True
  WandHasteMonster == WandHasteMonster = True
  WandSlowMonster == WandSlowMonster = True
  WandDrainLife == WandDrainLife = True
  WandNothing == WandNothing = True
  WandTeleportAway == WandTeleportAway = True
  WandTeleportTo == WandTeleportTo = True
  WandCancellation == WandCancellation = True
  _ == _ = False

public export
wandName : WandKind -> String
wandName WandLight = "wand of light"
wandName WandInvisibility = "wand of invisibility"
wandName WandLightning = "wand of lightning"
wandName WandFire = "wand of fire"
wandName WandCold = "wand of cold"
wandName WandPolymorph = "wand of polymorph"
wandName WandMagicMissile = "wand of magic missile"
wandName WandHasteMonster = "wand of haste monster"
wandName WandSlowMonster = "wand of slow monster"
wandName WandDrainLife = "wand of drain life"
wandName WandNothing = "wand of nothing"
wandName WandTeleportAway = "wand of teleport away"
wandName WandTeleportTo = "wand of teleport to"
wandName WandCancellation = "wand of cancellation"

public export
Show WandKind where
  show = wandName

||| Rogue 5.4.4's 14 rings.  `RingHunger` and `RingIncreaseAccuracy`
||| were provisional and do not exist in the authentic table; searching
||| and adornment replace them.
public export
data RingKind
  = RingProtection
  | RingAddStrength
  | RingSustainStrength
  | RingSearching
  | RingSeeInvisible
  | RingAdornment
  | RingAggravateMonster
  | RingDexterity
  | RingIncreaseDamage
  | RingRegeneration
  | RingSlowDigestion
  | RingTeleportation
  | RingStealth
  | RingMaintainArmor

public export
Eq RingKind where
  RingProtection == RingProtection = True
  RingAddStrength == RingAddStrength = True
  RingSustainStrength == RingSustainStrength = True
  RingSearching == RingSearching = True
  RingSeeInvisible == RingSeeInvisible = True
  RingAdornment == RingAdornment = True
  RingAggravateMonster == RingAggravateMonster = True
  RingDexterity == RingDexterity = True
  RingIncreaseDamage == RingIncreaseDamage = True
  RingRegeneration == RingRegeneration = True
  RingSlowDigestion == RingSlowDigestion = True
  RingTeleportation == RingTeleportation = True
  RingStealth == RingStealth = True
  RingMaintainArmor == RingMaintainArmor = True
  _ == _ = False

public export
ringName : RingKind -> String
ringName RingProtection = "ring of protection"
ringName RingAddStrength = "ring of add strength"
ringName RingSustainStrength = "ring of sustain strength"
ringName RingSearching = "ring of searching"
ringName RingSeeInvisible = "ring of see invisible"
ringName RingAdornment = "ring of adornment"
ringName RingAggravateMonster = "ring of aggravate monster"
ringName RingDexterity = "ring of dexterity"
ringName RingIncreaseDamage = "ring of increase damage"
ringName RingRegeneration = "ring of regeneration"
ringName RingSlowDigestion = "ring of slow digestion"
ringName RingTeleportation = "ring of teleportation"
ringName RingStealth = "ring of stealth"
ringName RingMaintainArmor = "ring of maintain armor"

public export
Show RingKind where
  show = ringName

||| The authentic 5.4.4 weapon table.  Damage is stored as two dice
||| expressions: equipped melee damage and damage when thrown.  The
||| percentages are the generation weights from the 5.4.4 item table.
public export
data WeaponKind
  = Mace
  | LongSword
  | ShortBow
  | Arrow
  | Dagger
  | TwoHandedSword
  | Dart
  | Shuriken
  | Spear

public export
Eq WeaponKind where
  Mace == Mace = True
  LongSword == LongSword = True
  ShortBow == ShortBow = True
  Arrow == Arrow = True
  Dagger == Dagger = True
  TwoHandedSword == TwoHandedSword = True
  Dart == Dart = True
  Shuriken == Shuriken = True
  Spear == Spear = True
  _ == _ = False

public export
weaponName : WeaponKind -> String
weaponName Mace = "mace"
weaponName LongSword = "long sword"
weaponName ShortBow = "short bow"
weaponName Arrow = "arrow"
weaponName Dagger = "dagger"
weaponName TwoHandedSword = "two-handed sword"
weaponName Dart = "dart"
weaponName Shuriken = "shuriken"
weaponName Spear = "spear"

public export
Show WeaponKind where
  show = weaponName

||| Generation weight out of 100.
public export
weaponWeight : WeaponKind -> Nat
weaponWeight Mace = 11
weaponWeight LongSword = 11
weaponWeight ShortBow = 12
weaponWeight Arrow = 12
weaponWeight Dagger = 8
weaponWeight TwoHandedSword = 10
weaponWeight Dart = 12
weaponWeight Shuriken = 12
weaponWeight Spear = 12

||| Gold value from the 5.4.4 item table.
public export
weaponValue : WeaponKind -> Int32
weaponValue Mace = 8
weaponValue LongSword = 15
weaponValue ShortBow = 15
weaponValue Arrow = 1
weaponValue Dagger = 3
weaponValue TwoHandedSword = 75
weaponValue Dart = 2
weaponValue Shuriken = 5
weaponValue Spear = 5

||| Melee damage when the weapon is wielded.
public export
weaponDamage : WeaponKind -> (Int32, Int32)
weaponDamage Mace = (2, 4)
weaponDamage LongSword = (3, 4)
weaponDamage ShortBow = (1, 1)
weaponDamage Arrow = (1, 1)
weaponDamage Dagger = (1, 6)
weaponDamage TwoHandedSword = (4, 4)
weaponDamage Dart = (1, 1)
weaponDamage Shuriken = (1, 2)
weaponDamage Spear = (2, 3)

||| Thrown damage from the 5.4.4 table.
public export
weaponThrowDamage : WeaponKind -> (Int32, Int32)
weaponThrowDamage Mace = (1, 3)
weaponThrowDamage LongSword = (1, 2)
weaponThrowDamage ShortBow = (1, 1)
weaponThrowDamage Arrow = (2, 3)
weaponThrowDamage Dagger = (1, 4)
weaponThrowDamage TwoHandedSword = (1, 2)
weaponThrowDamage Dart = (1, 3)
weaponThrowDamage Shuriken = (2, 4)
weaponThrowDamage Spear = (1, 6)

||| Ordinary weapons can be generated on any dungeon level; only the
||| Amulet is depth-restricted.
public export
weaponMinDepth : WeaponKind -> Depth
weaponMinDepth _ = 1

||| The authentic 5.4.4 armor table.  `armorValue` is the armor class
||| itself: lower is better, unarmored is 10, and plate mail is 3.
public export
data ArmorKind
  = LeatherArmor
  | RingMail
  | StuddedLeather
  | ScaleMail
  | ChainMail
  | SplintMail
  | BandedMail
  | PlateMail

public export
Eq ArmorKind where
  LeatherArmor == LeatherArmor = True
  RingMail == RingMail = True
  StuddedLeather == StuddedLeather = True
  ScaleMail == ScaleMail = True
  ChainMail == ChainMail = True
  SplintMail == SplintMail = True
  BandedMail == BandedMail = True
  PlateMail == PlateMail = True
  _ == _ = False

public export
armorName : ArmorKind -> String
armorName LeatherArmor = "leather armor"
armorName RingMail = "ring mail"
armorName StuddedLeather = "studded leather armor"
armorName ScaleMail = "scale mail"
armorName ChainMail = "chain mail"
armorName SplintMail = "splint mail"
armorName BandedMail = "banded mail"
armorName PlateMail = "plate mail"

public export
Show ArmorKind where
  show = armorName

||| Generation weight out of 100.
public export
armorWeight : ArmorKind -> Nat
armorWeight LeatherArmor = 20
armorWeight RingMail = 15
armorWeight StuddedLeather = 15
armorWeight ScaleMail = 13
armorWeight ChainMail = 12
armorWeight SplintMail = 10
armorWeight BandedMail = 10
armorWeight PlateMail = 5

||| Gold value from the 5.4.4 item table.
public export
armorGoldValue : ArmorKind -> Int32
armorGoldValue LeatherArmor = 20
armorGoldValue RingMail = 25
armorGoldValue StuddedLeather = 20
armorGoldValue ScaleMail = 30
armorGoldValue ChainMail = 75
armorGoldValue SplintMail = 80
armorGoldValue BandedMail = 90
armorGoldValue PlateMail = 150

||| Armor class: lower is better.  The base player AC is 10.
public export
armorValue : ArmorKind -> Int32
armorValue LeatherArmor = 8
armorValue RingMail = 7
armorValue StuddedLeather = 7
armorValue ScaleMail = 6
armorValue ChainMail = 5
armorValue SplintMail = 4
armorValue BandedMail = 4
armorValue PlateMail = 3

public export
armorMinDepth : ArmorKind -> Depth
armorMinDepth _ = 1

public export
data ItemKind
  = Weapon WeaponKind
  | Armor ArmorKind
  | Food FoodKind
  | Potion PotionKind
  | Scroll ScrollKind
  | Wand WandKind
  | Ring RingKind
  | Gold
  | Amulet

public export
Eq ItemKind where
  Weapon a == Weapon b = a == b
  Armor a == Armor b = a == b
  Food FoodRation == Food FoodRation = True
  Potion a == Potion b = a == b
  Scroll a == Scroll b = a == b
  Wand a == Wand b = a == b
  Ring a == Ring b = a == b
  Gold == Gold = True
  Amulet == Amulet = True
  _ == _ = False

public export
itemName : ItemKind -> String
itemName (Weapon w) = weaponName w
itemName (Armor a) = armorName a
itemName (Food FoodRation) = "food ration"
itemName (Potion p) = potionName p
itemName (Scroll s) = scrollName s
itemName (Wand w) = wandName w
itemName (Ring r) = ringName r
itemName Gold = "gold"
itemName Amulet = "Amulet of Yendor"

public export
Show ItemKind where
  show = itemName

||| The appearance shown before a potion has been identified.  The M3
||| slice uses a fixed colour per potion kind; per-run randomisation is a
||| presentation-fidelity item for M4.
public export
potionAppearance : PotionKind -> String
potionAppearance PotionConfusion = "blue potion"
potionAppearance PotionHallucination = "red potion"
potionAppearance PotionPoison = "green potion"
potionAppearance PotionStrength = "yellow potion"
potionAppearance PotionSeeInvisible = "black potion"
potionAppearance PotionHealing = "purple potion"
potionAppearance PotionDetectMonsters = "white potion"
potionAppearance PotionMagicDetection = "orange potion"
potionAppearance PotionRaiseLevel = "pink potion"
potionAppearance PotionExtraHealing = "cyan potion"
potionAppearance PotionHasteSelf = "silver potion"
potionAppearance PotionRestoreStrength = "golden potion"
potionAppearance PotionBlindness = "brown potion"
potionAppearance PotionLevitation = "clear potion"

public export
scrollAppearance : ScrollKind -> String
scrollAppearance ScrollConfuseMonster = "scroll labeled VELOX NEB"
scrollAppearance ScrollMagicMapping = "scroll labeled KIRJE"
scrollAppearance ScrollHoldMonster = "scroll labeled FOOBIE BLETCH"
scrollAppearance ScrollSleep = "scroll labeled ZELGO MER"
scrollAppearance ScrollEnchantArmor = "scroll labeled GABLEC NOCH"
scrollAppearance ScrollIdentifyPotion = "scroll labeled THARR"
scrollAppearance ScrollIdentifyScroll = "scroll labeled ELBIB YLOH"
scrollAppearance ScrollIdentifyWeapon = "scroll labeled LEP GEX VEN ZEA"
scrollAppearance ScrollIdentifyArmor = "scroll labeled PRIRUTSENIE"
scrollAppearance ScrollIdentifyRingOrWand = "scroll labeled TEMOV"
scrollAppearance ScrollScareMonster = "scroll labeled XIXAXA XOXAXA XUXAXA"
scrollAppearance ScrollFoodDetection = "scroll labeled VERR YED HORRE"
scrollAppearance ScrollTeleportation = "scroll labeled DAI YUK"
scrollAppearance ScrollEnchantWeapon = "scroll labeled PLUGH"
scrollAppearance ScrollCreateMonster = "scroll labeled ANDOVA BEGARIN"
scrollAppearance ScrollRemoveCurse = "scroll labeled KERNOD WEL"
scrollAppearance ScrollAggravateMonsters = "scroll labeled JUYED AWK YACC"
scrollAppearance ScrollProtectArmor = "scroll labeled NR 9"

public export
wandAppearance : WandKind -> String
wandAppearance WandLight = "oak wand"
wandAppearance WandInvisibility = "crystal wand"
wandAppearance WandLightning = "silver wand"
wandAppearance WandFire = "golden wand"
wandAppearance WandCold = "ebony wand"
wandAppearance WandPolymorph = "ivory wand"
wandAppearance WandMagicMissile = "copper wand"
wandAppearance WandHasteMonster = "iron wand"
wandAppearance WandSlowMonster = "maple wand"
wandAppearance WandDrainLife = "willow wand"
wandAppearance WandNothing = "jade wand"
wandAppearance WandTeleportAway = "obsidian wand"
wandAppearance WandTeleportTo = "pearl wand"
wandAppearance WandCancellation = "runed wand"

public export
ringAppearance : RingKind -> String
ringAppearance RingProtection = "ruby ring"
ringAppearance RingAddStrength = "sapphire ring"
ringAppearance RingSustainStrength = "emerald ring"
ringAppearance RingSearching = "topaz ring"
ringAppearance RingSeeInvisible = "wooden ring"
ringAppearance RingAdornment = "iron ring"
ringAppearance RingAggravateMonster = "gold ring"
ringAppearance RingDexterity = "silver ring"
ringAppearance RingIncreaseDamage = "copper ring"
ringAppearance RingRegeneration = "jade ring"
ringAppearance RingSlowDigestion = "pearl ring"
ringAppearance RingTeleportation = "opal ring"
ringAppearance RingStealth = "obsidian ring"
ringAppearance RingMaintainArmor = "crystal ring"

public export
itemAppearance : ItemKind -> String
itemAppearance (Potion p) = potionAppearance p
itemAppearance (Scroll s) = scrollAppearance s
itemAppearance (Wand w) = wandAppearance w
itemAppearance (Ring r) = ringAppearance r
itemAppearance k = itemName k

public export
data ItemLocation
  = OnFloor Depth Coord
  | InPack
  | CarriedBy MonsterId

public export
Eq ItemLocation where
  OnFloor d p == OnFloor d' p' = d == d' && p == p'
  InPack == InPack = True
  CarriedBy a == CarriedBy b = a == b
  _ == _ = False

public export
Show ItemLocation where
  show (OnFloor d p) = "on floor " ++ show d ++ " " ++ show p
  show InPack = "in pack"
  show (CarriedBy m) = "carried by " ++ show m

public export
record Item where
  constructor MkItem
  id : ItemId
  kind : ItemKind
  location : ItemLocation
  count : Int32
  enchant : Int32
  cursed : Bool
  charges : Int32
  protected : Bool

public export
Eq Item where
  a == b = a.id == b.id && a.kind == b.kind
           && a.location == b.location && a.count == b.count
           && a.enchant == b.enchant && a.cursed == b.cursed
           && a.charges == b.charges && a.protected == b.protected

||| A plain item at +0, not cursed, with no charges and unprotected.
||| Spawned equipment and wands override these fields after the RNG has
||| chosen their enchantment, curse state and charges.
public export
newItem : ItemId -> ItemKind -> ItemLocation -> Item
newItem i k loc = MkItem i k loc 1 0 False 0 False

||| The classic Rogue carrying capacity: a-z are display slots, but only
||| 23 items fit in the pack.
public export
maxPack : Nat
maxPack = 23

||| Starting nutrition.  One point is consumed per turn.
public export
startingHunger : Int32
startingHunger = 1300

||| `armor` is the total AC bonus from worn armor.  `weaponDice`,
||| `weaponSides` and `weaponBonus` are the derived attack profile so that
||| `Combat.playerAttack` does not need the whole item list.
public export
record Player where
  constructor MkPlayer
  pos : Coord
  hp, maxHp : Int32
  strength, maxStrength : Int32
  armor : Int32
  level : Int32
  exp : Int32
  gold : Int32
  hunger : Int32
  inventory : List ItemId
  wielded, worn : Maybe ItemId
  leftRing, rightRing : Maybe ItemId
  weaponDice, weaponSides, weaponBonus : Int32
  ringArmor, ringDamage, ringAccuracy, ringStrength : Int32
  statuses : List Status

||| Strength including passive ring bonuses.  The base `strength` field is
||| kept separately so removing a ring never destroys permanent gains.
public export
effectiveStrength : Player -> Int32
effectiveStrength p = p.strength + p.ringStrength

public export
hasStatus : StatusKind -> Player -> Bool
hasStatus k p = any (\s => s.statusKind == k) p.statuses

public export
statusTurns : StatusKind -> Player -> Int32
statusTurns k p =
  case find (\s => s.statusKind == k) p.statuses of
    Just s => s.remaining
    Nothing => 0

||| Unarmed damage.  A wielded weapon replaces this profile.
public export
unarmedDamage : (Int32, Int32)
unarmedDamage = (1, 4)

||| The initial player at `c`: 12 HP, strength 16, unarmored (AC 10) and
||| unarmed.  Rogue 5.4.4's starting 1300 nutrition is one food ration.
public export
initialPlayer : Coord -> Player
initialPlayer c =
  MkPlayer c 12 12 16 16 10 1 0 0 startingHunger [] Nothing Nothing
           Nothing Nothing 1 4 0 0 0 0 0 []

public export
data TrapKind
  = TrapDoor
  | ArrowTrap
  | Sleep
  | Bear
  | Teleport
  | DartTrap
  | Rust
  | Mysterious

public export
Eq TrapKind where
  TrapDoor == TrapDoor = True
  ArrowTrap == ArrowTrap = True
  Sleep == Sleep = True
  Bear == Bear = True
  Teleport == Teleport = True
  DartTrap == DartTrap = True
  Rust == Rust = True
  Mysterious == Mysterious = True
  _ == _ = False

public export
Show TrapKind where
  show TrapDoor = "trapdoor"
  show ArrowTrap = "arrow trap"
  show Sleep = "sleeping gas"
  show Bear = "bear trap"
  show Teleport = "teleport trap"
  show DartTrap = "dart trap"
  show Rust = "rust trap"
  show Mysterious = "mysterious trap"

public export
record Trap where
  constructor MkTrap
  pos : Coord
  kind : TrapKind
  revealed : Bool

public export
Eq Trap where
  a == b = a.pos == b.pos && a.kind == b.kind && a.revealed == b.revealed

public export
record Level where
  constructor MkLevel
  depth : Depth
  tiles : Grid
  explored : Bitset
  rooms : List Room
  monsters : List Monster
  traps : List Trap
  upStairs, downStairs : Maybe Coord

public export
Eq Level where
  a == b = a.depth == b.depth && a.tiles == b.tiles
           && a.explored == b.explored && a.rooms == b.rooms
           && a.monsters == b.monsters && a.traps == b.traps
           && a.upStairs == b.upStairs && a.downStairs == b.downStairs

public export
data MessageKind = CombatMsg | ItemMsg | SystemMsg | WarningMsg | StoryMsg

public export
Eq MessageKind where
  CombatMsg == CombatMsg = True
  ItemMsg == ItemMsg = True
  SystemMsg == SystemMsg = True
  WarningMsg == WarningMsg = True
  StoryMsg == StoryMsg = True
  _ == _ = False

public export
Show MessageKind where
  show CombatMsg = "Combat"
  show ItemMsg = "Item"
  show SystemMsg = "System"
  show WarningMsg = "Warning"
  show StoryMsg = "Story"

public export
record Message where
  constructor MkMessage
  turn : Turn
  kind : MessageKind
  text : String

public export
data DeathCause
  = KilledBy MonsterKind
  | KilledByTrap TrapKind
  | Starved
  | Drained
  | OtherDeath String

public export
Eq DeathCause where
  KilledBy a == KilledBy b = a == b
  KilledByTrap a == KilledByTrap b = a == b
  Starved == Starved = True
  Drained == Drained = True
  OtherDeath a == OtherDeath b = a == b
  _ == _ = False

public export
Show DeathCause where
  show (KilledBy k) = "killed by a " ++ monsterName k
  show (KilledByTrap t) = "killed by a " ++ show t
  show Starved = "starved"
  show Drained = "drained"
  show (OtherDeath s) = s

public export
data GameOver = Dead DeathCause | Won

public export
Eq GameOver where
  Dead a == Dead b = a == b
  Won == Won = True
  _ == _ = False

public export
Show GameOver where
  show (Dead c) = "Dead (" ++ show c ++ ")"
  show Won = "Won"

||| The current game state.  `levels` holds the current level first, then
||| previously visited levels in descent order.  Keeping the current level
||| at the head makes `currentLevel` total and avoids a duplicate field.
public export
record Game where
  constructor MkGame
  seed : Bits64
  rng : Rng
  turn : Turn
  depth : Depth
  player : Player
  levels : List Level
  items : List Item
  nextMonsterId, nextItemId : Bits32
  knownKinds : List ItemKind
  appearances : List (ItemKind, String)
  messages : List Message
  over : Maybe GameOver
  visible : Bitset

||| A fallback used only if the invariant `levels` is non-empty is broken.
public export
emptyLevel : Level
emptyLevel =
  MkLevel 1 (replicate 22 (replicate 80 Rock)) empty [] [] [] Nothing Nothing

public export
currentLevel : Game -> Level
currentLevel g =
  case g.levels of
    (l :: _) => l
    [] => emptyLevel

public export
updateCurrentLevel : (Level -> Level) -> Game -> Game
updateCurrentLevel f g =
  case g.levels of
    (l :: ls) => { levels := f l :: ls } g
    [] => g

||| Is a ring of this kind currently worn in either hand?
public export
hasRing : RingKind -> Game -> Bool
hasRing k g =
  let p = g.player
      holds : Maybe ItemId -> Bool
      holds Nothing = False
      holds (Just iid) =
        case find (\i => i.id == iid) g.items of
          Just i => i.kind == Ring k
          Nothing => False
  in holds p.leftRing || holds p.rightRing

||| See-invisible comes from either the potion/scroll status or a ring.
public export
playerSeesInvisible : Game -> Bool
playerSeesInvisible g =
  hasStatus SeeInvisible g.player || hasRing RingSeeInvisible g

||| A closed integer range, used to build fixed maps and test data.
public export
range : Int32 -> Int32 -> List Int32
range lo hi = if lo > hi then [] else lo :: range (lo + 1) hi
