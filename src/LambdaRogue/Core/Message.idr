||| Typed game messages and their canonical English rendering.
|||
||| Core never chooses a display language.  It builds a `Msg` value, which
||| carries a stable key and stable arguments for the presentation layer,
||| and also renders the canonical English text.  `App.Catalog` turns the
||| key and arguments into another language, falling back to that text for
||| old saves and unknown keys.
|||
||| The English renderer must keep producing the exact strings the game
||| produced before the catalog existed.  Save files therefore stay
||| readable and tests that compare English text stay meaningful.
module LambdaRogue.Core.Message

import Data.List
import LambdaRogue.Core.Types

%default covering

||| How an attack that damaged a monster was introduced in the log.
public export
data AttackLead
  = NoLead
  | WandLightning
  | WandFire
  | WandCold
  | WandMagicMissile
  | DrainLife
  | ThrownItem
  | BreathFire MonsterKind
  | ArrowFire MonsterKind

||| What corroded the player's armour.
public export
data RustSource
  = RustTrap
  | RustMonster MonsterKind

||| One semantic message.  Arguments are typed here; `msgKey` and `msgArgs`
||| give the stable presentation form used by saves and translations.
public export
data Msg
  = TakeDamage Int32
  | Die Bool DeathCause
  | WelcomeLevel Int32
  | ArmorUnaffected RustSource
  | ArmorProtected
  | ArmorWeakens RustSource String
  | KillMonster AttackLead MonsterKind
  | MonsterTakesDamage AttackLead MonsterKind Int32
  | MonsterResists
  | MonsterVanishes MonsterKind
  | MonsterAppears MonsterKind
  | ScrollFizzles
  | MissMonster MonsterKind
  | HitMonster MonsterKind Int32 Bool
  | KillMonsterPlain MonsterKind
  | FoundSecretDoor
  | OpenDoor
  | TriggerTrap TrapKind
  | TeleportFizzles
  | Teleported Coord
  | CannotDescend
  | DescendLevel Int32
  | WinGame
  | CannotReturn
  | AscendLevel Int32
  | WayUpBlocked
  | StrengthHolds
  | FeelWeaker
  | BearTrap
  | FallAsleep
  | FloatOverTrap
  | StrangeNoise
  | FoundTrap TrapKind
  | FoundTrapUnknown
  | SearchNothing
  | HeldInPlace
  | WallThere
  | DoorLocked
  | NotOnStairs StairDir
  | NothingHere
  | PickUpGold Int32
  | PickUpAmulet
  | PickUpItem String
  | PackFull
  | FeelBetter
  | FeelMuchBetter
  | AlreadyStrong
  | FeelStronger
  | StrengthReturns
  | SickStrengthHolds
  | WeakerHeadClears
  | FeelConfused
  | EverythingStrange
  | Blinded
  | SenseMonsters
  | SenseMagic
  | MovingFaster
  | EyesStrange
  | Float
  | MoreExperienced
  | NoSuchItem
  | CannotQuaff
  | QuaffItem String
  | CannotEat
  | EatRation
  | AlreadyWearingRing
  | FingersFull
  | CannotPutOn
  | IdentifyItem String
  | NoUnidentified String
  | HandsGlowRed
  | MapForms
  | MonstersFreeze
  | MonstersSleep
  | MonstersFlee
  | SenseFood
  | NotWearingArmor
  | ArmorGlowsSilver String
  | NotWieldingWeapon
  | WeaponGlowsBlue String
  | SurgeOfRelief
  | GrowlEverywhere
  | ArmorFeelsProtected String
  | CannotRead
  | ReadScroll String
  | BeamFizzles
  | WandFloodsLight
  | FadeOutOfSight
  | MonsterPolymorphs MonsterKind MonsterKind
  | MonsterSpeedsUp MonsterKind
  | MonsterSlowsDown MonsterKind
  | NothingHappens
  | MonsterOrdinary MonsterKind
  | WandSputters
  | ZapWand String
  | CannotZap
  | TakeOffBeforeThrowing
  | ThrowItem String Bool
  | AlreadyWielding
  | WeaponWelded
  | WeaponWeldsToHand String
  | WieldItem String
  | CannotWield
  | RingTightens
  | PutOnRing String
  | AlreadyWearingArmor
  | ArmorTightens String
  | WearArmor String
  | CannotWear
  | CannotRemoveCursedArmor
  | CannotRemoveCursedRing
  | TakeOffItem String
  | NotWearingThat
  | CannotLetGoCursed
  | DropItem String
  | MonsterFindsNoGold MonsterKind
  | MonsterSnatchesGold MonsterKind Int32
  | MonsterFindsNothing MonsterKind
  | MonsterSnatchesItem MonsterKind String
  | MonsterFreezesYou MonsterKind
  | MonsterHoldsYou MonsterKind
  | MonsterDrainsMaxHp MonsterKind Int32
  | MonsterTriesWeaken MonsterKind
  | MonsterWeakensYou MonsterKind
  | MonsterDrainsLifeForce MonsterKind
  | MonsterCorrodesArmor MonsterKind
  | MonsterMisses MonsterKind
  | MonsterHitsYou MonsterKind Int32
  | MonsterOpensDoor MonsterKind
  | MonsterWakesUp MonsterKind
  | RangedMiss AttackLead
  | RangedHit AttackLead Int32
  | RingHums
  | YouAreAsleep
  | YouAreParalyzed
  | StatusExpires StatusKind
  | Hungry
  | WeakFromHunger
  | FaintFromHunger
  | Welcome
  | ResumedFromSave
  | RecoveredFromAutosave

