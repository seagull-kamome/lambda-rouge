||| Stable JSON codecs for the small Core types shared by every persistence
||| format: coordinates, statuses, names, tiles and game results.
|||
||| Enum values are written as their stable display names, never as their
||| constructor index.  Reordering a Core enum therefore cannot silently
||| reinterpret an old save file.
module LambdaRogue.Persist.Codec

import Data.Bits
import Data.List
import Data.Maybe
import Language.JSON
import LambdaRogue.Core.Types
import LambdaRogue.Persist.Json

%default covering

public export
jsonInt : Int32 -> JSON
jsonInt n = JNumber (cast n)

public export
jsonBits32 : Bits32 -> JSON
jsonBits32 n = JNumber (cast n)

public export
coordToJSON : Coord -> JSON
coordToJSON c = JObject [("x", jsonInt c.x), ("y", jsonInt c.y)]

public export
coordFromJSON : JSON -> Maybe Coord
coordFromJSON j = do
  x <- field "x" j >>= asInt32
  y <- field "y" j >>= asInt32
  pure (MkCoord x y)

public export
dirText : Dir -> String
dirText = show

public export
dirFromText : String -> Maybe Dir
dirFromText "N" = Just N
dirFromText "NE" = Just NE
dirFromText "E" = Just E
dirFromText "SE" = Just SE
dirFromText "S" = Just S
dirFromText "SW" = Just SW
dirFromText "W" = Just W
dirFromText "NW" = Just NW
dirFromText _ = Nothing

public export
statusKindText : StatusKind -> String
statusKindText = show

public export
statusKindFromText : String -> Maybe StatusKind
statusKindFromText s =
  find (\k => statusKindText k == s)
       [ Confused, Blinded, Hasted, SeeInvisible, DetectMonsters
       , DetectFood, DetectMagic, Invisible, Poisoned, Held, Slowed
       , Paralyzed, Scared, Sleeping, Hallucinating, Levitated
       , ConfuseNext, Mimicking, Fainted
       ]

public export
statusToJSON : Status -> JSON
statusToJSON s =
  JObject
    [ ("kind", JString (statusKindText s.statusKind))
    , ("remaining", jsonInt s.remaining)
    ]

public export
statusFromJSON : JSON -> Maybe Status
statusFromJSON j = do
  kind <- field "kind" j >>= asString >>= statusKindFromText
  remaining <- field "remaining" j >>= asInt32
  pure (MkStatus kind remaining)

public export
statusesToJSON : List Status -> JSON
statusesToJSON = JArray . map statusToJSON

public export
statusesFromJSON : JSON -> Maybe (List Status)
statusesFromJSON = arrayOf statusFromJSON

public export
monsterStateText : MonsterState -> String
monsterStateText Asleep = "asleep"
monsterStateText Awake = "awake"
monsterStateText Chasing = "chasing"
monsterStateText Fleeing = "fleeing"

public export
monsterStateFromText : String -> Maybe MonsterState
monsterStateFromText "asleep" = Just Asleep
monsterStateFromText "awake" = Just Awake
monsterStateFromText "chasing" = Just Chasing
monsterStateFromText "fleeing" = Just Fleeing
monsterStateFromText _ = Nothing

public export
monsterKindText : MonsterKind -> String
monsterKindText = monsterName

public export
monsterKindFromText : String -> Maybe MonsterKind
monsterKindFromText s =
  find (\k => monsterKindText k == s)
       [ Aquator, Bat, Centaur, Dragon, Emu, VenusFlytrap, Griffin
       , Hobgoblin, IceMonster, Jabberwock, Kestrel, Leprechaun, Medusa
       , Nymph, Orc, Phantom, Quagga, Rattlesnake, Snake, Troll
       , BlackUnicorn, Vampire, Wraith, Xeroc, Yeti, Zombie
       ]

export
allWeaponKinds : List WeaponKind
allWeaponKinds = [Mace, LongSword, ShortBow, Arrow, Dagger, TwoHandedSword, Dart, Shuriken, Spear]

export
allArmorKinds : List ArmorKind
allArmorKinds = [LeatherArmor, RingMail, StuddedLeather, ScaleMail, ChainMail, SplintMail, BandedMail, PlateMail]

export
allPotionKinds : List PotionKind
allPotionKinds =
  [ PotionConfusion, PotionHallucination, PotionPoison, PotionStrength
  , PotionSeeInvisible, PotionHealing, PotionDetectMonsters
  , PotionMagicDetection, PotionRaiseLevel, PotionExtraHealing
  , PotionHasteSelf, PotionRestoreStrength, PotionBlindness, PotionLevitation
  ]

export
allScrollKinds : List ScrollKind
allScrollKinds =
  [ ScrollConfuseMonster, ScrollMagicMapping, ScrollHoldMonster, ScrollSleep
  , ScrollEnchantArmor, ScrollIdentifyPotion, ScrollIdentifyScroll
  , ScrollIdentifyWeapon, ScrollIdentifyArmor, ScrollIdentifyRingOrWand
  , ScrollScareMonster, ScrollFoodDetection, ScrollTeleportation
  , ScrollEnchantWeapon, ScrollCreateMonster, ScrollRemoveCurse
  , ScrollAggravateMonsters, ScrollProtectArmor
  ]

