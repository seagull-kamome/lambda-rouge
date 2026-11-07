||| Monster data and spawning.
|||
||| The roster, experience values, levels, armor classes, damage dice,
||| spawn bands and special abilities are the Rogue 5.4.4 values from the
||| public 5.4.4 monster sheet.  Hit points are `level`d8, the classic
||| Rogue rule; the sheet lists the level rather than explicit HP dice.
module LambdaRogue.Core.Monster

import Data.List
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types

%default covering

public export
data MonsterAbility
  = HoldingAttack
  | Freeze
  | FireBreath
  | DrainLife
  | DrainStrength
  | DrainExperience
  | RustArmor
  | StealGold
  | StealItem
  | Regenerate
  | Invisible
  | Erratic
  | Immobile
  | Fast
  | Greedy
  | UsuallyAsleep
  | MimicObject

public export
Eq MonsterAbility where
  HoldingAttack == HoldingAttack = True
  Freeze == Freeze = True
  FireBreath == FireBreath = True
  DrainLife == DrainLife = True
  DrainStrength == DrainStrength = True
  DrainExperience == DrainExperience = True
  RustArmor == RustArmor = True
  StealGold == StealGold = True
  StealItem == StealItem = True
  Regenerate == Regenerate = True
  Invisible == Invisible = True
  Erratic == Erratic = True
  Immobile == Immobile = True
  Fast == Fast = True
  Greedy == Greedy = True
  UsuallyAsleep == UsuallyAsleep = True
  MimicObject == MimicObject = True
  _ == _ = False

public export
Show MonsterAbility where
  show HoldingAttack = "holding attack"
  show Freeze = "freeze"
  show FireBreath = "fire breath"
  show DrainLife = "drain life"
  show DrainStrength = "drain strength"
  show DrainExperience = "drain experience"
  show RustArmor = "rust armor"
  show StealGold = "steal gold"
  show StealItem = "steal item"
  show Regenerate = "regenerate"
  show Invisible = "invisible"
  show Erratic = "erratic"
  show Immobile = "immobile"
  show Fast = "fast"
  show Greedy = "greedy"
  show UsuallyAsleep = "usually asleep"
  show MimicObject = "mimics objects"

public export
record MonsterSpec where
  constructor MkMonsterSpec
  glyph : Char
  name : String
  level : Int32
  attacks : List (Int32, Int32)
  ac : Int32
  exp : Int32
  minDepth, maxDepth : Depth
  abilities : List MonsterAbility

public export
noAttack : List (Int32, Int32)
noAttack = []

||| The authentic Rogue 5.4.4 monster table.  Spawn bands are inclusive.
public export
monsterSpec : MonsterKind -> MonsterSpec
monsterSpec Aquator =
  MkMonsterSpec 'A' "aquator" 5 [(0, 0), (0, 0)] 2 20 9 18 [RustArmor]
monsterSpec Bat =
  MkMonsterSpec 'B' "bat" 1 [(1, 2)] 3 1 1 8 [Erratic, Fast]
monsterSpec Centaur =
  MkMonsterSpec 'C' "centaur" 4 [(1, 2), (1, 5), (1, 5)] 4 17 7 16 []
monsterSpec Dragon =
  MkMonsterSpec 'D' "dragon" 10 [(1, 8), (1, 8), (3, 10)] (-1) 5000 22 26
    [FireBreath]
monsterSpec Emu =
  MkMonsterSpec 'E' "emu" 1 [(1, 2)] 7 2 1 7 []
monsterSpec VenusFlytrap =
  MkMonsterSpec 'F' "venus flytrap" 8 [(0, 0)] 3 80 12 21
    [HoldingAttack, Immobile]
monsterSpec Griffin =
  MkMonsterSpec 'G' "griffin" 13 [(4, 3), (3, 5)] 2 2000 20 26
    [Regenerate, Fast]
monsterSpec Hobgoblin =
  MkMonsterSpec 'H' "hobgoblin" 1 [(1, 8)] 5 3 1 10 []
monsterSpec IceMonster =
  MkMonsterSpec 'I' "ice monster" 1 [(0, 0)] 9 5 2 11
    [Freeze, UsuallyAsleep]
monsterSpec Jabberwock =
  MkMonsterSpec 'J' "jabberwock" 15 [(2, 12), (2, 4)] 6 3000 21 26 []
monsterSpec Kestrel =
  MkMonsterSpec 'K' "kestrel" 1 [(1, 4)] 7 1 1 6 [Fast]
monsterSpec Leprechaun =
  MkMonsterSpec 'L' "leprechaun" 3 [(1, 1)] 8 10 6 15
    [StealGold, UsuallyAsleep]
monsterSpec Medusa =
  MkMonsterSpec 'M' "medusa" 8 [(3, 4), (3, 4), (2, 5)] 2 200 18 26 []
monsterSpec Nymph =
  MkMonsterSpec 'N' "nymph" 3 [(0, 0)] 9 37 10 19
    [StealItem, UsuallyAsleep]
monsterSpec Orc =
  MkMonsterSpec 'O' "orc" 1 [(1, 8)] 6 5 4 13 [Greedy]
monsterSpec Phantom =
  MkMonsterSpec 'P' "phantom" 8 [(4, 4)] 3 120 15 24
    [Invisible, Erratic]
monsterSpec Quagga =
  MkMonsterSpec 'Q' "quagga" 3 [(1, 5), (1, 5)] 3 15 8 17 []
monsterSpec Rattlesnake =
  MkMonsterSpec 'R' "rattlesnake" 2 [(1, 6)] 3 9 3 12 [DrainStrength]