||| The canonical English sentences.  Keep these identical to the strings
||| used before the catalog was introduced.
-- Helpers ------------------------------------------------------------------

dieCap : DeathCause -> String
dieCap (KilledBy k) = "Killed by a " ++ monsterName k
dieCap (KilledByTrap t) = "Killed by a " ++ show t
dieCap Starved = "Starved"
dieCap Drained = "Drained"
dieCap (OtherDeath text) = text

dieEn : Bool -> DeathCause -> String
dieEn False cause = "You die... " ++ show cause ++ "."
dieEn True cause = "You die... " ++ dieCap cause ++ "."

leadText : AttackLead -> String
leadText NoLead = ""
leadText WandLightning = "Lightning arcs through the air!"
leadText WandFire = "A bolt of fire roars out!"
leadText WandMagicMissile = "Magic missiles streak away!"
leadText WandCold = "A cone of cold blasts out!"
leadText DrainLife = "The wand drains life!"
leadText ThrownItem = "The thrown item hits!"
leadText (BreathFire kind) =
  "The " ++ monsterName kind ++ " breathes fire!"
leadText (ArrowFire kind) =
  "The " ++ monsterName kind ++ " fires an arrow!"

leadEn : RustSource -> String
leadEn RustTrap = "The rust trap corrodes your armor."
leadEn (RustMonster kind) =
  "The " ++ monsterName kind ++ " corrodes your armor."

stairEn : StairDir -> String
stairEn Up = "Up"
stairEn Down = "Down"

trapFoundEn : TrapKind -> String
trapFoundEn TrapDoor = "You found a trapdoor."
trapFoundEn ArrowTrap = "You found an arrow trap."
trapFoundEn Sleep = "You found a sleeping gas trap."
trapFoundEn Bear = "You found a bear trap."
trapFoundEn Teleport = "You found a teleport trap."
trapFoundEn DartTrap = "You found a dart trap."
trapFoundEn Rust = "You found a rust trap."
trapFoundEn Mysterious = "You found a mysterious trap."

statusExpiryEn : StatusKind -> String
statusExpiryEn Confused = "You are no longer confused."
statusExpiryEn Blinded = "You can see again."
statusExpiryEn Hasted = "You feel yourself slow down."
statusExpiryEn SeeInvisible = "Your eyes feel normal again."
statusExpiryEn DetectMonsters = "Your senses return to normal."
statusExpiryEn DetectFood = "Your food sense fades."
statusExpiryEn DetectMagic = "Your magic sense fades."
statusExpiryEn Invisible = "You are no longer invisible."
statusExpiryEn Poisoned = "The poison wears off."
statusExpiryEn Held = "You can move again."
statusExpiryEn Slowed = "You feel normal again."
statusExpiryEn Paralyzed = "You can move again."
statusExpiryEn Scared = "You feel brave again."
statusExpiryEn Sleeping = "You wake up."
statusExpiryEn Hallucinating = "Everything looks normal again."
statusExpiryEn Levitated = "You float gently back to the floor."
statusExpiryEn ConfuseNext = "Your hands stop glowing."
statusExpiryEn Mimicking = "Your disguise slips."

leadArg : AttackLead -> String
leadArg NoLead = "none"
leadArg WandLightning = "lightning"
leadArg WandFire = "fire"
leadArg WandCold = "cold"
leadArg WandMagicMissile = "magic-missile"
leadArg DrainLife = "drain"
leadArg ThrownItem = "thrown"
leadArg (BreathFire kind) = "breath:" ++ monsterName kind
leadArg (ArrowFire kind) = "arrow:" ++ monsterName kind

rustArg : RustSource -> String
rustArg RustTrap = "trap"
rustArg (RustMonster kind) = "monster:" ++ monsterName kind

stairArg : StairDir -> String
stairArg Up = "up"
stairArg Down = "down"

causeArg : DeathCause -> String
causeArg (KilledBy kind) = "monster:" ++ monsterName kind
causeArg (KilledByTrap kind) = "trap:" ++ show kind
causeArg Starved = "starved"
causeArg Drained = "drained"
causeArg (OtherDeath text) = "other:" ++ text

public export
msgEn : Msg -> String
msgEn (TakeDamage dmg) = "You take " ++ show dmg ++ " damage."
msgEn (Die cap cause) = dieEn cap cause
msgEn (WelcomeLevel level) = "Welcome to level " ++ show level ++ "!"
msgEn (ArmorUnaffected src) = leadEn src ++ " Your armor is unaffected."
msgEn ArmorProtected = "Your armor is protected from the rust."
msgEn (ArmorWeakens src item) =
  leadEn src ++ " Your " ++ item ++ " weakens."
msgEn (KillMonster lead kind) =
  leadText lead ++ "You kill the " ++ monsterName kind ++ "."
