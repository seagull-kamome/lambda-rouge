||| The pure turn resolver.
|||
||| `step` validates a command, resolves the player's action, then lets
||| every monster on the current level act in `MonsterId` order, and
||| finally recomputes the field of view.  A level change (stairs or a
||| trapdoor) skips the monster turn for the newly entered level.
module LambdaRogue.Core.Game

import Data.Bits
import Data.List
import Data.Maybe
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Combat
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Fov
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Item
import LambdaRogue.Core.Message
import LambdaRogue.Core.Monster
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Survival
import LambdaRogue.Core.Types

%default covering

public export
data Command
  = Move Dir
  | Wait
  | Search
  | PickUp
  | Quaff ItemId
  | Read ItemId
  | Eat ItemId
  | Wield ItemId
  | Wear ItemId
  | PutOnRing ItemId
  | TakeOff ItemId
  | Drop ItemId
  | Throw ItemId Dir
  | Zap ItemId Dir
  | Descend
  | Ascend

public export
Eq Command where
  Move a == Move b = a == b
  Wait == Wait = True
  Search == Search = True
  PickUp == PickUp = True
  Quaff a == Quaff b = a == b
  Read a == Read b = a == b
  Eat a == Eat b = a == b
  Wield a == Wield b = a == b
  Wear a == Wear b = a == b
  PutOnRing a == PutOnRing b = a == b
  TakeOff a == TakeOff b = a == b
  Drop a == Drop b = a == b
  Throw a d == Throw b e = a == b && d == e
  Zap a d == Zap b e = a == b && d == e
  Descend == Descend = True
  Ascend == Ascend = True
  _ == _ = False

public export
Show Command where
  show (Move d) = "Move " ++ show d
  show Wait = "Wait"
  show Search = "Search"
  show PickUp = "PickUp"
  show (Quaff i) = "Quaff " ++ show i
  show (Read i) = "Read " ++ show i
  show (Eat i) = "Eat " ++ show i
  show (Wield i) = "Wield " ++ show i
  show (Wear i) = "Wear " ++ show i
  show (PutOnRing i) = "PutOnRing " ++ show i
  show (TakeOff i) = "TakeOff " ++ show i
  show (Drop i) = "Drop " ++ show i
  show (Throw i d) = "Throw " ++ show i ++ " " ++ show d
  show (Zap i d) = "Zap " ++ show i ++ " " ++ show d
  show Descend = "Descend"
  show Ascend = "Ascend"

public export
data Event
  = PlayerMoved Coord
  | MonsterMoved MonsterId Coord
  | PlayerAttacked MonsterId Int32
  | MonsterAttacked MonsterId Int32
  | MonsterWoke MonsterId
  | MonsterDied MonsterId
  | ItemPicked ItemId
  | ItemUsed ItemId
  | ItemDropped ItemId
  | DoorOpened Coord
  | TrapTriggered TrapKind Coord
  | LevelChanged Depth
  | PlayerLevelUp Int32
  | PlayerDied
  | PlayerWon

public export
Show Event where
  show (PlayerMoved c) = "PlayerMoved " ++ show c
  show (MonsterMoved i c) = "MonsterMoved " ++ show i ++ " " ++ show c
  show (PlayerAttacked i d) = "PlayerAttacked " ++ show i ++ " " ++ show d
  show (MonsterAttacked i d) = "MonsterAttacked " ++ show i ++ " " ++ show d
  show (MonsterWoke i) = "MonsterWoke " ++ show i
  show (MonsterDied i) = "MonsterDied " ++ show i
  show (ItemPicked i) = "ItemPicked " ++ show i
  show (ItemUsed i) = "ItemUsed " ++ show i
  show (ItemDropped i) = "ItemDropped " ++ show i
  show (DoorOpened c) = "DoorOpened " ++ show c
  show (TrapTriggered k c) = "TrapTriggered " ++ show k ++ " " ++ show c
  show (LevelChanged d) = "LevelChanged " ++ show d
  show (PlayerLevelUp l) = "PlayerLevelUp " ++ show l
  show PlayerDied = "PlayerDied"
  show PlayerWon = "PlayerWon"

public export
record Outcome where
  constructor MkOutcome
  game : Game
  messages : List Message
  events : List Event
  turnConsumed : Bool

record Step where
  constructor MkStep
  game : Game
  events : List Event
  newMessages : List Message
  consumed : Bool

say : MessageKind -> Msg -> Step -> Step
say kind message st =
  let msg : Message
      msg = mkMessage st.game.turn kind message
      g : Game
      g = { messages := take 200 (msg :: st.game.messages) } st.game
  in { game := g, newMessages := msg :: st.newMessages } st

event : Event -> Step -> Step
event e st = { events := e :: st.events } st

consume : Step -> Step
consume st = { consumed := True } st

monsterAt : Level -> Coord -> Maybe Monster
monsterAt lvl c = find (\m => m.pos == c) lvl.monsters

monsterById : MonsterId -> Level -> Maybe Monster
monsterById i lvl = find (\m => m.id == i) lvl.monsters

updateMonster : MonsterId -> (Monster -> Monster) -> Level -> Level
updateMonster i f lvl =
  { monsters := map (\m => if m.id == i then f m else m) lvl.monsters } lvl

removeMonster : MonsterId -> Level -> Level
removeMonster i lvl =
  { monsters := filter (\m => m.id /= i) lvl.monsters } lvl

||| A monster that acts or is attacked can no longer pass for an object.
revealMimicAt : MonsterId -> Level -> Level
revealMimicAt i lvl =
  updateMonster i
    (\m => { statuses := filter (\s => s.statusKind /= Mimicking) m.statuses } m)
    lvl

revealMimic : MonsterId -> Game -> Game
revealMimic i g = updateCurrentLevel (revealMimicAt i) g

itemAt : Game -> Coord -> Maybe Item
itemAt g c =
  find (\i => case i.location of
                OnFloor d p => d == g.depth && p == c
                InPack => False
                CarriedBy _ => False)
       g.items

trapAt : Level -> Coord -> Maybe Trap
trapAt lvl c = find (\t => t.pos == c) lvl.traps

setPlayer : Player -> Step -> Step
setPlayer p st = { game := { player := p } st.game } st

addKnown : ItemKind -> Game -> Game
addKnown k g =
  if elem k g.knownKinds
     then g
     else { knownKinds := k :: g.knownKinds } g

removePackItem : ItemId -> Game -> Game
removePackItem iid g =
  let p : Player
      p = { inventory := filter (/= iid) g.player.inventory } g.player
  in { items := filter (\i => i.id /= iid) g.items, player := p } g

addStatus : StatusKind -> Int32 -> Player -> Player
addStatus k turns p =
  { statuses := MkStatus k (max 1 turns)
                :: filter (\s => s.statusKind /= k) p.statuses } p

directions : List Dir
directions = [N, NE, E, SE, S, SW, W, NW]

hasAmulet : Game -> Bool
hasAmulet g =
  any (\i => i.kind == Amulet && i.location == InPack) g.items