monsterSpec Snake =
  MkMonsterSpec 'S' "snake" 1 [(1, 3)] 5 2 1 9 []
monsterSpec Troll =
  MkMonsterSpec 'T' "troll" 6 [(1, 8), (1, 8), (2, 6)] 4 120 13 22
    [Regenerate]
monsterSpec BlackUnicorn =
  MkMonsterSpec 'U' "black unicorn" 7 [(1, 9), (1, 9), (2, 9)] (-2) 190 17 26
    []
monsterSpec Vampire =
  MkMonsterSpec 'V' "vampire" 8 [(1, 10)] 1 350 19 26
    [DrainLife, Regenerate]
monsterSpec Wraith =
  MkMonsterSpec 'W' "wraith" 5 [(1, 6)] 4 55 14 23 [DrainExperience]
monsterSpec Xeroc =
  MkMonsterSpec 'X' "xeroc" 7 [(4, 4)] 7 100 16 25 [MimicObject]
monsterSpec Yeti =
  MkMonsterSpec 'Y' "yeti" 4 [(1, 6), (1, 6)] 6 50 11 20 []
monsterSpec Zombie =
  MkMonsterSpec 'Z' "zombie" 2 [(1, 8)] 8 6 5 14 []

public export
hasAbility : MonsterAbility -> MonsterKind -> Bool
hasAbility a k = elem a (monsterSpec k).abilities

||| Monster order used by the 5.4.4 spawn bands: weakest first.  The
||| threshold-shaped bands are the depths at which a kind appears.
public export
monsterOrder : List MonsterKind
monsterOrder =
  [Kestrel, Emu, Bat, Snake, Hobgoblin, IceMonster, Rattlesnake, Orc,
   Zombie, Leprechaun, Centaur, Quagga, Aquator, Nymph, Yeti, VenusFlytrap,
   Troll, Wraith, Phantom, Xeroc, BlackUnicorn, Medusa, Vampire, Griffin,
   Jabberwock, Dragon]

public export
allMonsterKinds : List MonsterKind
allMonsterKinds =
  [Aquator, Bat, Centaur, Dragon, Emu, VenusFlytrap, Griffin, Hobgoblin,
   IceMonster, Jabberwock, Kestrel, Leprechaun, Medusa, Nymph, Orc,
   Phantom, Quagga, Rattlesnake, Snake, Troll, BlackUnicorn, Vampire,
   Wraith, Xeroc, Yeti, Zombie]

eligible : Depth -> MonsterKind -> Bool
eligible d k =
  let s = monsterSpec k
  in s.minDepth <= d && d <= s.maxDepth

||| Every eligible kind has the same chance.  The 5.4.4 bands already
||| encode the difficulty progression; the old proximity weighting was a
||| provisional M4 rule and does not appear in the authentic table.
public export
spawnPool : Depth -> List MonsterKind
spawnPool d =
  let pool = filter (eligible d) monsterOrder
  in if null pool then [Kestrel] else pool

||| The number of monsters on a level.  Density is not part of the
||| published 5.4.4 stat table; this remains a conservative M4 value that
||| keeps the 80x22 map readable.
public export
monsterCount : Depth -> Nat
monsterCount d = cast (min 12 (2 + d `div` 2))

||| HP is `level`d8 for every monster.
public export
rollMonsterHp : MonsterSpec -> Rng -> (Int32, Rng)
rollMonsterHp spec = roll spec.level 8

||| Experience from killing a monster.  Rogue 5.4.4 adds a hit-point bonus
||| of 1/6 HP (1/8 for level-1 kinds), multiplied by 4 above six hit dice
||| and by 20 at ten or more.
public export
monsterExpGain : MonsterSpec -> Int32 -> Int32
monsterExpGain spec hp =
  let divisor = if spec.level == 1 then 8 else 6
      multiplier = if spec.level >= 10 then 20
                   else if spec.level > 6 then 4
                   else 1
  in spec.exp + (hp `div` divisor) * multiplier

||| Spawn monsters on the given candidate cells.  Cells are removed as they
||| are used, so two monsters never share a position.  IDs are allocated in
||| spawn order.  Ice monsters, leprechauns and nymphs are usually asleep.
public export
spawnMonsters : Depth -> List Coord -> MonsterId -> Rng
             -> (List Monster, MonsterId, Rng)
spawnMonsters depth candidates nextId g0 =
  go (monsterCount depth) candidates nextId g0 []
  where
    go : Nat -> List Coord -> MonsterId -> Rng -> List Monster
      -> (List Monster, MonsterId, Rng)
    go Z _ nextId g acc = (reverse acc, nextId, g)
    go (S k) [] nextId g acc = (reverse acc, nextId, g)
    go (S k) cs nextId g acc =
      let (kindOpt, g1) = pick (spawnPool depth) g
          (coordOpt, g2) = pick cs g1
      in case (kindOpt, coordOpt) of
           (Just kind, Just c) =>
             let spec = monsterSpec kind
                 (hp, g3) = rollMonsterHp spec g2
                 sleepChance = if hasAbility UsuallyAsleep kind then 92 else 80
                 (asleep, g4) = chance sleepChance g3
                 state : MonsterState
                 state = if asleep then Asleep else Awake
                 m : Monster
                 m = MkMonster nextId kind c hp hp state []
                 cs' = filter (/= c) cs
             in go k cs' (nextId + 1) g4 (m :: acc)
           _ => (reverse acc, nextId, g2)