msgEn (MonsterTakesDamage lead kind dmg) =
  leadText lead ++ "The " ++ monsterName kind ++ " takes "
  ++ show dmg ++ " damage."
msgEn MonsterResists = "The monster resists."
msgEn (MonsterVanishes kind) = "The " ++ monsterName kind ++ " vanishes."
msgEn (MonsterAppears kind) = "A " ++ monsterName kind ++ " appears!"
msgEn ScrollFizzles = "The scroll fizzles."
msgEn (MissMonster kind) = "You miss the " ++ monsterName kind ++ "."
msgEn (HitMonster kind dmg confused) =
  "You hit the " ++ monsterName kind ++ " for " ++ show dmg ++ "."
  ++ (if confused then " The " ++ monsterName kind ++ " looks confused." else "")
msgEn (KillMonsterPlain kind) = "You kill the " ++ monsterName kind ++ "."
msgEn FoundSecretDoor = "You found a secret door."
msgEn OpenDoor = "You open the door."
msgEn (TriggerTrap kind) = "You trigger a " ++ show kind ++ "."
msgEn TeleportFizzles = "The teleport trap fizzles."
msgEn (Teleported c) = "You are teleported to " ++ show c ++ "."
msgEn CannotDescend = "You cannot descend further."
msgEn (DescendLevel level) = "You descend to level " ++ show level ++ "."
msgEn WinGame = "You return to the surface with the Amulet of Yendor! You win!"
msgEn CannotReturn = "You cannot return without the Amulet of Yendor."
msgEn (AscendLevel level) = "You ascend to level " ++ show level ++ "."
msgEn WayUpBlocked = "The way up is blocked."
msgEn StrengthHolds = "You feel weak, but your strength holds."
msgEn FeelWeaker = "You feel weaker."
msgEn BearTrap = "The bear trap snaps shut on your leg!"
msgEn FallAsleep = "You fall asleep."
msgEn FloatOverTrap = "You float over a trap."
msgEn StrangeNoise = "You hear a strange noise in the distance."
msgEn (FoundTrap kind) = trapFoundEn kind
msgEn FoundTrapUnknown = "You found a trap."
msgEn SearchNothing = "You search but find nothing."
msgEn HeldInPlace = "You are held in place."
msgEn WallThere = "There is a wall there."
msgEn DoorLocked = "The door is locked."
msgEn (NotOnStairs dir) =
  "You are not standing on " ++ stairEn dir ++ " stairs."
msgEn NothingHere = "There is nothing here to pick up."
msgEn (PickUpGold n) = "You pick up " ++ show n ++ " gold."
msgEn PickUpAmulet = "You pick up the Amulet of Yendor!"
msgEn (PickUpItem name) = "You pick up the " ++ name ++ "."
msgEn PackFull = "Your pack is full."
msgEn FeelBetter = "You feel better."
msgEn FeelMuchBetter = "You feel much better."
msgEn AlreadyStrong = "You feel very strong already."
msgEn FeelStronger = "You feel stronger."
msgEn StrengthReturns = "Your strength returns."
msgEn SickStrengthHolds = "You feel a little sick, but your strength holds."
msgEn WeakerHeadClears = "You feel weaker and your head clears."
msgEn FeelConfused = "You feel confused."
msgEn EverythingStrange = "Oh wow! Everything looks strange."
msgEn Blinded = "You are blinded."
msgEn SenseMonsters = "You sense the presence of monsters."
msgEn SenseMagic = "You sense the presence of magic."
msgEn MovingFaster = "You feel yourself moving faster."
msgEn EyesStrange = "Your eyes feel strange."
msgEn Float = "You float gently into the air."
msgEn MoreExperienced = "You feel more experienced."
msgEn NoSuchItem = "You do not have that item."
msgEn CannotQuaff = "You cannot quaff that."
msgEn (QuaffItem name) = "You quaff the " ++ name ++ "."
msgEn CannotEat = "You cannot eat that."
msgEn EatRation = "You eat the food ration. You feel satisfied."
msgEn AlreadyWearingRing = "You are already wearing that ring."
msgEn FingersFull = "Your fingers are already full."
msgEn CannotPutOn = "You cannot put that on."
msgEn (IdentifyItem name) = "You identify the " ++ name ++ "."
msgEn (NoUnidentified what) =
  "You have no unidentified " ++ what ++ "."
msgEn HandsGlowRed = "Your hands begin to glow red."
msgEn MapForms = "A map of the level forms in your mind."
msgEn MonstersFreeze = "The monsters freeze in place."
msgEn MonstersSleep = "The monsters fall asleep."
msgEn MonstersFlee = "The monsters turn to flee."
msgEn SenseFood = "You sense food nearby."
msgEn NotWearingArmor = "You are not wearing armor."
msgEn (ArmorGlowsSilver name) = "Your " ++ name ++ " glows silver."
msgEn NotWieldingWeapon = "You are not wielding a weapon."
msgEn (WeaponGlowsBlue name) = "Your " ++ name ++ " glows blue."
msgEn SurgeOfRelief = "You feel a surge of relief."
msgEn GrowlEverywhere = "You hear a growl from every direction."
msgEn (ArmorFeelsProtected name) = "Your " ++ name ++ " feels protected."
msgEn CannotRead = "You cannot read that."
msgEn (ReadScroll name) = "You read the " ++ name ++ "."
msgEn BeamFizzles = "The beam fizzles."
msgEn WandFloodsLight = "The wand floods the room with light."
msgEn FadeOutOfSight = "You fade out of sight."
msgEn (MonsterPolymorphs old new) =
  "The " ++ monsterName old ++ " becomes a " ++ monsterName new ++ "!"