||| Apply direct damage and turn it into a death when HP reaches zero.
damagePlayer : DeathCause -> Int32 -> Step -> Step
damagePlayer cause dmg st =
  let g = st.game
      hp' = max 0 (g.player.hp - dmg)
      p : Player
      p = { hp := hp' } g.player
      g1 : Game
      g1 = { player := p } g
      st1 = say WarningMsg (TakeDamage dmg)
              ({ game := g1 } st)
  in if hp' <= 0
        then let g2 : Game
                 g2 = { over := Just (Dead cause) } g1
             in event PlayerDied
                  (say WarningMsg (Die False cause)
                    ({ game := g2 } st1))
        else st1

addLevelUpMessages : ExpResult -> Step -> Step
addLevelUpMessages er st =
  if er.levelsGained == 0
     then st
     else event (PlayerLevelUp er.player.level)
            (say SystemMsg (WelcomeLevel er.player.level)
                st)

||| Replace one item in the run-wide item list.
updateItem : ItemId -> (Item -> Item) -> Game -> Game
updateItem iid f g =
  { items := map (\i => if i.id == iid then f i else i) g.items } g

||| Drop everything a dead monster was carrying at its last position.
dropCarriedBy : MonsterId -> Coord -> Game -> Game
dropCarriedBy mid pos g =
  { items := map (\i => case i.location of
                          CarriedBy m => if m == mid
                                            then { location :=
                                                     OnFloor g.depth pos } i
                                            else i
                          _ => i)
                g.items } g

weaponStats : Item -> (Int32, Int32, Int32)
weaponStats it =
  case it.kind of
    Weapon w => let (d, s) = weaponDamage w in (d, s, it.enchant)
    _ => let (d, s) = unarmedDamage in (d, s, 0)

recomputeWeapon : Game -> Game
recomputeWeapon g =
  case g.player.wielded of
    Nothing =>
      let (d, s) = unarmedDamage
          p : Player
          p = { weaponDice := d, weaponSides := s, weaponBonus := 0 } g.player
      in { player := p } g
    Just iid =>
      case findPackItem g iid of
        Just it =>
          let (d, s, b) = weaponStats it
              p : Player
              p = { weaponDice := d, weaponSides := s, weaponBonus := b } g.player
          in { player := p } g
        Nothing => g

recomputeArmor : Game -> Game
recomputeArmor g =
  case g.player.worn of
    Nothing => { player := { armor := 10 } g.player } g
    Just iid =>
      case findPackItem g iid of
        Just it =>
          case it.kind of
            Armor a =>
              let p : Player
                  p = { armor := armorValue a - it.enchant } g.player
              in { player := p } g
            _ => g
        Nothing => g

||| Ring increments are signed: a +2 ring has power 2, a -1 ring is
||| cursed and works against the wearer where applicable.
ringPower : Item -> Int32
ringPower i = i.enchant

ringStats : Game -> (Int32, Int32, Int32, Int32)
ringStats g =
  foldl add (0, 0, 0, 0) (catMaybes [g.player.leftRing, g.player.rightRing])
  where
    add : (Int32, Int32, Int32, Int32) -> ItemId
        -> (Int32, Int32, Int32, Int32)
    add (a, d, acc, s) iid =
      case find (\i => i.id == iid) g.items of
        Just it =>
          case it.kind of
            Ring RingProtection => (a + ringPower it, d, acc, s)
            Ring RingIncreaseDamage => (a, d + ringPower it, acc, s)
            Ring RingDexterity => (a, d, acc + ringPower it, s)
            Ring RingAddStrength => (a, d, acc, s + ringPower it)
            _ => (a, d, acc, s)
        Nothing => (a, d, acc, s)

recomputeRings : Game -> Game
recomputeRings g =
  let (a, d, acc, s) = ringStats g
      p : Player
      p = { ringArmor := a, ringDamage := d,
            ringAccuracy := acc, ringStrength := s } g.player
  in { player := p } g

||| Apply one point of rust to the worn armor, honouring protection and
||| the ring of maintain armor.  The caller supplies the narrative lead.
rustPlayerArmor : RustSource -> Step -> Step
rustPlayerArmor src st =
  case st.game.player.worn of
    Nothing => say WarningMsg (ArmorUnaffected src) st
    Just iid =>
      case findPackItem st.game iid of
        Nothing => say WarningMsg (ArmorUnaffected src) st
        Just it =>
          if it.protected || hasRing RingMaintainArmor st.game
             then say ItemMsg ArmorProtected st
             else let g1 : Game
                      g1 = updateItem iid
                             (\i => { enchant := i.enchant - 1 } i) st.game
                      g2 : Game
                      g2 = recomputeArmor g1
                  in say WarningMsg
                       (ArmorWeakens src (itemDisplayNameIn g2 it))
                       ({ game := g2 } st)

fullMapBits : Bitset
fullMapBits =
  foldl (\bs, c => setBit c.x c.y bs) empty
    [MkCoord x y | y <- range 0 21, x <- range 0 79]

revealMap : Game -> Game
revealMap g =
  updateCurrentLevel (\l => { explored := fullMapBits } l) g

roomAt : Level -> Coord -> Maybe Room
roomAt lvl (MkCoord x y) =
  find (\r => x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h)
       lvl.rooms

||| A wand of light maps only the room the player is standing in, including
||| its wall border.  In a corridor there is no room to light.
revealRoom : Game -> Game
revealRoom g =
  case roomAt (currentLevel g) g.player.pos of
    Nothing => g
    Just r =>
      let lit = [MkCoord x y | x <- range (r.x - 1) (r.x + r.w),
                               y <- range (r.y - 1) (r.y + r.h),
                               inBounds (MkCoord x y)]
          explored' = foldl (\bs, c => setBit c.x c.y bs)
                            (currentLevel g).explored lit
      in updateCurrentLevel (\l => { explored := explored' } l) g

visibleMonsters : Game -> List Monster
visibleMonsters g =
  filter (\m => getBit m.pos.x m.pos.y g.visible)
         (currentLevel g).monsters

monsterHasStatus : StatusKind -> Monster -> Bool
monsterHasStatus k m = any (\s => s.statusKind == k) m.statuses

addMonsterStatus : StatusKind -> Int32 -> Monster -> Monster
addMonsterStatus k turns m =
  { statuses := MkStatus k (max 1 turns)
                :: filter (\s => s.statusKind /= k) m.statuses } m

tickMonsterStatuses : Monster -> Monster
tickMonsterStatuses m =
  { statuses := mapMaybe tickOne m.statuses } m
  where
    tickOne : Status -> Maybe Status
    tickOne s =
      if s.statusKind == Mimicking
         then Just s
         else if s.remaining > 1
                 then Just ({ remaining := s.remaining - 1 } s)
                 else Nothing

beamCells : Game -> Dir -> List Coord
beamCells g d = go 1
  where
    delta' : Coord
    delta' = delta d

    at : Int32 -> Coord
    at n = MkCoord (g.player.pos.x + delta'.x * n)
                   (g.player.pos.y + delta'.y * n)

    go : Int32 -> List Coord
    go n =
      if n > 8
         then []
         else let c = at n
              in case tileAt (currentLevel g).tiles c of
                   Nothing => []
                   Just t =>
                     if walkable t
                        then c :: go (n + 1)
                        else []

beamTarget : Game -> Dir -> Maybe (Coord, Monster)
beamTarget g d = go (beamCells g d)
  where
    go : List Coord -> Maybe (Coord, Monster)
    go [] = Nothing
    go (c :: cs) =
      case monsterAt (currentLevel g) c of
        Just m => Just (c, m)
        Nothing => go cs

damageMonster : Monster -> Int32 -> AttackLead -> Step -> Step
damageMonster m dmg lead st =
  let g = st.game
      lvl = currentLevel g
      dmg' = max 1 dmg
      hp' = m.hp - dmg'
  in if hp' <= 0
        then let lvl' : Level
                 lvl' = removeMonster m.id lvl
                 g1 : Game
                 g1 = updateCurrentLevel (const lvl') g
                 g1d : Game
                 g1d = dropCarriedBy m.id m.pos g1
                 spec = monsterSpec m.kind
                 er = gainExperience g1d.player
                                   (monsterExpGain spec m.maxHp) g1d.rng
                 g2 : Game
                 g2 = { player := er.player, rng := er.rng } g1d
                 st1 = event (MonsterDied m.id)
                         (say CombatMsg
                           (KillMonster lead m.kind)
                           ({ game := g2 } st))
             in addLevelUpMessages er st1
        else let lvl' : Level
                 lvl' = revealMimicAt m.id
                          (updateMonster m.id (\mm => { hp := hp' } mm) lvl)
                 g1 : Game
                 g1 = updateCurrentLevel (const lvl') g
             in event (PlayerAttacked m.id dmg')
                  (say CombatMsg
                    (MonsterTakesDamage lead m.kind dmg')
                    ({ game := g1 } st))

identifyFirst : (ItemKind -> Bool) -> Game -> (Game, Maybe Item)
identifyFirst p g =
  case find (\i => i.location == InPack && p i.kind
                   && not (itemKnown g.knownKinds i))
            (packItems g) of
    Nothing => (g, Nothing)
    Just i => (addKnown i.kind g, Just i)

teleportMonster : Monster -> Step -> Step
teleportMonster m st =
  let g = st.game
      lvl = currentLevel g
      cells = filter (\c => c /= g.player.pos
                            && isNothing (monsterAt lvl c)
                            && maybe False walkable (tileAt lvl.tiles c))
                     (allWalkableCells lvl.tiles)
      (targetOpt, rng') = pick cells g.rng
  in case targetOpt of
       Nothing => say WarningMsg MonsterResists st
       Just target =>
         let lvl' : Level
             lvl' = updateMonster m.id (\mm => { pos := target } mm) lvl
             g' : Game
             g' = { rng := rng' }
                    (updateCurrentLevel (const lvl') g)
         in say SystemMsg (MonsterVanishes m.kind)
              ({ game := g' } st)

createMonsterNear : Step -> Step
createMonsterNear st =
  let g = st.game
      lvl = currentLevel g
      cells = filter (\c => c /= g.player.pos
                            && isNothing (monsterAt lvl c)
                            && maybe False walkable (tileAt lvl.tiles c))
                     (allWalkableCells lvl.tiles)
      (kindOpt, g1) = pick (spawnPool g.depth) g.rng
      (coordOpt, g2) = pick cells g1
  in case (kindOpt, coordOpt) of
       (Just kind, Just c) =>
         let spec = monsterSpec kind
             (hp, g3) = rollMonsterHp spec g2
             m : Monster
             m = MkMonster g.nextMonsterId kind c hp hp Awake []
             lvl' : Level
             lvl' = { monsters := lvl.monsters ++ [m] } lvl
             g' : Game
             g' = { rng := g3, nextMonsterId := g.nextMonsterId + 1 }
                    (updateCurrentLevel (const lvl') g)
         in say SystemMsg (MonsterAppears kind)
              ({ game := g' } st)
       _ => say WarningMsg ScrollFizzles st

attackMonster : Monster -> Step -> Step
attackMonster m st =
  let g = st.game
      (result, rng') = playerAttack g.player m g.rng
      g1 : Game
      g1 = { rng := rng' } g
      lvl = currentLevel g1
  in case result of
       Miss =>
         event (PlayerAttacked m.id 0)
           (consume (say CombatMsg (MissMonster m.kind)
                       ({ game := revealMimic m.id g1 } st)))
       Hit dmg =>
         let confuse = hasStatus ConfuseNext g1.player
             monsterStatuses = if confuse
                                 then MkStatus Confused 20 :: m.statuses
                                 else m.statuses
             player' : Player
             player' = if confuse
                          then { statuses := filter
                                   (\s => s.statusKind /= ConfuseNext)
                                   g1.player.statuses } g1.player
                          else g1.player
             hp' = m.hp - dmg
             lvl' : Level
             lvl' = updateMonster m.id
                      (\mm => { hp := hp', statuses := monsterStatuses } mm) lvl
             g2 : Game
             g2 = { player := player' }
                    (updateCurrentLevel (const lvl') g1)
         in event (PlayerAttacked m.id dmg)
              (consume (say CombatMsg
                (HitMonster m.kind dmg confuse)
                ({ game := revealMimic m.id g2 } st)))
       Killed dmg =>
         let lvl' : Level
             lvl' = removeMonster m.id lvl
             g2 : Game
             g2 = updateCurrentLevel (const lvl') g1
             g2d : Game
             g2d = dropCarriedBy m.id m.pos g2
             spec = monsterSpec m.kind
             er = gainExperience g2d.player
                               (monsterExpGain spec m.maxHp) g2d.rng
             g3 : Game
             g3 = { player := er.player, rng := er.rng } g2d
             st1 = event (MonsterDied m.id)
                     (consume (say CombatMsg
                       (KillMonsterPlain m.kind)
                       ({ game := g3 } st)))
         in addLevelUpMessages er st1

openDoor : Coord -> Step -> Step
openDoor c st =
  let g = st.game
      lvl = currentLevel g
      message = case tileAt lvl.tiles c of
                  Just (Door Secret) => FoundSecretDoor
                  _ => OpenDoor
      lvl' : Level
      lvl' = { tiles := setTile c (Door Open) lvl.tiles } lvl
      g' : Game
      g' = updateCurrentLevel (const lvl') g
  in event (DoorOpened c)
       (consume (say SystemMsg message ({ game := g' } st)))

trapDamage : TrapKind -> Int32 -> Int32 -> Step -> Step
trapDamage kind n sides st =
  let g = st.game
      (dmg, rng') = roll n sides g.rng
      hp' = max 0 (g.player.hp - dmg)
      player' : Player
      player' = { hp := hp' } g.player
      g1 : Game
      g1 = { rng := rng', player := player' } g
      hit = say WarningMsg (TakeDamage dmg)
              ({ game := g1 } st)
  in if hp' <= 0
       then let g2 : Game
                g2 = { over := Just (Dead (KilledByTrap kind)) } g1
            in event PlayerDied
                 (say WarningMsg (Die True (KilledByTrap kind))
                   ({ game := g2 } st))
       else hit

teleportPlayer : Step -> Step
teleportPlayer st =
  let g = st.game
      lvl = currentLevel g
      cells = filter (\c => c /= g.player.pos
                            && isNothing (monsterAt lvl c))
                     (allWalkableCells lvl.tiles)
      (targetOpt, rng') = pick cells g.rng
  in case targetOpt of
       Nothing => say WarningMsg TeleportFizzles st
       Just target =>
         let player' : Player
             player' = { pos := target } g.player
             g' : Game
             g' = { rng := rng', player := player' } g
         in say SystemMsg (Teleported target)
              ({ game := g' } st)

descendLevel : Step -> Step
descendLevel st =
  let g = st.game
  in if g.depth >= 26
       then say WarningMsg CannotDescend st
       else case find (\l => l.depth == g.depth + 1) g.levels of
              Just existing =>
                let rest = filter (\l => l.depth /= existing.depth) g.levels
                    start = fromMaybe g.player.pos existing.upStairs
                    player' : Player
                    player' = { pos := start } g.player
                    g' : Game
                    g' = { depth := g.depth + 1
                         , levels := existing :: rest
                         , player := player'
                         } g
                in event (LevelChanged g'.depth)
                     (consume (say SystemMsg
                       (DescendLevel g'.depth)
                       ({ game := g' } st)))
              Nothing =>
                let gen = generateLevel (g.depth + 1) g.nextMonsterId
                                        g.nextItemId g.rng
                    start = fromMaybe (MkCoord 1 1) gen.level.upStairs
                    player' : Player
                    player' = { pos := start } g.player
                    g' : Game
                    g' = { depth := g.depth + 1
                         , levels := gen.level :: g.levels
                         , items := g.items ++ gen.items
                         , rng := gen.rng
                         , nextMonsterId := gen.nextMonsterId
                         , nextItemId := gen.nextItemId
                         , player := player'
                         } g
                in event (LevelChanged g'.depth)
                     (consume (say SystemMsg
                       (DescendLevel g'.depth)
                       ({ game := g' } st)))

winGame : Step -> Step
winGame st =
  let g : Game
      g = { over := Just Won } st.game
  in event PlayerWon
       (say StoryMsg WinGame
         ({ game := g } st))

ascendLevel : Step -> Step
ascendLevel st =
  let g = st.game
  in if not (hasAmulet g)
        then say WarningMsg CannotReturn st
        else if g.depth <= 1
                then consume (winGame st)
                else case find (\l => l.depth == g.depth - 1) g.levels of
                       Just target =>
                         let current = currentLevel g
                             rest = filter (\l => l.depth /= target.depth) g.levels
                             others = filter (\l => l.depth /= current.depth) rest
                             levels' = target :: (others ++ [current])
                             start = fromMaybe g.player.pos target.downStairs
                             player' : Player
                             player' = { pos := start } g.player
                             g' : Game
                             g' = { depth := g.depth - 1
                                  , levels := levels'
                                  , player := player'
                                  } g
                             st1 = event (LevelChanged g'.depth)
                                     (consume (say SystemMsg
                                       (AscendLevel g'.depth)
                                       ({ game := g' } st)))
                         in st1
                       Nothing => say WarningMsg WayUpBlocked st

applyTrap : Trap -> Step -> Step
applyTrap trap st =
  case trap.kind of
    TrapDoor =>
      if st.game.depth < 26
         then descendLevel st
         else trapDamage TrapDoor 1 6 st
    ArrowTrap => trapDamage ArrowTrap 1 6 st
    DartTrap =>
      let st1 = trapDamage DartTrap 1 4 st
      in if isJust st1.game.over
            then st1
            else if hasRing RingSustainStrength st1.game
                    then say WarningMsg StrengthHolds st1
                    else let p = st1.game.player
                             p' : Player
                             p' = { strength := max 0 (p.strength - 1) } p
                         in say WarningMsg FeelWeaker
                              (setPlayer p' st1)
    Bear =>
      say WarningMsg BearTrap
        (setPlayer (addStatus Held 4 st.game.player) st)
    Teleport => teleportPlayer st
    Sleep =>
      say WarningMsg FallAsleep
        (setPlayer (addStatus Sleeping 6 st.game.player) st)
    Rust => rustPlayerArmor RustTrap st
    Mysterious =>
      say SystemMsg StrangeNoise st

triggerTrap : Coord -> Step -> Step
triggerTrap c st =
  let lvl = currentLevel st.game
  in case find (\t => t.pos == c && not t.revealed) lvl.traps of
       Nothing => st
       Just trap =>
         let lvl' : Level
             lvl' = { traps := map (\t : Trap =>
                                      if t.pos == c
                                         then { revealed := True } t
                                         else t)
                                 lvl.traps } lvl
             g' : Game
             g' = updateCurrentLevel (const lvl') st.game
             st1 = event (TrapTriggered trap.kind c)
                     (say SystemMsg (TriggerTrap trap.kind)
                         ({ game := g' } st))
         in applyTrap trap st1

||| Searching is less reliable when blind or hallucinating, mirroring the
||| original's increased denominator (`rnd(2 + probinc)`).
searchPenalty : Player -> Bits64
searchPenalty p =
  let blind = if hasStatus Blinded p then 2 else 0
      hallucinating = if hasStatus Hallucinating p then 3 else 0
  in cast (blind + hallucinating)

trapFoundMessage : TrapKind -> String
trapFoundMessage TrapDoor = "You found a trapdoor."
trapFoundMessage ArrowTrap = "You found an arrow trap."
trapFoundMessage Sleep = "You found a sleeping gas trap."
trapFoundMessage Bear = "You found a bear trap."
trapFoundMessage Teleport = "You found a teleport trap."
trapFoundMessage DartTrap = "You found a dart trap."
trapFoundMessage Rust = "You found a rust trap."
trapFoundMessage Mysterious = "You found a mysterious trap."

revealTrapAt : Coord -> Game -> Game
revealTrapAt c g =
  let lvl = currentLevel g
      lvl' : Level
      lvl' = { traps := map (\t : Trap =>
                               if t.pos == c
                                  then { revealed := True } t
                                  else t)
                          lvl.traps } lvl
  in updateCurrentLevel (const lvl') g

||| Searching a secret door turns it into a closed door, exactly as if the
||| door had been generated normally.  The player then opens it by walking
||| into it.
revealSecretDoorAt : Coord -> Game -> Game
revealSecretDoorAt c g =
  let lvl = currentLevel g
      lvl' : Level
      lvl' = { tiles := setTile c (Door Closed) lvl.tiles } lvl
  in updateCurrentLevel (const lvl') g

||| Search the eight neighbouring cells for secret doors.  Each secret
||| door is found with the same probability as a trap.
searchDoors : Step -> (Step, Bool)
searchDoors st0 =
  let around = map (\d => add st0.game.player.pos (delta d)) directions
      bound = the Bits64 2 + searchPenalty st0.game.player
      visit : (Step, Bool) -> Coord -> (Step, Bool)
      visit (st, found) c =
        case tileAt (currentLevel st.game).tiles c of
          Just (Door Secret) =>
            let (roll', rng') = uniform bound st.game.rng
                st1 : Step
                st1 = { game := { rng := rng' } st.game } st
            in if roll' == 0
                  then (say SystemMsg FoundSecretDoor
                          ({ game := revealSecretDoorAt c st1.game } st1), True)
                  else (st1, found)
          _ => (st, found)
  in foldl visit (st0, False) around

||| Search the eight neighbouring cells.  Each unrevealed trap is found
||| with probability 1/2 (1/4 when blind, lower still when hallucinating).
||| Secret doors use the same probability and become closed doors.
searchTraps : Step -> (Step, Bool)
searchTraps st0 =
  let around = map (\d => add st0.game.player.pos (delta d)) directions
      bound = the Bits64 2 + searchPenalty st0.game.player
      visit : (Step, Bool) -> Trap -> (Step, Bool)
      visit (st, found) t =
        if t.revealed || not (elem t.pos around)
           then (st, found)
           else let (roll', rng') = uniform bound st.game.rng
                    st1 : Step
                    st1 = { game := { rng := rng' } st.game } st
                in if roll' == 0
                      then let g' = revealTrapAt t.pos st1.game
                               message = if hasStatus Hallucinating st1.game.player
                                            then FoundTrapUnknown
                                            else FoundTrap t.kind
                           in (say SystemMsg message ({ game := g' } st1), True)
                      else (st1, found)
  in foldl visit (st0, False) (currentLevel st0.game).traps

searchArea : Step -> Step
searchArea st =
  let (st1, foundDoor) = searchDoors st
      (st2, foundTrap) = searchTraps st1
  in consume (if foundDoor || foundTrap
                 then st2
                 else say SystemMsg SearchNothing st2)

playerMove : Dir -> Step -> Step
playerMove d st =
  let g0 = st.game
      (d', rng') =
        if hasStatus Confused g0.player
           then let (chosen, r) = pick directions g0.rng
                in (fromMaybe d chosen, r)
           else (d, g0.rng)
      g : Game
      g = { rng := rng' } g0
      st0 : Step
      st0 = { game := g } st
      target = add g.player.pos (delta d')
      lvl = currentLevel g
  in if hasStatus Held g.player
        && isNothing (monsterAt lvl target)
        then consume (say WarningMsg HeldInPlace st0)
        else if not (inBounds target)
                then say WarningMsg WallThere st0
                else case tileAt lvl.tiles target of
                       Nothing => say WarningMsg WallThere st0
                       Just (Door Locked) =>
                         say WarningMsg DoorLocked st0
                       Just t =>
                         if openable t
                            then openDoor target st0
                            else if not (walkable t)
                                    then say WarningMsg WallThere st0
                                    else case monsterAt lvl target of
                                           Just m => attackMonster m st0
                                           Nothing =>
                                             let player' : Player
                                                 player' = { pos := target } g.player
                                                 g' : Game
                                                 g' = { player := player' } g
                                                 st1 = event (PlayerMoved target)
                                                         (consume ({ game := g' } st0))
                                             in if hasStatus Levitated g.player
                                                   then st1
                                                   else triggerTrap target st1

stairsAction : StairDir -> Step -> Step
stairsAction dir st =
  let g = st.game
      lvl = currentLevel g
  in case tileAt lvl.tiles g.player.pos of
       Just (Stairs d) =>
         if d == dir
            then case dir of
                   Down => descendLevel st
                   Up => ascendLevel st
            else say WarningMsg (NotOnStairs dir) st
       _ => say WarningMsg (NotOnStairs dir) st

pickUp : Step -> Step
pickUp st =
  case itemAt st.game st.game.player.pos of
    Nothing => say WarningMsg NothingHere st
    Just it =>
      case it.kind of
        Gold =>
          let g = st.game
              items' : List Item
              items' = filter (\i => i.id /= it.id) g.items
              player' : Player
              player' = { gold := g.player.gold + it.count } g.player
              g' : Game
              g' = { items := items', player := player' } g
          in event (ItemPicked it.id)
               (consume (say ItemMsg
                 (PickUpGold it.count)
                 ({ game := g' } st)))
        _ =>
          if length st.game.player.inventory >= maxPack
             then say WarningMsg PackFull st
             else let g = st.game
                      items' : List Item
                      items' = map (\i => if i.id == it.id
                                             then { location := InPack } i
                                             else i)
                                   g.items
                      player' : Player
                      player' = { inventory := it.id :: g.player.inventory }
                                  g.player
                      g' : Game
                      g' = { items := items', player := player' } g
                      shown = itemDisplayNameIn g' it
                      message = if it.kind == Amulet
                                   then PickUpAmulet
                                   else PickUpItem shown
                  in event (ItemPicked it.id)
                       (consume (say ItemMsg message ({ game := g' } st)))

applyPotion : PotionKind -> Step -> Step
applyPotion PotionHealing st =
  let p = st.game.player
      (n, rng') = roll p.level 4 st.game.rng
      healed = p.hp + n
      hp' : Int32
      hp' = if healed > p.maxHp then p.maxHp + 1 else healed
      maxHp' : Int32
      maxHp' = if healed > p.maxHp then p.maxHp + 1 else p.maxHp
      p' : Player
      p' = { hp := hp', maxHp := maxHp' } p
      g : Game
      g = { rng := rng' } st.game
  in say ItemMsg FeelBetter (setPlayer p' ({ game := g } st))
applyPotion PotionExtraHealing st =
  let p = st.game.player
      (n, rng') = roll p.level 8 st.game.rng
      healed = p.hp + n
      boosted = healed > p.maxHp
      maxHp' : Int32
      maxHp' = if boosted
                  then if healed > p.maxHp + p.level + 1
                          then p.maxHp + 2
                          else p.maxHp + 1
                  else p.maxHp
      hp' : Int32
      hp' = if boosted then maxHp' else healed
      p' : Player
      p' = { hp := hp', maxHp := maxHp' } p
      g : Game
      g = { rng := rng' } st.game
  in say ItemMsg FeelMuchBetter (setPlayer p' ({ game := g } st))
applyPotion PotionStrength st =
  let p = st.game.player
  in if p.strength >= 31
        then say ItemMsg AlreadyStrong st
        else let s = p.strength + 1
                 p' : Player
                 p' = { strength := s, maxStrength := max p.maxStrength s } p
             in say ItemMsg FeelStronger (setPlayer p' st)
applyPotion PotionRestoreStrength st =
  let p = st.game.player
      p' : Player
      p' = { strength := p.maxStrength } p
  in say ItemMsg StrengthReturns (setPlayer p' st)
applyPotion PotionPoison st =
  let (drain, rng1) = roll 1 3 st.game.rng
      g : Game
      g = { rng := rng1 } st.game
  in if hasRing RingSustainStrength g
        then say ItemMsg SickStrengthHolds
               ({ game := g } st)
        else let p = g.player
                 p' : Player
                 p' = { strength := max 0 (p.strength - drain)
                      , statuses := filter
                          (\s => s.statusKind /= Hallucinating) p.statuses
                      } p
             in say WarningMsg WeakerHeadClears
                  (setPlayer p' ({ game := g } st))
applyPotion PotionConfusion st =
  let (turns, rng') = roll 1 8 st.game.rng
      p' = addStatus Confused (turns + 4) st.game.player
      g : Game
      g = { rng := rng' } st.game
  in say ItemMsg FeelConfused (setPlayer p' ({ game := g } st))
applyPotion PotionHallucination st =
  let (turns, rng') = roll 1 50 st.game.rng
      p' = addStatus Hallucinating (turns + 20) st.game.player
      g : Game
      g = { rng := rng' } st.game
  in say ItemMsg EverythingStrange
       (setPlayer p' ({ game := g } st))
applyPotion PotionBlindness st =
  let (turns, rng') = roll 1 8 st.game.rng
      p' = addStatus Blinded (turns + 4) st.game.player
      g : Game
      g = { rng := rng' } st.game
  in say WarningMsg Blinded (setPlayer p' ({ game := g } st))
applyPotion PotionDetectMonsters st =
  let (turns, rng') = roll 1 8 st.game.rng
      p' = addStatus DetectMonsters (turns + 4) st.game.player
      g : Game
      g = { rng := rng' } st.game
  in say ItemMsg SenseMonsters
       (setPlayer p' ({ game := g } st))
applyPotion PotionMagicDetection st =
  let (turns, rng') = roll 1 8 st.game.rng
      p' = addStatus DetectMagic (turns + 4) st.game.player
      magicCells = mapMaybe
                     (\i => case i.location of
                              OnFloor d c =>
                                if d == st.game.depth
                                   && i.kind /= Gold && i.kind /= Amulet
                                   then Just c else Nothing
                              _ => Nothing)
                     st.game.items
      g0 = st.game
      g1 : Game
      g1 = updateCurrentLevel
             (\l => { explored := foldl (\bs, c => setBit c.x c.y bs)
                                         l.explored magicCells } l) g0
      g : Game
      g = { rng := rng', player := p' } g1
  in say ItemMsg SenseMagic
       ({ game := g } st)
applyPotion PotionHasteSelf st =
  let (turns, rng') = roll 1 8 st.game.rng
      p' = addStatus Hasted (turns + 4) st.game.player
      g : Game
      g = { rng := rng' } st.game
  in say ItemMsg MovingFaster
       (setPlayer p' ({ game := g } st))
applyPotion PotionSeeInvisible st =
  let (turns, rng') = roll 1 8 st.game.rng
      p' = addStatus SeeInvisible (turns + 4) st.game.player
      g : Game
      g = { rng := rng' } st.game
  in say ItemMsg EyesStrange (setPlayer p' ({ game := g } st))
applyPotion PotionLevitation st =
  let (turns, rng') = roll 1 20 st.game.rng
      p' = addStatus Levitated (turns + 10) st.game.player
      g : Game
      g = { rng := rng' } st.game
  in say ItemMsg Float
       (setPlayer p' ({ game := g } st))
applyPotion PotionRaiseLevel st =
  let p = st.game.player
      amount = max 1 (expForNext p.level - p.exp)
      er = gainExperience p amount st.game.rng
      g : Game
      g = { player := er.player, rng := er.rng } st.game
      st1 = say ItemMsg MoreExperienced ({ game := g } st)
  in addLevelUpMessages er st1

quaff : ItemId -> Step -> Step
quaff iid st =
  case findPackItem st.game iid of
    Nothing => say WarningMsg NoSuchItem st
    Just it =>
      case it.kind of
        Potion k =>
          let shown = itemDisplayNameIn st.game it
              g1 = addKnown (Potion k) (removePackItem iid st.game)
              st1 = say ItemMsg (QuaffItem shown)
                            ({ game := g1 } st)
          in consume (applyPotion k st1)
        _ => say WarningMsg CannotQuaff st

eat : ItemId -> Step -> Step
eat iid st =
  case findPackItem st.game iid of
    Nothing => say WarningMsg NoSuchItem st
    Just it =>
      case it.kind of
        Food FoodRation =>
          let g0 = removePackItem iid st.game
              p : Player
              p = { hunger := g0.player.hunger + hungerMax } g0.player
              g1 : Game
              g1 = { player := p } g0
          in event (ItemUsed iid)
               (consume (say ItemMsg EatRation
                 ({ game := g1 } st)))
        _ => say WarningMsg CannotEat st

equipRingAt : Bool -> Item -> Step -> Step
equipRingAt left it st =
  let p = st.game.player
      p' : Player
      p' = if left
              then { leftRing := Just it.id } p
              else { rightRing := Just it.id } p
      g0 : Game
      g0 = { player := p' } st.game
      g1 : Game
      g1 = addKnown it.kind (recomputeRings g0)
      g : Game
      g = if it.kind == Ring RingAggravateMonster
             then updateCurrentLevel
                    (\l => { monsters := map (\m => { state := Chasing } m)
                                                l.monsters } l) g1
             else g1
      message = if it.cursed
                   then RingTightens
                   else PutOnRing (itemDisplayNameIn g it)
  in event (ItemUsed it.id)
       (consume (say ItemMsg message ({ game := g } st)))

putOnRing : ItemId -> Step -> Step
putOnRing iid st =
  case findPackItem st.game iid of
    Nothing => say WarningMsg NoSuchItem st
    Just it =>
      case it.kind of
        Ring _ =>
          let p = st.game.player
          in if p.leftRing == Just iid || p.rightRing == Just iid
                then say SystemMsg AlreadyWearingRing st
                else case (p.leftRing, p.rightRing) of
                       (Nothing, _) => equipRingAt True it st
                       (_, Nothing) => equipRingAt False it st
                       _ => say WarningMsg FingersFull st
        _ => say WarningMsg CannotPutOn st

isPotionKind : ItemKind -> Bool
isPotionKind (Potion _) = True
isPotionKind _ = False

isScrollKind : ItemKind -> Bool
isScrollKind (Scroll _) = True
isScrollKind _ = False

isWeaponKind : ItemKind -> Bool
isWeaponKind (Weapon _) = True
isWeaponKind _ = False

isArmorKind : ItemKind -> Bool
isArmorKind (Armor _) = True
isArmorKind _ = False

isRingOrWandKind : ItemKind -> Bool
isRingOrWandKind (Ring _) = True
isRingOrWandKind (Wand _) = True
isRingOrWandKind _ = False

identifyMessage : String -> (Game, Maybe Item) -> Step -> Step
identifyMessage what (g, found) st =
  case found of
    Just it => say ItemMsg
      (IdentifyItem (itemDisplayNameIn g it))
      ({ game := g } st)
    Nothing => say WarningMsg (NoUnidentified what) st

applyScroll : ScrollKind -> Step -> Step
applyScroll ScrollConfuseMonster st =
  let p : Player
      p = addStatus ConfuseNext 50 st.game.player
  in say ItemMsg HandsGlowRed
       ({ game := { player := p } st.game } st)
applyScroll ScrollMagicMapping st =
  say ItemMsg MapForms
    ({ game := revealMap st.game } st)
applyScroll ScrollHoldMonster st =
  let g : Game
      g = updateCurrentLevel
            (\l => { monsters := map (addMonsterStatus Held 10) l.monsters } l)
            st.game
  in say ItemMsg MonstersFreeze ({ game := g } st)
applyScroll ScrollSleep st =
  let g : Game
      g = updateCurrentLevel
            (\l => { monsters := map
                       (\m => { state := Asleep }
                                (addMonsterStatus Sleeping 20 m)) l.monsters } l)
            st.game
  in say ItemMsg MonstersSleep ({ game := g } st)
applyScroll ScrollEnchantArmor st =
  case st.game.player.worn of
    Nothing => say WarningMsg NotWearingArmor st
    Just iid =>
      case findPackItem st.game iid of
        Nothing => say WarningMsg NotWearingArmor st
        Just it =>
          let g1 : Game
              g1 = updateItem iid
                     (\i => { enchant := i.enchant + 1, cursed := False } i)
                     st.game
              g2 : Game
              g2 = recomputeArmor g1
          in say ItemMsg
               (ArmorGlowsSilver (itemDisplayNameIn g2 it))
               ({ game := g2 } st)
applyScroll ScrollIdentifyPotion st =
  identifyMessage "potions" (identifyFirst isPotionKind st.game) st
applyScroll ScrollIdentifyScroll st =
  identifyMessage "scrolls" (identifyFirst isScrollKind st.game) st
applyScroll ScrollIdentifyWeapon st =
  identifyMessage "weapons" (identifyFirst isWeaponKind st.game) st
applyScroll ScrollIdentifyArmor st =
  identifyMessage "armor" (identifyFirst isArmorKind st.game) st
applyScroll ScrollIdentifyRingOrWand st =
  identifyMessage "rings or wands"
    (identifyFirst isRingOrWandKind st.game) st
applyScroll ScrollScareMonster st =
  let g : Game
      g = updateCurrentLevel
            (\l => { monsters := map
                       (\m => { state := Fleeing }
                                (addMonsterStatus Scared 12 m)) l.monsters } l)
            st.game
  in say ItemMsg MonstersFlee ({ game := g } st)
applyScroll ScrollFoodDetection st =
  let p : Player
      p = addStatus DetectFood 30 st.game.player
  in say ItemMsg SenseFood ({ game := { player := p } st.game } st)
applyScroll ScrollTeleportation st =
  teleportPlayer (say ItemMsg (Teleported st.game.player.pos) st)
applyScroll ScrollEnchantWeapon st =
  case st.game.player.wielded of
    Nothing => say WarningMsg NotWieldingWeapon st
    Just iid =>
      case findPackItem st.game iid of
        Nothing => say WarningMsg NotWieldingWeapon st
        Just it =>
          let g1 : Game
              g1 = updateItem iid
                     (\i => { enchant := i.enchant + 1, cursed := False } i)
                     st.game
              g2 : Game
              g2 = recomputeWeapon g1
          in say ItemMsg
               (WeaponGlowsBlue (itemDisplayNameIn g2 it))
               ({ game := g2 } st)
applyScroll ScrollCreateMonster st = createMonsterNear st
applyScroll ScrollRemoveCurse st =
  case st.game.player.worn of
    Nothing => say ItemMsg SurgeOfRelief st
    Just iid =>
      case findPackItem st.game iid of
        Nothing => say ItemMsg SurgeOfRelief st
        Just it =>
          let g1 : Game
              g1 = updateItem iid (\i => { cursed := False } i) st.game
              g2 : Game
              g2 = recomputeArmor g1
          in say ItemMsg SurgeOfRelief ({ game := g2 } st)
applyScroll ScrollAggravateMonsters st =
  let g : Game
      g = updateCurrentLevel
            (\l => { monsters := map (\m => { state := Chasing } m) l.monsters } l)
            st.game
  in say WarningMsg GrowlEverywhere
       ({ game := g } st)
applyScroll ScrollProtectArmor st =
  case st.game.player.worn of
    Nothing => say WarningMsg NotWearingArmor st
    Just iid =>
      case findPackItem st.game iid of
        Nothing => say WarningMsg NotWearingArmor st
        Just it =>
          let g : Game
              g = updateItem iid (\i => { protected := True } i) st.game
          in say ItemMsg
               (ArmorFeelsProtected (itemDisplayNameIn g it))
               ({ game := g } st)

read : ItemId -> Step -> Step
read iid st =
  case findPackItem st.game iid of
    Nothing => say WarningMsg NoSuchItem st
    Just it =>
      case it.kind of
        Scroll k =>
          let shown = itemDisplayNameIn st.game it
              g1 = addKnown (Scroll k) (removePackItem iid st.game)
              st1 = say ItemMsg (ReadScroll shown)
                            ({ game := g1 } st)
          in consume (applyScroll k st1)
        _ => say WarningMsg CannotRead st

zapDamage : Int32 -> Int32 -> AttackLead -> Dir -> Step -> Step
zapDamage n sides lead dir st =
  case beamTarget st.game dir of
    Nothing => say WarningMsg BeamFizzles st
    Just (_, m) =>
      let (dmg, rng') = roll n sides st.game.rng
          g : Game
          g = { rng := rng' } st.game
      in damageMonster m dmg lead ({ game := g } st)

applyWand : WandKind -> Dir -> Step -> Step
applyWand WandLight dir st =
  say ItemMsg WandFloodsLight
    ({ game := revealRoom st.game } st)
applyWand WandInvisibility dir st =
  let p : Player
      p = addStatus Invisible 20 st.game.player
  in say ItemMsg FadeOutOfSight ({ game := { player := p } st.game } st)
applyWand WandLightning dir st =
  zapDamage 6 6 WandLightning dir st
applyWand WandFire dir st =
  zapDamage 6 6 WandFire dir st
applyWand WandCold dir st =
  zapDamage 6 6 WandCold dir st
applyWand WandMagicMissile dir st =
  zapDamage 1 4 WandMagicMissile dir st
applyWand WandPolymorph dir st =
  case beamTarget st.game dir of
    Nothing => say WarningMsg BeamFizzles st
    Just (_, m) =>
      let (kindOpt, rng1) = pick (spawnPool st.game.depth) st.game.rng
      in case kindOpt of
           Nothing => say WarningMsg BeamFizzles st
           Just kind =>
             let spec = monsterSpec kind
                 (hp, rng2) = rollMonsterHp spec rng1
                 lvl = currentLevel st.game
                 lvl' : Level
                 lvl' = revealMimicAt m.id
                          (updateMonster m.id
                            (\mm => { kind := kind, hp := hp, maxHp := hp,
                                      state := Chasing } mm) lvl)
                 g : Game
                 g = { rng := rng2 }
                       (updateCurrentLevel (const lvl') st.game)
             in say ItemMsg
                  (MonsterPolymorphs m.kind kind)
                  ({ game := g } st)
applyWand WandHasteMonster dir st =
  case beamTarget st.game dir of
    Nothing => say WarningMsg BeamFizzles st
    Just (_, m) =>
      let lvl = currentLevel st.game
          lvl' : Level
          lvl' = updateMonster m.id (addMonsterStatus Hasted 20) lvl
          g : Game
          g = updateCurrentLevel (const lvl') st.game
      in say ItemMsg (MonsterSpeedsUp m.kind)
           ({ game := g } st)
applyWand WandSlowMonster dir st =
  case beamTarget st.game dir of
    Nothing => say WarningMsg BeamFizzles st
    Just (_, m) =>
      let lvl = currentLevel st.game
          lvl' : Level
          lvl' = updateMonster m.id (addMonsterStatus Slowed 20) lvl
          g : Game
          g = updateCurrentLevel (const lvl') st.game
      in say ItemMsg (MonsterSlowsDown m.kind)
           ({ game := g } st)
applyWand WandDrainLife dir st =
  case beamTarget st.game dir of
    Nothing => say WarningMsg BeamFizzles st
    Just (_, m) =>
      let (dmg, rng') = roll 2 6 st.game.rng
          p = st.game.player
          p' : Player
          p' = { hp := min p.maxHp (p.hp + dmg) } p
          g : Game
          g = { rng := rng', player := p' } st.game
      in damageMonster m dmg DrainLife ({ game := g } st)
applyWand WandNothing dir st =
  say ItemMsg NothingHappens st
applyWand WandTeleportAway dir st =
  case beamTarget st.game dir of
    Nothing => say WarningMsg BeamFizzles st
    Just (_, m) => teleportMonster m st
applyWand WandTeleportTo dir st =
  teleportPlayer (say ItemMsg (Teleported st.game.player.pos) st)
applyWand WandCancellation dir st =
  case beamTarget st.game dir of
    Nothing => say WarningMsg BeamFizzles st
    Just (_, m) =>
      let lvl = currentLevel st.game
          lvl' : Level
          lvl' = updateMonster m.id
                   (\mm => { statuses := [], state := Chasing } mm) lvl
          g : Game
          g = updateCurrentLevel (const lvl') st.game
      in say ItemMsg (MonsterOrdinary m.kind)
           ({ game := g } st)

zap : ItemId -> Dir -> Step -> Step
zap iid dir st =
  case findPackItem st.game iid of
    Nothing => say WarningMsg NoSuchItem st
    Just it =>
      case it.kind of
        Wand k =>
          if it.charges <= 0
             then say WarningMsg WandSputters st
             else let shown = itemDisplayNameIn st.game it
                      g1 : Game
                      g1 = updateItem iid (\i => { charges := i.charges - 1 } i)
                             (addKnown (Wand k) st.game)
                      st1 = say ItemMsg (ZapWand shown)
                                    ({ game := g1 } st)
                  in consume (applyWand k dir st1)
        _ => say WarningMsg CannotZap st

throwPath : Game -> Dir -> List Coord
throwPath g d = go 1
  where
    delta' : Coord
    delta' = delta d

    at : Int32 -> Coord
    at n = MkCoord (g.player.pos.x + delta'.x * n)
                   (g.player.pos.y + delta'.y * n)

    go : Int32 -> List Coord
    go n =
      if n > 6
         then []
         else let c = at n
              in case tileAt (currentLevel g).tiles c of
                   Nothing => []
                   Just t => if walkable t then c :: go (n + 1) else []

throwLanding : Game -> List Coord -> (Coord, Maybe Monster)
throwLanding g = go g.player.pos
  where
    go : Coord -> List Coord -> (Coord, Maybe Monster)
    go prev [] = (prev, Nothing)
    go prev (c :: cs) =
      case monsterAt (currentLevel g) c of
        Just m => (prev, Just m)
        Nothing => go c cs

throwDamage : Player -> Item -> Rng -> (Int32, Rng)
throwDamage p it g =
  case it.kind of
    Weapon w =>
      let (dice, sides) = weaponDamage w
          (n, g') = roll dice sides g
      in (max 1 (n + it.enchant + strengthDamageBonus (effectiveStrength p)), g')
    _ =>
      let (n, g') = roll 1 2 g
      in (max 1 n, g')

throwItem : ItemId -> Dir -> Step -> Step
throwItem iid dir st =
  case findPackItem st.game iid of
    Nothing => say WarningMsg NoSuchItem st
    Just it =>
      let p = st.game.player
          equipped = p.wielded == Just iid || p.worn == Just iid
                     || p.leftRing == Just iid || p.rightRing == Just iid
      in if equipped
            then say WarningMsg TakeOffBeforeThrowing st
            else let (landing, targetM) =
                       throwLanding st.game (throwPath st.game dir)
                     isPotion = case it.kind of
                                  Potion _ => True
                                  _ => False
                     items' : List Item
                     items' = if isPotion
                                 then filter (\i => i.id /= iid) st.game.items
                                 else map (\i => if i.id == iid
                                                   then { location :=
                                                            OnFloor st.game.depth
                                                                    landing } i
                                                   else i)
                                          st.game.items
                     p' : Player
                     p' = { inventory := filter (/= iid) p.inventory } p
                     g0 : Game
                     g0 = { items := items', player := p' } st.game
                     message = ThrowItem (itemDisplayNameIn st.game it) isPotion
                     base = event (ItemDropped iid)
                              (say ItemMsg message ({ game := g0 } st))
                 in case targetM of
                      Nothing => consume base
                      Just m =>
                        let (dmg, rng') = throwDamage p it st.game.rng
                            g1 : Game
                            g1 = { rng := rng' } g0
                        in consume (damageMonster m dmg
                                      ThrownItem ({ game := g1 } base))

equipWeapon : Item -> Step -> Step
equipWeapon it st =
  let g0 : Game
      g0 = { player := { wielded := Just it.id } st.game.player } st.game
      g : Game
      g = addKnown it.kind (recomputeWeapon g0)
      message = if it.cursed
                   then WeaponWeldsToHand (itemName it.kind)
                   else WieldItem (itemDisplayNameIn g it)
  in event (ItemUsed it.id)
       (consume (say ItemMsg message ({ game := g } st)))

wield : ItemId -> Step -> Step
wield iid st =
  case findPackItem st.game iid of
    Nothing => say WarningMsg NoSuchItem st
    Just it =>
      case it.kind of
        Weapon _ =>
          if st.game.player.wielded == Just iid
             then say SystemMsg AlreadyWielding st
             else case st.game.player.wielded of
                    Just old =>
                      case findPackItem st.game old of
                        Just oldItem =>
                          if oldItem.cursed
                             then say WarningMsg WeaponWelded st
                             else equipWeapon it st
                        Nothing => equipWeapon it st
                    Nothing => equipWeapon it st
        _ => say WarningMsg CannotWield st

equipArmor : Item -> Step -> Step
equipArmor it st =
  let g0 : Game
      g0 = { player := { worn := Just it.id } st.game.player } st.game
      g : Game
      g = addKnown it.kind (recomputeArmor g0)
      message = if it.cursed
                   then ArmorTightens (itemName it.kind)
                   else WearArmor (itemDisplayNameIn g it)
  in event (ItemUsed it.id)
       (consume (say ItemMsg message ({ game := g } st)))

wear : ItemId -> Step -> Step
wear iid st =
  case findPackItem st.game iid of
    Nothing => say WarningMsg NoSuchItem st
    Just it =>
      case it.kind of
        Armor _ =>
          if st.game.player.worn == Just iid
             then say SystemMsg AlreadyWearingArmor st
             else case st.game.player.worn of
                    Just old =>
                      case findPackItem st.game old of
                        Just oldItem =>
                          if oldItem.cursed
                             then say WarningMsg CannotRemoveCursedArmor st
                             else equipArmor it st
                        Nothing => equipArmor it st
                    Nothing => equipArmor it st
        _ => say WarningMsg CannotWear st

takeOff : ItemId -> Step -> Step
takeOff iid st =
  let g = st.game
      p = g.player
      isRing = p.leftRing == Just iid || p.rightRing == Just iid
  in if p.worn == Just iid
        then case findPackItem g iid of
               Nothing => say WarningMsg NotWearingThat st
               Just it =>
                 if it.cursed
                    then say WarningMsg CannotRemoveCursedArmor st
                    else let p' : Player
                             p' = { worn := Nothing } p
                             g1 : Game
                             g1 = recomputeArmor ({ player := p' } g)
                         in event (ItemUsed iid)
                              (consume (say ItemMsg
                                (TakeOffItem (itemDisplayNameIn g1 it))
                                ({ game := g1 } st)))
        else if isRing
                then case findPackItem g iid of
                       Nothing => say WarningMsg NotWearingThat st
                       Just it =>
                         if it.cursed
                            then say WarningMsg CannotRemoveCursedRing st
                            else let p' : Player
                                     p' = { leftRing :=
                                              if p.leftRing == Just iid
                                                 then Nothing else p.leftRing
                                          , rightRing :=
                                              if p.rightRing == Just iid
                                                 then Nothing else p.rightRing
                                          } p
                                     g1 : Game
                                     g1 = recomputeRings ({ player := p' } g)
                                 in event (ItemUsed iid)
                                      (consume (say ItemMsg
                                        (TakeOffItem (itemDisplayNameIn g1 it))
                                        ({ game := g1 } st)))
                else say WarningMsg NotWearingThat st

dropItem : ItemId -> Step -> Step
dropItem iid st =
  case findPackItem st.game iid of
    Nothing => say WarningMsg NoSuchItem st
    Just it =>
      let p0 = st.game.player
          equipped = p0.wielded == Just iid || p0.worn == Just iid
                     || p0.leftRing == Just iid || p0.rightRing == Just iid
      in if equipped && it.cursed
            then say WarningMsg CannotLetGoCursed st
            else let p1 : Player
                     p1 = if p0.wielded == Just iid
                             then { wielded := Nothing } p0
                             else if p0.worn == Just iid
                                     then { worn := Nothing } p0
                                     else if p0.leftRing == Just iid
                                             then { leftRing := Nothing } p0
                                             else if p0.rightRing == Just iid
                                                     then { rightRing := Nothing }
                                                          p0
                                                     else p0
                     g1 : Game
                     g1 = recomputeRings (recomputeArmor
                            (recomputeWeapon ({ player := p1 } st.game)))
                     p2 : Player
                     p2 = { inventory := filter (/= iid) g1.player.inventory }
                            g1.player
                     items' : List Item
                     items' = map (\i => if i.id == iid
                                            then { location := OnFloor st.game.depth
                                                              st.game.player.pos } i
                                            else i)
                                  g1.items
                     g : Game
                     g = { player := p2, items := items' } g1
                 in event (ItemDropped iid)
                      (consume (say ItemMsg
                        (DropItem (itemDisplayNameIn g it))
                        ({ game := g } st)))

playerAction : Command -> Step -> Step
playerAction (Move d) st = playerMove d st
playerAction Wait st = consume st
playerAction Search st = searchArea st
playerAction PickUp st = pickUp st
playerAction (Quaff i) st = quaff i st
playerAction (Read i) st = read i st
playerAction (Eat i) st = eat i st
playerAction (Wield i) st = wield i st
playerAction (Wear i) st = wear i st
playerAction (PutOnRing i) st = putOnRing i st
playerAction (TakeOff i) st = takeOff i st
playerAction (Drop i) st = dropItem i st
playerAction (Throw i d) st = throwItem i d st
playerAction (Zap i d) st = zap i d st
playerAction Descend st = stairsAction Down st
playerAction Ascend st = stairsAction Up st

||| A monster may walk onto floor, corridors, stairs and closed doors.
||| Opening a closed door is resolved in `chase`; secret and locked doors
||| stay closed to monsters.
monsterPassable : Tile -> Bool
monsterPassable t = walkable t || t == Door Closed

free : Game -> Coord -> Coord -> Bool
free g from target =
  let lvl = currentLevel g
  in target /= from
     && inBounds target
     && (case tileAt lvl.tiles target of
           Just t => monsterPassable t
           Nothing => False)
     && target /= g.player.pos
     && isNothing (monsterAt lvl target)

stepToward : Game -> Coord -> Coord -> Maybe Coord
stepToward g from to =
  let dx = sign (to.x - from.x)
      dy = sign (to.y - from.y)
      direct = [MkCoord (from.x + dx) (from.y + dy),
                MkCoord (from.x + dx) from.y,
                MkCoord from.x (from.y + dy)]
      fallback = [MkCoord (from.x + ddx) (from.y + ddy)
                 | ddx <- [-1, 0, 1], ddy <- [-1, 0, 1],
                   not (ddx == 0 && ddy == 0)]
  in find (free g from) (nub (direct ++ fallback))

stealGold : Monster -> Step -> Step
stealGold m st =
  let g = st.game
      (amount, rng') = roll 1 10 g.rng
      stolen = min amount g.player.gold
      p' : Player
      p' = { gold := g.player.gold - stolen } g.player
      g1 : Game
      g1 = { rng := rng', player := p' } g
  in if stolen <= 0
        then say CombatMsg
               (MonsterFindsNoGold m.kind)
               ({ game := g1 } st)
        else say WarningMsg
               (MonsterSnatchesGold m.kind stolen)
               (teleportMonster m ({ game := g1 } st))

stealItem : Monster -> Step -> Step
stealItem m st =
  let g = st.game
      p = g.player
      equipped : Item -> Bool
      equipped i =
        p.wielded == Just i.id || p.worn == Just i.id
        || p.leftRing == Just i.id || p.rightRing == Just i.id
      candidates = filter (not . equipped) (packItems g)
      picked = pick candidates g.rng
      choice = fst picked
      rng' = snd picked
  in case choice of
       Nothing => say CombatMsg
                    (MonsterFindsNothing m.kind)
                    st
       Just it =>
         let p' : Player
             p' = { inventory := filter (/= it.id) p.inventory } p
             items' : List Item
             items' = map (\i => if i.id == it.id
                                    then { location := CarriedBy m.id } i
                                    else i) g.items
             g1 : Game
             g1 = { rng := rng', player := p', items := items' } g
         in say WarningMsg
              (MonsterSnatchesItem m.kind (itemDisplayNameIn g it))
              (teleportMonster m ({ game := g1 } st))

||| Apply the on-hit special ability of a monster.  Only one offensive
||| status/steal ability is expected per kind, but the order is fixed so
||| future kinds with several abilities stay deterministic.
monsterAbilityOnHit : Monster -> Step -> Step
monsterAbilityOnHit m st =
  if isJust st.game.over
     then st
     else if hasAbility Freeze m.kind
             then say WarningMsg
                    (MonsterFreezesYou m.kind)
                    (setPlayer (addStatus Held 3 st.game.player) st)
     else if hasAbility HoldingAttack m.kind
             then say WarningMsg
                    (MonsterHoldsYou m.kind)
                    (setPlayer (addStatus Held 3 st.game.player) st)
     else if hasAbility DrainLife m.kind
             then let (amount, rng') = roll 1 5 st.game.rng
                      p = st.game.player
                      maxHp' = max 1 (p.maxHp - amount)
                      p' : Player
                      p' = { maxHp := maxHp', hp := min p.hp maxHp' } p
                      g : Game
                      g = { rng := rng', player := p' } st.game
                  in say WarningMsg
                       (MonsterDrainsMaxHp m.kind amount)
                       ({ game := g } st)
     else if hasAbility DrainStrength m.kind
             then if hasRing RingSustainStrength st.game
                     then say WarningMsg
                            (MonsterTriesWeaken m.kind)
                            st
                     else let p = st.game.player
                              p' : Player
                              p' = { strength := max 0 (p.strength - 1) } p
                          in say WarningMsg
                               (MonsterWeakensYou m.kind)
                               (setPlayer p' st)
     else if hasAbility DrainExperience m.kind
             then let p = st.game.player
                      newLevel = max 1 (p.level - 1)
                      newMax = max 1 (p.maxHp - 1)
                      p' : Player
                      p' = { level := newLevel
                           , exp := min p.exp (expForLevel newLevel)
                           , maxHp := newMax
                           , hp := min p.hp newMax
                           } p
                  in say WarningMsg
                       (MonsterDrainsLifeForce m.kind)
                       (setPlayer p' st)
     else if hasAbility RustArmor m.kind
             then rustPlayerArmor (RustMonster m.kind) st
     else if hasAbility StealGold m.kind
             then stealGold m st
     else if hasAbility StealItem m.kind
             then stealItem m st
     else st

||| Apply ranged damage from a monster.  Used by arrows and by the
||| dragon's fire breath.
applyRangedHit : AttackLead -> Monster -> Int32 -> Game -> Step -> Step
applyRangedHit lead m dmg g1 st =
  let hp' = g1.player.hp - dmg
  in if hp' <= 0
       then let player' : Player
                player' = { hp := 0 } g1.player
                g2 : Game
                g2 = { player := player'
                     , over := Just (Dead (KilledBy m.kind))
                     } g1
            in event PlayerDied
                 (say WarningMsg
                   (Die True (KilledBy m.kind))
                   ({ game := g2 } st))
       else let player' : Player
                player' = { hp := hp' } g1.player
                g2 : Game
                g2 = { player := player' } g1
            in event (MonsterAttacked m.id dmg)
                 (say CombatMsg
                   (RangedHit lead dmg)
                   ({ game := g2 } st))

rangedStrike : Monster -> Step -> Step
rangedStrike m st =
  let g = st.game
  in if hasAbility FireBreath m.kind
       then let (dmg, rng') = roll 6 6 g.rng
                g1 : Game
                g1 = { rng := rng' } g
            in applyRangedHit
                 (BreathFire m.kind)
                 m dmg g1 st
       else let (result, rng') = monsterAttack g.player m g.rng
                g1 : Game
                g1 = { rng := rng' } g
                lead = ArrowFire m.kind
            in case result of
                 Miss =>
                   say CombatMsg (RangedMiss lead)
                       ({ game := g1 } st)
                 Hit dmg => applyRangedHit lead m dmg g1 st
                 Killed dmg => applyRangedHit lead m dmg g1 st

monsterStrike : Monster -> Step -> Step
monsterStrike m st =
  let g = st.game
      (result, rng') = monsterAttack g.player m g.rng
      g1 : Game
      g1 = { rng := rng' } g
  in case result of
       Miss =>
         say CombatMsg (MonsterMisses m.kind)
             ({ game := g1 } st)
       Hit dmg =>
         let hp' = g1.player.hp - dmg
             player' : Player
             player' = { hp := hp' } g1.player
             g2 : Game
             g2 = { player := player' } g1
         in event (MonsterAttacked m.id dmg)
              (monsterAbilityOnHit m
                (say CombatMsg
                  (MonsterHitsYou m.kind dmg)
                  ({ game := g2 } st)))
       Killed dmg =>
         let player' : Player
             player' = { hp := 0 } g1.player
             g2 : Game
             g2 = { player := player'
                  , over := Just (Dead (KilledBy m.kind))
                  } g1
         in event PlayerDied
              (say WarningMsg
                (Die True (KilledBy m.kind))
                ({ game := g2 } st))

neighborCells : Coord -> List Coord
neighborCells c = map (\d => add c (delta d)) directions

moveMonsterTo : Monster -> Coord -> Step -> Step
moveMonsterTo m target st =
  let lvl0 = currentLevel st.game
      opened = case tileAt lvl0.tiles target of
                 Just (Door Closed) => True
                 _ => False
      lvl1 : Level
      lvl1 = if opened
                then { tiles := setTile target (Door Open) lvl0.tiles } lvl0
                else lvl0
      lvl' : Level
      lvl' = updateMonster m.id (\mm => { pos := target } mm) lvl1
      g' : Game
      g' = updateCurrentLevel (const lvl') st.game
      st1 : Step
      st1 = if opened
               then say SystemMsg
                      (MonsterOpensDoor m.kind)
                      ({ game := g' } st)
               else { game := g' } st
  in event (MonsterMoved m.id target) st1

chase : Monster -> Step -> Step
chase m st =
  if adjacent m.pos st.game.player.pos
     then monsterStrike m st
     else case stepToward st.game m.pos st.game.player.pos of
            Nothing => st
            Just target => moveMonsterTo m target st

pickFarthest : Coord -> List Coord -> Maybe Coord
pickFarthest from [] = Nothing
pickFarthest from (c :: cs) =
  let best = pickFarthest from cs
  in case best of
       Nothing => Just c
       Just b => if chebyshev c from > chebyshev b from then Just c else Just b

flee : Monster -> Step -> Step
flee m st =
  let options = filter (free st.game m.pos) (neighborCells m.pos)
  in case pickFarthest st.game.player.pos options of
       Nothing => st
       Just target => moveMonsterTo m target st

randomMove : Monster -> Step -> Step
randomMove m st =
  let options = filter (free st.game m.pos) (neighborCells m.pos)
      (targetOpt, rng') = pick options st.game.rng
  in case targetOpt of
       Nothing => if adjacent m.pos st.game.player.pos
                     then monsterStrike m st
                     else st
       Just target =>
         let g : Game
             g = { rng := rng' } st.game
         in moveMonsterTo m target ({ game := g } st)

erraticAct : Monster -> Step -> Step
erraticAct m st =
  if adjacent m.pos st.game.player.pos
     then monsterStrike m st
     else randomMove m st

canRanged : Monster -> Game -> Bool
canRanged m g =
  let d = chebyshev m.pos g.player.pos
      dx = abs (m.pos.x - g.player.pos.x)
      dy = abs (m.pos.y - g.player.pos.y)
      aligned = dx == 0 || dy == 0 || dx == dy
  in d > 1 && d <= 6 && aligned
     && canSee (currentLevel g).tiles m.pos g.player.pos

rangedOrChase : Monster -> Step -> Step
rangedOrChase m st =
  if monsterHasStatus Confused m
     then randomMove m st
     else if hasAbility FireBreath m.kind && canRanged m st.game
             then let (fires, rng') = chance 20 st.game.rng
                      g : Game
                      g = { rng := rng' } st.game
                  in if fires
                        then rangedStrike m ({ game := g } st)
                        else chase m ({ game := g } st)
             else chase m st

goldPileCoords : Depth -> Game -> List Coord
goldPileCoords depth g =
  mapMaybe (\i => case i.location of
                    OnFloor d c => if i.kind == Gold && d == depth
                                      then Just c
                                      else Nothing
                    _ => Nothing)
           g.items

||| The nearest gold pile the monster can see.  Ties keep the earlier item
||| in `Game.items`, so the choice is deterministic.
nearestVisibleGold : Monster -> Game -> Maybe Coord
nearestVisibleGold m g =
  let lvl = currentLevel g
      seen = filter (\c => canSee lvl.tiles m.pos c) (goldPileCoords g.depth g)
      nearest : Maybe Coord -> List Coord -> Maybe Coord
      nearest best [] = best
      nearest Nothing (c :: cs) = nearest (Just c) cs
      nearest (Just b) (c :: cs) =
        if chebyshev c m.pos < chebyshev b m.pos
           then nearest (Just c) cs
           else nearest (Just b) cs
  in nearest Nothing seen

||| A greedy monster picks up the gold pile under its feet.
pickUpGold : Monster -> Step -> Step
pickUpGold m st =
  case find (\i => i.kind == Gold
                   && i.location == OnFloor st.game.depth m.pos)
            st.game.items of
    Nothing => st
    Just it =>
      let g' : Game
          g' = { items := map (\i => if i.id == it.id
                                       then { location := CarriedBy m.id } i
                                       else i)
                              st.game.items } st.game
      in { game := g' } st

||| `Greedy` monsters prefer visible gold over chasing the player.  They
||| attack an adjacent player first, then walk to the nearest gold pile and
||| carry it until they die.
greedyAct : Monster -> Step -> Step
greedyAct m st =
  if monsterHasStatus Confused m
     then randomMove m st
     else if adjacent m.pos st.game.player.pos
             then monsterStrike m st
             else case nearestVisibleGold m st.game of
                    Nothing => rangedOrChase m st
                    Just c =>
                      if c == m.pos
                         then pickUpGold m st
                         else case stepToward st.game m.pos c of
                                Nothing => rangedOrChase m st
                                Just target => moveMonsterTo m target st

monsterAct : Monster -> Step -> Step
monsterAct m st =
  if isJust st.game.over
     then st
     else if monsterHasStatus Held m || monsterHasStatus Slowed m
             || monsterHasStatus Paralyzed m || monsterHasStatus Sleeping m
             then st
     else if monsterHasStatus Scared m
             then flee m st
     else if hasStatus Invisible st.game.player
             && not (adjacent m.pos st.game.player.pos)
             then st
     else if (m.state == Awake || m.state == Chasing)
             && hasAbility Immobile m.kind
             then if adjacent m.pos st.game.player.pos
                     then monsterStrike m st
                     else st
     else if (m.state == Awake || m.state == Chasing)
             && hasAbility Erratic m.kind
             then erraticAct m st
     else if (m.state == Awake || m.state == Chasing)
             && hasAbility Greedy m.kind
             then greedyAct m st
     else case m.state of
            Asleep =>
              let lvl = currentLevel st.game
                  radius = if hasRing RingStealth st.game
                              then sightRadius `div` 2
                              else sightRadius
              in if chebyshev m.pos st.game.player.pos <= radius
                    && canSee lvl.tiles m.pos st.game.player.pos
                    then let lvl' : Level
                             lvl' = updateMonster m.id
                                      (\mm => { state := Chasing } mm) lvl
                             g' : Game
                             g' = updateCurrentLevel (const lvl') st.game
                         in if isMimicking m
                               then event (MonsterWoke m.id)
                                      ({ game := g' } st)
                               else event (MonsterWoke m.id)
                                      (say CombatMsg
                                        (MonsterWakesUp m.kind)
                                        ({ game := g' } st))
                    else st
            Fleeing =>
              let lvl = currentLevel st.game
                  lvl' : Level
                  lvl' = updateMonster m.id
                           (\mm => { state := Chasing } mm) lvl
                  g' : Game
                  g' = updateCurrentLevel (const lvl') st.game
              in chase m ({ game := g' } st)
            Awake => rangedOrChase m st
            Chasing => rangedOrChase m st

monsterTurn : Step -> Step
monsterTurn st =
  let ms = sortBy (\a, b => compare a.id b.id)
                  (currentLevel st.game).monsters
  in foldl act st ms
  where
    actedNow : Monster -> Step -> Step -> Bool
    actedNow before st1 st2 =
      let hpChanged = st2.game.player.hp /= st1.game.player.hp
          spoke = length st2.newMessages > length st1.newMessages
          moved = case monsterById before.id (currentLevel st2.game) of
                    Just after => after.pos /= before.pos
                    Nothing => False
      in hpChanged || spoke || moved

    revealIfActed : Monster -> Step -> Step -> Step
    revealIfActed before st1 st2 =
      if isMimicking before && actedNow before st1 st2
         then { game := revealMimic before.id st2.game } st2
         else st2

    act : Step -> Monster -> Step
    act acc m =
      if isJust acc.game.over
         then acc
         else let m' = tickMonsterStatuses m
                  m'' : Monster
                  m'' = if hasAbility Regenerate m'.kind
                           && m'.hp < m'.maxHp
                           then { hp := m'.hp + 1 } m'
                           else m'
                  lvl = currentLevel acc.game
                  lvl' : Level
                  lvl' = updateMonster m.id (const m'') lvl
                  acc1 : Step
                  acc1 = { game := updateCurrentLevel (const lvl') acc.game } acc
                  acc2 = revealIfActed m'' acc1 (monsterAct m'' acc1)
              in if (hasAbility Fast m''.kind
                     || monsterHasStatus Hasted m'')
                    && not (isJust acc2.game.over)
                    then case monsterById m.id (currentLevel acc2.game) of
                           Just m2 => revealIfActed m2 acc2
                                        (monsterAct m2 acc2)
                           Nothing => acc2
                    else acc2

||| Number of worn rings of the given kind, 0, 1 or 2.
countRing : RingKind -> Game -> Int32
countRing k g =
  let countOne : Maybe ItemId -> Int32 -> Int32
      countOne Nothing n = n
      countOne (Just iid) n =
        case find (\i => i.id == iid) g.items of
          Just i => if i.kind == Ring k then n + 1 else n
          Nothing => n
  in countOne g.player.rightRing (countOne g.player.leftRing 0)

||| Natural healing interval for levels 1-8, from the Rogue Vade-Mecum
||| experience table.  Levels 9+ heal 1d(level-7) every three turns.
healInterval : Int32 -> Int32
healInterval level =
  case level of
    1 => 18
    2 => 17
    3 => 15
    4 => 13
    5 => 11
    6 => 9
    7 => 7
    _ => 3

||| The heal daemon: one hit point per interval up to level 8, then
||| 1d(level-7) every three turns.  `quiet` counts consumed turns since
||| the player last lost HP; a healing event resets it.  No roll is made
||| at full health.
naturalHeal : Player -> Turn -> Rng -> (Int32, Turn, Rng)
naturalHeal p quiet rng =
  if p.hp >= p.maxHp
     then (0, quiet, rng)
     else if p.level <= 8
             then if quiet >= healInterval p.level
                     then (1, 0, rng)
                     else (0, quiet, rng)
             else if quiet >= 3
                     then let (n, rng') = roll 1 (min 14 (p.level - 7)) rng
                          in (n, 0, rng')
                     else (0, quiet, rng)

healAmount : Int32 -> Player -> Player
healAmount n p =
  if n <= 0 then p else { hp := min p.maxHp (p.hp + n) } p

||| Advance status timers, poison, natural healing and hunger after the
||| monster turn.  A ring of regeneration heals one HP per turn (two rings
||| heal two); a single ring of slow digestion halves hunger, and two stop
||| it completely.
survivalTurn : Step -> Step
survivalTurn st =
  let r = tickSurvival st.game.player
      g1 : Game
      g1 = { player := r.player } st.game
      st1 : Step
      st1 = foldl (\s, text => say WarningMsg text s)
                  ({ game := g1 } st) r.messages
  in case r.died of
       Just cause =>
         let p : Player
             p = { hp := 0 } r.player
             g2 : Game
             g2 = { player := p, over := Just (Dead cause) } g1
         in event PlayerDied
              (say WarningMsg (Die False cause)
                ({ game := g2 } st1))
       Nothing =>
         let p0 = g1.player
             damaged = p0.hp < st.game.player.hp
             quiet0 : Turn
             quiet0 = if damaged then 0 else st.game.quietTurns + 1
             p1 : Player
             p1 = healAmount (countRing RingRegeneration g1) p0
             healRoll = naturalHeal p1 quiet0 g1.rng
             natHeal = fst healRoll
             quiet1 = fst (snd healRoll)
             rng1 = snd (snd healRoll)
             p2 : Player
             p2 = healAmount natHeal p1
             slowRings = countRing RingSlowDigestion g1
             digestRecovery : Int32
             digestRecovery =
               if slowRings >= 2 then 1
               else if slowRings == 1 && g1.turn `mod` 2 == 0 then 1
               else 0
             p3 : Player
             p3 = if digestRecovery > 0
                     then { hunger := min hungerMax (p2.hunger + digestRecovery) } p2
                     else p2
             g2 : Game
             g2 = { player := p3, rng := rng1, quietTurns := quiet1 } g1
             teleportRoll = if hasRing RingTeleportation g2
                               then chance 2 g2.rng
                               else (False, g2.rng)
             teleport = fst teleportRoll
             rng' = snd teleportRoll
             g3 : Game
             g3 = { rng := rng' } g2
             st2 : Step
             st2 = { game := g3 } st1
         in if teleport
               then teleportPlayer
                      (say ItemMsg RingHums st2)
               else st2

isMoveCommand : Command -> Bool
isMoveCommand (Move _) = True
isMoveCommand _ = False

ringSearch : Nat -> Step -> Step
ringSearch Z st = st
ringSearch (S k) st =
  let (st1, _) = searchDoors st
      (st2, _) = searchTraps st1
  in ringSearch k st2

||| A ring of searching performs a free search after each successful move,
||| once per worn ring, as in 5.4.4's `domove`.
ringSearchAfterMove : Step -> Step
ringSearchAfterMove st =
  if isJust st.game.over
     then st
     else ringSearch (cast (countRing RingSearching st.game)) st

advanceTurn : Step -> Step
advanceTurn st =
  let g = st.game
      g' : Game
      g' = { turn := g.turn + 1 } g
  in { game := g' } st

refresh : Step -> Step
refresh st =
  let g = st.game
      lvl = currentLevel g
      vis = if hasStatus Blinded g.player
               then computeBlinded lvl.tiles lvl.rooms g.player.pos
               else compute lvl.tiles lvl.rooms g.player.pos
      explored = union lvl.explored vis
      lvl' : Level
      lvl' = { explored := explored } lvl
      g1 : Game
      g1 = updateCurrentLevel (const lvl') g
      g2 : Game
      g2 = { visible := vis } g1
  in { game := g2 } st

public export
step : Command -> Game -> Outcome
step cmd g =
  case g.over of
    Just _ => MkOutcome g [] [] False
    Nothing =>
      let st0 = MkStep g [] [] False
          incapacitated = hasStatus Sleeping g.player
                          || hasStatus Paralyzed g.player
          st1 = if incapacitated
                   then consume (say WarningMsg
                          (if hasStatus Sleeping g.player
                              then YouAreAsleep
                              else YouAreParalyzed) st0)
                   else playerAction cmd st0
          changed = st1.game.depth /= g.depth
          moved = st1.game.player.pos /= g.player.pos || changed
          st2 = if st1.consumed
                   then let st2a0 = advanceTurn st1
                            st2a = if isMoveCommand cmd && moved && not changed
                                      then ringSearchAfterMove st2a0
                                      else st2a0
                            monstersAct =
                              not (hasStatus Hasted st2a.game.player
                                   && st2a.game.turn `mod` 2 == 0)
                            st2b = if changed || not monstersAct
                                      then st2a
                                      else monsterTurn st2a
                            st2c = if isJust st2b.game.over
                                      then st2b
                                      else survivalTurn st2b
                        in refresh st2c
                   else st1
      in MkOutcome st2.game (reverse st2.newMessages) (reverse st2.events)
                   st2.consumed