export
allWandKinds : List WandKind
allWandKinds =
  [ WandLight, WandInvisibility, WandLightning, WandFire, WandCold
  , WandPolymorph, WandMagicMissile, WandHasteMonster, WandSlowMonster
  , WandDrainLife, WandNothing, WandTeleportAway, WandTeleportTo
  , WandCancellation
  ]

export
allRingKinds : List RingKind
allRingKinds =
  [ RingProtection, RingAddStrength, RingSustainStrength, RingSearching
  , RingSeeInvisible, RingAdornment, RingAggravateMonster, RingDexterity
  , RingIncreaseDamage, RingRegeneration, RingSlowDigestion
  , RingTeleportation, RingStealth, RingMaintainArmor
  ]

public export
allItemKinds : List ItemKind
allItemKinds =
  map Weapon allWeaponKinds
  ++ map Armor allArmorKinds
  ++ [Food FoodRation]
  ++ map Potion allPotionKinds
  ++ map Scroll allScrollKinds
  ++ map Wand allWandKinds
  ++ map Ring allRingKinds
  ++ [Gold, Amulet]

public export
itemKindText : ItemKind -> String
itemKindText = itemName

public export
itemKindFromText : String -> Maybe ItemKind
itemKindFromText s = find (\k => itemKindText k == s) allItemKinds

public export
trapKindText : TrapKind -> String
trapKindText TrapDoor = "trapdoor"
trapKindText ArrowTrap = "arrow"
trapKindText Sleep = "sleep"
trapKindText Bear = "bear"
trapKindText Teleport = "teleport"
trapKindText DartTrap = "dart"
trapKindText Rust = "rust"
trapKindText Mysterious = "mysterious"

public export
trapKindFromText : String -> Maybe TrapKind
trapKindFromText "trapdoor" = Just TrapDoor
trapKindFromText "arrow" = Just ArrowTrap
trapKindFromText "sleep" = Just Sleep
trapKindFromText "bear" = Just Bear
trapKindFromText "teleport" = Just Teleport
trapKindFromText "dart" = Just DartTrap
trapKindFromText "rust" = Just Rust
trapKindFromText "mysterious" = Just Mysterious
trapKindFromText _ = Nothing

public export
messageKindText : MessageKind -> String
messageKindText CombatMsg = "combat"
messageKindText ItemMsg = "item"
messageKindText SystemMsg = "system"
messageKindText WarningMsg = "warning"
messageKindText StoryMsg = "story"

public export
messageKindFromText : String -> Maybe MessageKind
messageKindFromText "combat" = Just CombatMsg
messageKindFromText "item" = Just ItemMsg
messageKindFromText "system" = Just SystemMsg
messageKindFromText "warning" = Just WarningMsg
messageKindFromText "story" = Just StoryMsg
messageKindFromText _ = Nothing

public export
tileText : Tile -> Char
tileText Rock = '#'
tileText Floor = '.'
tileText Corridor = ':'
tileText (Door Closed) = '+'
tileText (Door Open) = '\''
tileText (Door Secret) = 's'
tileText (Door Locked) = 'l'
tileText (Stairs Up) = '<'
tileText (Stairs Down) = '>'

public export
tileFromText : Char -> Maybe Tile
tileFromText '#' = Just Rock
tileFromText '.' = Just Floor
tileFromText ':' = Just Corridor
tileFromText '+' = Just (Door Closed)
tileFromText '\'' = Just (Door Open)
tileFromText 's' = Just (Door Secret)
tileFromText 'l' = Just (Door Locked)
tileFromText '<' = Just (Stairs Up)
tileFromText '>' = Just (Stairs Down)
tileFromText _ = Nothing

public export
deathCauseToJSON : DeathCause -> JSON
deathCauseToJSON (KilledBy k) =
  JObject [("kind", JString "monster"),
           ("monster", JString (monsterKindText k))]
deathCauseToJSON (KilledByTrap t) =
  JObject [("kind", JString "trap"),
           ("trap", JString (trapKindText t))]
deathCauseToJSON Starved =
  JObject [("kind", JString "starved")]
deathCauseToJSON Drained =
  JObject [("kind", JString "drained")]
deathCauseToJSON (OtherDeath text) =
  JObject [("kind", JString "other"), ("text", JString text)]

public export
deathCauseFromJSON : JSON -> Maybe DeathCause
deathCauseFromJSON j = do
  kind <- field "kind" j >>= asString
  case kind of
    "monster" => KilledBy <$> (field "monster" j >>= asString
                                             >>= monsterKindFromText)
    "trap" => KilledByTrap <$> (field "trap" j >>= asString
                                              >>= trapKindFromText)
    "starved" => Just Starved
    "drained" => Just Drained
    "other" => OtherDeath <$> (field "text" j >>= asString)
    _ => Nothing

public export
gameOverToJSON : GameOver -> JSON
gameOverToJSON Won = JObject [("result", JString "won")]
gameOverToJSON (Dead cause) =
  JObject [("result", JString "dead"),
           ("cause", deathCauseToJSON cause)]

public export
gameOverFromJSON : JSON -> Maybe GameOver
gameOverFromJSON j = do
  result <- field "result" j >>= asString
  case result of
    "won" => Just Won
    "dead" => Dead <$> (field "cause" j >>= deathCauseFromJSON)
    _ => Nothing