msgEn (MonsterSpeedsUp kind) = "The " ++ monsterName kind ++ " speeds up!"
msgEn (MonsterSlowsDown kind) = "The " ++ monsterName kind ++ " slows down."
msgEn NothingHappens = "Nothing happens."
msgEn (MonsterOrdinary kind) =
  "The " ++ monsterName kind ++ " looks ordinary again."
msgEn WandSputters = "The wand sputters."
msgEn (ZapWand name) = "You zap the " ++ name ++ "."
msgEn CannotZap = "You cannot zap that."
msgEn TakeOffBeforeThrowing = "Take it off before throwing it."
msgEn (ThrowItem name shatters) =
  "You throw the " ++ name ++ (if shatters then ". It shatters." else ".")
msgEn AlreadyWielding = "You are already wielding that."
msgEn WeaponWelded = "Your weapon is welded to your hand!"
msgEn (WeaponWeldsToHand name) =
  "You feel the " ++ name ++ " weld itself to your hand!"
msgEn (WieldItem name) = "You wield the " ++ name ++ "."
msgEn CannotWield = "You cannot wield that."
msgEn RingTightens = "The ring tightens around your finger!"
msgEn (PutOnRing name) = "You put on the " ++ name ++ "."
msgEn AlreadyWearingArmor = "You are already wearing that."
msgEn (ArmorTightens name) =
  "You feel the " ++ name ++ " tighten around you!"
msgEn (WearArmor name) = "You wear the " ++ name ++ "."
msgEn CannotWear = "You cannot wear that."
msgEn CannotRemoveCursedArmor = "You cannot remove the cursed armor!"
msgEn CannotRemoveCursedRing = "You cannot remove the cursed ring!"
msgEn (TakeOffItem name) = "You take off the " ++ name ++ "."
msgEn NotWearingThat = "You are not wearing that."
msgEn CannotLetGoCursed = "You cannot let go of the cursed item!"
msgEn (DropItem name) = "You drop the " ++ name ++ "."
msgEn (MonsterFindsNoGold kind) =
  "The " ++ monsterName kind ++ " finds no gold to steal."
msgEn (MonsterSnatchesGold kind n) =
  "The " ++ monsterName kind ++ " snatches " ++ show n
  ++ " gold and vanishes!"
msgEn (MonsterFindsNothing kind) =
  "The " ++ monsterName kind ++ " finds nothing to steal."
msgEn (MonsterSnatchesItem kind name) =
  "The " ++ monsterName kind ++ " snatches your " ++ name
  ++ " and vanishes!"
msgEn (MonsterFreezesYou kind) =
  "The " ++ monsterName kind ++ " freezes you!"
msgEn (MonsterHoldsYou kind) =
  "The " ++ monsterName kind ++ " holds you fast!"
msgEn (MonsterDrainsMaxHp kind n) =
  "The " ++ monsterName kind ++ " drains " ++ show n ++ " maximum HP!"
msgEn (MonsterTriesWeaken kind) =
  "The " ++ monsterName kind ++ " tries to weaken you, but your strength holds."
msgEn (MonsterWeakensYou kind) =
  "The " ++ monsterName kind ++ " weakens you!"
msgEn (MonsterDrainsLifeForce kind) =
  "The " ++ monsterName kind ++ " drains your life force!"
msgEn (MonsterCorrodesArmor kind) =
  "The " ++ monsterName kind ++ " corrodes your armor."
msgEn (MonsterMisses kind) = "The " ++ monsterName kind ++ " misses."
msgEn (MonsterHitsYou kind dmg) =
  "The " ++ monsterName kind ++ " hits you for " ++ show dmg ++ "."
msgEn (MonsterOpensDoor kind) =
  "The " ++ monsterName kind ++ " opens the door."
msgEn (MonsterWakesUp kind) = "The " ++ monsterName kind ++ " wakes up."
msgEn (RangedMiss lead) = leadText lead ++ "You dodge it."
msgEn (RangedHit lead dmg) =
  leadText lead ++ "You take " ++ show dmg ++ " damage."
msgEn RingHums = "The ring hums, and the world shifts."
msgEn YouAreAsleep = "You are asleep."
msgEn YouAreParalyzed = "You are paralyzed."
msgEn (StatusExpires status) = statusExpiryEn status
msgEn Hungry = "You are hungry."
msgEn WeakFromHunger = "You are weak."
msgEn FaintFromHunger = "You faint from lack of food."
msgEn Welcome =
  "Welcome to lambda-rogue. hjkl/yubn move, . wait, , pick up, > descend, i inventory, q quit."
msgEn ResumedFromSave = "Resumed from save."
msgEn RecoveredFromAutosave = "Recovered from autosave."

||| Stable key names.  These are part of the save format and must not
||| change casually.
public export
msgKey : Msg -> String
msgKey (TakeDamage _) = "damage"
msgKey (Die _ _) = "die"
msgKey (WelcomeLevel _) = "welcome-level"
msgKey (ArmorUnaffected _) = "armor-unaffected"
msgKey ArmorProtected = "armor-protected"
msgKey (ArmorWeakens _ _) = "armor-weakens"
msgKey (KillMonster _ _) = "kill-monster"
msgKey (MonsterTakesDamage _ _ _) = "monster-takes-damage"
msgKey MonsterResists = "monster-resists"
msgKey (MonsterVanishes _) = "monster-vanishes"
msgKey (MonsterAppears _) = "monster-appears"
msgKey ScrollFizzles = "scroll-fizzles"
msgKey (MissMonster _) = "miss-monster"
msgKey (HitMonster _ _ _) = "hit-monster"
msgKey (KillMonsterPlain _) = "kill-monster-plain"
msgKey FoundSecretDoor = "found-secret-door"
msgKey OpenDoor = "open-door"
msgKey (TriggerTrap _) = "trigger-trap"
msgKey TeleportFizzles = "teleport-fizzles"
msgKey (Teleported _) = "teleported"
msgKey CannotDescend = "cannot-descend"
msgKey (DescendLevel _) = "descend-level"
msgKey WinGame = "win-game"
msgKey CannotReturn = "cannot-return"
msgKey (AscendLevel _) = "ascend-level"
msgKey WayUpBlocked = "way-up-blocked"
msgKey StrengthHolds = "strength-holds"
msgKey FeelWeaker = "feel-weaker"
msgKey BearTrap = "bear-trap"
msgKey FallAsleep = "fall-asleep"
msgKey FloatOverTrap = "float-over-trap"
msgKey StrangeNoise = "strange-noise"
msgKey (FoundTrap _) = "found-trap"
msgKey FoundTrapUnknown = "found-trap-unknown"
msgKey SearchNothing = "search-nothing"
msgKey HeldInPlace = "held-in-place"
msgKey WallThere = "wall-there"
msgKey DoorLocked = "door-locked"
msgKey (NotOnStairs _) = "not-on-stairs"
msgKey NothingHere = "nothing-here"
msgKey (PickUpGold _) = "pick-up-gold"
msgKey PickUpAmulet = "pick-up-amulet"
msgKey (PickUpItem _) = "pick-up-item"
msgKey PackFull = "pack-full"
msgKey FeelBetter = "feel-better"
msgKey FeelMuchBetter = "feel-much-better"
msgKey AlreadyStrong = "already-strong"
msgKey FeelStronger = "feel-stronger"
msgKey StrengthReturns = "strength-returns"
msgKey SickStrengthHolds = "sick-strength-holds"
msgKey WeakerHeadClears = "weaker-head-clears"
msgKey FeelConfused = "feel-confused"
msgKey EverythingStrange = "everything-strange"
msgKey Blinded = "blinded"
msgKey SenseMonsters = "sense-monsters"
msgKey SenseMagic = "sense-magic"
msgKey MovingFaster = "moving-faster"
msgKey EyesStrange = "eyes-strange"
msgKey Float = "float"
msgKey MoreExperienced = "more-experienced"
msgKey NoSuchItem = "no-such-item"
msgKey CannotQuaff = "cannot-quaff"
msgKey (QuaffItem _) = "quaff-item"
msgKey CannotEat = "cannot-eat"
msgKey EatRation = "eat-ration"
msgKey AlreadyWearingRing = "already-wearing-ring"
msgKey FingersFull = "fingers-full"
msgKey CannotPutOn = "cannot-put-on"
msgKey (IdentifyItem _) = "identify-item"
msgKey (NoUnidentified _) = "no-unidentified"
msgKey HandsGlowRed = "hands-glow-red"
msgKey MapForms = "map-forms"
msgKey MonstersFreeze = "monsters-freeze"
msgKey MonstersSleep = "monsters-sleep"
msgKey MonstersFlee = "monsters-flee"
msgKey SenseFood = "sense-food"
msgKey NotWearingArmor = "not-wearing-armor"
msgKey (ArmorGlowsSilver _) = "armor-glows-silver"
msgKey NotWieldingWeapon = "not-wielding-weapon"
msgKey (WeaponGlowsBlue _) = "weapon-glows-blue"
msgKey SurgeOfRelief = "surge-of-relief"
msgKey GrowlEverywhere = "growl-everywhere"
msgKey (ArmorFeelsProtected _) = "armor-feels-protected"
msgKey CannotRead = "cannot-read"
msgKey (ReadScroll _) = "read-scroll"
msgKey BeamFizzles = "beam-fizzles"
msgKey WandFloodsLight = "wand-floods-light"
msgKey FadeOutOfSight = "fade-out-of-sight"
msgKey (MonsterPolymorphs _ _) = "monster-polymorphs"
msgKey (MonsterSpeedsUp _) = "monster-speeds-up"
msgKey (MonsterSlowsDown _) = "monster-slows-down"
msgKey NothingHappens = "nothing-happens"
msgKey (MonsterOrdinary _) = "monster-ordinary"
msgKey WandSputters = "wand-sputters"
msgKey (ZapWand _) = "zap-wand"
msgKey CannotZap = "cannot-zap"
msgKey TakeOffBeforeThrowing = "take-off-before-throwing"
msgKey (ThrowItem _ _) = "throw-item"
msgKey AlreadyWielding = "already-wielding"
msgKey WeaponWelded = "weapon-welded"
msgKey (WeaponWeldsToHand _) = "weapon-welds-to-hand"
msgKey (WieldItem _) = "wield-item"
msgKey CannotWield = "cannot-wield"
msgKey RingTightens = "ring-tightens"
msgKey (PutOnRing _) = "put-on-ring"
msgKey AlreadyWearingArmor = "already-wearing-armor"
msgKey (ArmorTightens _) = "armor-tightens"
msgKey (WearArmor _) = "wear-armor"
msgKey CannotWear = "cannot-wear"
msgKey CannotRemoveCursedArmor = "cannot-remove-cursed-armor"
msgKey CannotRemoveCursedRing = "cannot-remove-cursed-ring"
msgKey (TakeOffItem _) = "take-off-item"
msgKey NotWearingThat = "not-wearing-that"
msgKey CannotLetGoCursed = "cannot-let-go-cursed"
msgKey (DropItem _) = "drop-item"
msgKey (MonsterFindsNoGold _) = "monster-finds-no-gold"
msgKey (MonsterSnatchesGold _ _) = "monster-snatches-gold"
msgKey (MonsterFindsNothing _) = "monster-finds-nothing"
msgKey (MonsterSnatchesItem _ _) = "monster-snatches-item"
msgKey (MonsterFreezesYou _) = "monster-freezes-you"
msgKey (MonsterHoldsYou _) = "monster-holds-you"
msgKey (MonsterDrainsMaxHp _ _) = "monster-drains-max-hp"
msgKey (MonsterTriesWeaken _) = "monster-tries-weaken"
msgKey (MonsterWeakensYou _) = "monster-weakens-you"
msgKey (MonsterDrainsLifeForce _) = "monster-drains-life-force"
msgKey (MonsterCorrodesArmor _) = "monster-corrodes-armor"
msgKey (MonsterMisses _) = "monster-misses"
msgKey (MonsterHitsYou _ _) = "monster-hits-you"
msgKey (MonsterOpensDoor _) = "monster-opens-door"
msgKey (MonsterWakesUp _) = "monster-wakes-up"
msgKey (RangedMiss _) = "ranged-miss"
msgKey (RangedHit _ _) = "ranged-hit"
msgKey RingHums = "ring-hums"
msgKey YouAreAsleep = "you-are-asleep"
msgKey YouAreParalyzed = "you-are-paralyzed"
msgKey (StatusExpires _) = "status-expires"
msgKey Hungry = "hungry"
msgKey WeakFromHunger = "weak-from-hunger"
msgKey FaintFromHunger = "faint-from-hunger"
msgKey Welcome = "welcome"
msgKey ResumedFromSave = "resumed-from-save"
msgKey RecoveredFromAutosave = "recovered-from-autosave"

||| Stable argument encodings.  The presentation layer decides how to
||| render them; `text:` arguments are already-localised item names.
public export
msgArgs : Msg -> List String
msgArgs (TakeDamage dmg) = [show dmg]
msgArgs (Die cap cause) = [if cap then "cap" else "low", causeArg cause]
msgArgs (WelcomeLevel level) = [show level]
msgArgs (ArmorUnaffected src) = [rustArg src]
msgArgs ArmorProtected = []
msgArgs (ArmorWeakens src item) = [rustArg src, item]
msgArgs (KillMonster lead kind) = [leadArg lead, monsterName kind]
msgArgs (MonsterTakesDamage lead kind dmg) =
  [leadArg lead, monsterName kind, show dmg]
msgArgs MonsterResists = []
msgArgs (MonsterVanishes kind) = [monsterName kind]
msgArgs (MonsterAppears kind) = [monsterName kind]
msgArgs ScrollFizzles = []
msgArgs (MissMonster kind) = [monsterName kind]
msgArgs (HitMonster kind dmg confused) =
  [monsterName kind, show dmg, if confused then "yes" else "no"]
msgArgs (KillMonsterPlain kind) = [monsterName kind]
msgArgs FoundSecretDoor = []
msgArgs OpenDoor = []
msgArgs (TriggerTrap kind) = [show kind]
msgArgs TeleportFizzles = []
msgArgs (Teleported c) = [show c.x, show c.y]
msgArgs CannotDescend = []
msgArgs (DescendLevel level) = [show level]
msgArgs WinGame = []
msgArgs CannotReturn = []
msgArgs (AscendLevel level) = [show level]
msgArgs WayUpBlocked = []
msgArgs StrengthHolds = []
msgArgs FeelWeaker = []
msgArgs BearTrap = []
msgArgs FallAsleep = []
msgArgs FloatOverTrap = []
msgArgs StrangeNoise = []
msgArgs (FoundTrap kind) = [show kind]
msgArgs FoundTrapUnknown = []
msgArgs SearchNothing = []
msgArgs HeldInPlace = []
msgArgs WallThere = []
msgArgs DoorLocked = []
msgArgs (NotOnStairs dir) = [stairArg dir]
msgArgs NothingHere = []
msgArgs (PickUpGold n) = [show n]
msgArgs PickUpAmulet = []
msgArgs (PickUpItem name) = [name]
msgArgs PackFull = []
msgArgs FeelBetter = []
msgArgs FeelMuchBetter = []
msgArgs AlreadyStrong = []
msgArgs FeelStronger = []
msgArgs StrengthReturns = []
msgArgs SickStrengthHolds = []
msgArgs WeakerHeadClears = []
msgArgs FeelConfused = []
msgArgs EverythingStrange = []
msgArgs Blinded = []
msgArgs SenseMonsters = []
msgArgs SenseMagic = []
msgArgs MovingFaster = []
msgArgs EyesStrange = []
msgArgs Float = []
msgArgs MoreExperienced = []
msgArgs NoSuchItem = []
msgArgs CannotQuaff = []
msgArgs (QuaffItem name) = [name]
msgArgs CannotEat = []
msgArgs EatRation = []
msgArgs AlreadyWearingRing = []
msgArgs FingersFull = []
msgArgs CannotPutOn = []
msgArgs (IdentifyItem name) = [name]
msgArgs (NoUnidentified what) = [what]
msgArgs HandsGlowRed = []
msgArgs MapForms = []
msgArgs MonstersFreeze = []
msgArgs MonstersSleep = []
msgArgs MonstersFlee = []
msgArgs SenseFood = []
msgArgs NotWearingArmor = []
msgArgs (ArmorGlowsSilver name) = [name]
msgArgs NotWieldingWeapon = []
msgArgs (WeaponGlowsBlue name) = [name]
msgArgs SurgeOfRelief = []
msgArgs GrowlEverywhere = []
msgArgs (ArmorFeelsProtected name) = [name]
msgArgs CannotRead = []
msgArgs (ReadScroll name) = [name]
msgArgs BeamFizzles = []
msgArgs WandFloodsLight = []
msgArgs FadeOutOfSight = []
msgArgs (MonsterPolymorphs old new) = [monsterName old, monsterName new]
msgArgs (MonsterSpeedsUp kind) = [monsterName kind]
msgArgs (MonsterSlowsDown kind) = [monsterName kind]
msgArgs NothingHappens = []
msgArgs (MonsterOrdinary kind) = [monsterName kind]
msgArgs WandSputters = []
msgArgs (ZapWand name) = [name]
msgArgs CannotZap = []
msgArgs TakeOffBeforeThrowing = []
msgArgs (ThrowItem name shatters) = [name, if shatters then "yes" else "no"]
msgArgs AlreadyWielding = []
msgArgs WeaponWelded = []
msgArgs (WeaponWeldsToHand name) = [name]
msgArgs (WieldItem name) = [name]
msgArgs CannotWield = []
msgArgs RingTightens = []
msgArgs (PutOnRing name) = [name]
msgArgs AlreadyWearingArmor = []
msgArgs (ArmorTightens name) = [name]
msgArgs (WearArmor name) = [name]
msgArgs CannotWear = []
msgArgs CannotRemoveCursedArmor = []
msgArgs CannotRemoveCursedRing = []
msgArgs (TakeOffItem name) = [name]
msgArgs NotWearingThat = []
msgArgs CannotLetGoCursed = []
msgArgs (DropItem name) = [name]
msgArgs (MonsterFindsNoGold kind) = [monsterName kind]
msgArgs (MonsterSnatchesGold kind n) = [monsterName kind, show n]
msgArgs (MonsterFindsNothing kind) = [monsterName kind]
msgArgs (MonsterSnatchesItem kind name) = [monsterName kind, name]
msgArgs (MonsterFreezesYou kind) = [monsterName kind]
msgArgs (MonsterHoldsYou kind) = [monsterName kind]
msgArgs (MonsterDrainsMaxHp kind n) = [monsterName kind, show n]
msgArgs (MonsterTriesWeaken kind) = [monsterName kind]
msgArgs (MonsterWeakensYou kind) = [monsterName kind]
msgArgs (MonsterDrainsLifeForce kind) = [monsterName kind]
msgArgs (MonsterCorrodesArmor kind) = [monsterName kind]
msgArgs (MonsterMisses kind) = [monsterName kind]
msgArgs (MonsterHitsYou kind dmg) = [monsterName kind, show dmg]
msgArgs (MonsterOpensDoor kind) = [monsterName kind]
msgArgs (MonsterWakesUp kind) = [monsterName kind]
msgArgs (RangedMiss lead) = [leadArg lead]
msgArgs (RangedHit lead dmg) = [leadArg lead, show dmg]
msgArgs RingHums = []
msgArgs YouAreAsleep = []
msgArgs YouAreParalyzed = []
msgArgs (StatusExpires status) = [show status]
msgArgs Hungry = []
msgArgs WeakFromHunger = []
msgArgs FaintFromHunger = []
msgArgs Welcome = []
msgArgs ResumedFromSave = []
msgArgs RecoveredFromAutosave = []

||| Build the message stored in the game log.  `text` stays the canonical
||| English sentence so old saves and unknown keys have a safe fallback.
public export
mkMessage : Turn -> MessageKind -> Msg -> Message
mkMessage turn kind msg =
  MkMessage turn kind (msgKey msg) (msgArgs msg) (msgEn msg)

||| A message that predates the catalog, or a test fixture.  It has no
||| key, so the UI always shows `text`.
public export
legacyMessage : Turn -> MessageKind -> String -> Message
legacyMessage turn kind text = MkMessage turn kind "" [] text

||| Representative values for every constructor.  Used by the catalog
||| completeness tests and by documentation examples.
public export
sampleMessages : List Msg
sampleMessages =
  [ TakeDamage 3
  , Die True (KilledBy Orc)
  , WelcomeLevel 4
  , ArmorUnaffected RustTrap
  , ArmorProtected
  , ArmorWeakens (RustMonster Aquator) "leather armor"
  , KillMonster WandFire Orc
  , MonsterTakesDamage ThrownItem Orc 5
  , MonsterResists
  , MonsterVanishes Orc
  , MonsterAppears Orc
  , ScrollFizzles
  , MissMonster Orc
  , HitMonster Orc 4 True
  , KillMonsterPlain Orc
  , FoundSecretDoor
  , OpenDoor
  , TriggerTrap Bear
  , TeleportFizzles
  , Teleported (MkCoord 3 4)
  , CannotDescend
  , DescendLevel 2
  , WinGame
  , CannotReturn
  , AscendLevel 1
  , WayUpBlocked
  , StrengthHolds
  , FeelWeaker
  , BearTrap
  , FallAsleep
  , FloatOverTrap
  , StrangeNoise
  , FoundTrap Bear
  , FoundTrapUnknown
  , SearchNothing
  , HeldInPlace
  , WallThere
  , DoorLocked
  , NotOnStairs Up
  , NothingHere
  , PickUpGold 12
  , PickUpAmulet
  , PickUpItem "food ration"
  , PackFull
  , FeelBetter
  , FeelMuchBetter
  , AlreadyStrong
  , FeelStronger
  , StrengthReturns
  , SickStrengthHolds
  , WeakerHeadClears
  , FeelConfused
  , EverythingStrange
  , Blinded
  , SenseMonsters
  , SenseMagic
  , MovingFaster
  , EyesStrange
  , Float
  , MoreExperienced
  , NoSuchItem
  , CannotQuaff
  , QuaffItem "potion of healing"
  , CannotEat
  , EatRation
  , AlreadyWearingRing
  , FingersFull
  , CannotPutOn
  , IdentifyItem "potion of healing"
  , NoUnidentified "potions"
  , HandsGlowRed
  , MapForms
  , MonstersFreeze
  , MonstersSleep
  , MonstersFlee
  , SenseFood
  , NotWearingArmor
  , ArmorGlowsSilver "leather armor"
  , NotWieldingWeapon
  , WeaponGlowsBlue "mace"
  , SurgeOfRelief
  , GrowlEverywhere
  , ArmorFeelsProtected "leather armor"
  , CannotRead
  , ReadScroll "scroll of magic mapping"
  , BeamFizzles
  , WandFloodsLight
  , FadeOutOfSight
  , MonsterPolymorphs Orc Dragon
  , MonsterSpeedsUp Orc
  , MonsterSlowsDown Orc
  , NothingHappens
  , MonsterOrdinary Orc
  , WandSputters
  , ZapWand "wand of fire"
  , CannotZap
  , TakeOffBeforeThrowing
  , ThrowItem "dagger" True
  , AlreadyWielding
  , WeaponWelded
  , WeaponWeldsToHand "dagger"
  , WieldItem "mace"
  , CannotWield
  , RingTightens
  , PutOnRing "ring of protection"
  , AlreadyWearingArmor
  , ArmorTightens "leather armor"
  , WearArmor "leather armor"
  , CannotWear
  , CannotRemoveCursedArmor
  , CannotRemoveCursedRing
  , TakeOffItem "leather armor"
  , NotWearingThat
  , CannotLetGoCursed
  , DropItem "dagger"
  , MonsterFindsNoGold Orc
  , MonsterSnatchesGold Orc 10
  , MonsterFindsNothing Orc
  , MonsterSnatchesItem Orc "dagger"
  , MonsterFreezesYou Orc
  , MonsterHoldsYou Orc
  , MonsterDrainsMaxHp Orc 2
  , MonsterTriesWeaken Orc
  , MonsterWeakensYou Orc
  , MonsterDrainsLifeForce Orc
  , MonsterCorrodesArmor Orc
  , MonsterMisses Orc
  , MonsterHitsYou Orc 4
  , MonsterOpensDoor Orc
  , MonsterWakesUp Orc
  , RangedMiss (ArrowFire Orc)
  , RangedHit (BreathFire Dragon) 12
  , RingHums
  , YouAreAsleep
  , YouAreParalyzed
  , StatusExpires Confused
  , Hungry
  , WeakFromHunger
  , FaintFromHunger
  , Welcome
  , ResumedFromSave
  , RecoveredFromAutosave
  ]
