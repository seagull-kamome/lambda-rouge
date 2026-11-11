||| Presentation-only effects derived from Core events.
|||
||| An animation is a short-lived glyph painted over the map after a step.
||| It never changes the game, the RNG, the turn or the replay: the effects
||| are built from `Outcome.events` and aged by timer ticks in the App.
module LambdaRogue.UI.Animation

import Data.List
import Data.Maybe
import LambdaRogue.Core.Game
import LambdaRogue.Core.Geometry
import LambdaRogue.Core.Types
import LambdaRogue.UI.Theme

%default covering

||| How fast effect ticks advance.  This is presentation only; the game,
||| RNG, turn count and replay are untouched.  Slow gives effects a longer
||| visible life, fast shortens it.
public export
data AnimationSpeed = SlowAnimation | NormalAnimation | FastAnimation

public export
Eq AnimationSpeed where
  SlowAnimation == SlowAnimation = True
  NormalAnimation == NormalAnimation = True
  FastAnimation == FastAnimation = True
  _ == _ = False

public export
Show AnimationSpeed where
  show SlowAnimation = "slow"
  show NormalAnimation = "normal"
  show FastAnimation = "fast"

public export
animationSpeedId : AnimationSpeed -> String
animationSpeedId SlowAnimation = "slow"
animationSpeedId NormalAnimation = "normal"
animationSpeedId FastAnimation = "fast"

public export
animationSpeedFromId : String -> Maybe AnimationSpeed
animationSpeedFromId "slow" = Just SlowAnimation
animationSpeedFromId "normal" = Just NormalAnimation
animationSpeedFromId "fast" = Just FastAnimation
animationSpeedFromId _ = Nothing

||| Milliseconds between effect ticks.
public export
animationDelay : AnimationSpeed -> Nat
animationDelay SlowAnimation = 32
animationDelay NormalAnimation = 16
animationDelay FastAnimation = 8

public export
nextAnimationSpeed : AnimationSpeed -> AnimationSpeed
nextAnimationSpeed SlowAnimation = NormalAnimation
nextAnimationSpeed NormalAnimation = FastAnimation
nextAnimationSpeed FastAnimation = SlowAnimation

||| The kinds of short effects the map can show.  The glyph and style are
||| presentation decisions; the kind only carries what happened.
public export
data EffectKind
  = Trail
  | Impact
  | Damage Int32
  | Death
  | Pickup
  | DoorMark
  | TrapMark
  | LevelUpMark
  | Victory

public export
Eq EffectKind where
  Trail == Trail = True
  Impact == Impact = True
  Damage a == Damage b = a == b
  Death == Death = True
  Pickup == Pickup = True
  DoorMark == DoorMark = True
  TrapMark == TrapMark = True
  LevelUpMark == LevelUpMark = True
  Victory == Victory = True
  _ == _ = False

public export
Show EffectKind where
  show Trail = "trail"
  show Impact = "impact"
  show (Damage d) = "damage " ++ show d
  show Death = "death"
  show Pickup = "pickup"
  show DoorMark = "door"
  show TrapMark = "trap"
  show LevelUpMark = "level-up"
  show Victory = "victory"

||| One effect on the map.  `age` is counted in fixed 16 ms ticks, so the
||| animation is deterministic and does not read a clock or consume RNG.
public export
record Effect where
  constructor MkEffect
  kind : EffectKind
  pos : Coord
  age : Nat
  life : Nat

public export
Eq Effect where
  a == b = a.kind == b.kind && a.pos == b.pos
           && a.age == b.age && a.life == b.life

lifeOf : EffectKind -> Nat
lifeOf Trail = 4
lifeOf Impact = 4
lifeOf (Damage _) = 12
lifeOf Death = 8
lifeOf Pickup = 4
lifeOf DoorMark = 4
lifeOf TrapMark = 8
lifeOf LevelUpMark = 10
lifeOf Victory = 16

glyphOf : EffectKind -> String
glyphOf Trail = "."
glyphOf Impact = "*"
glyphOf (Damage d) = show d
glyphOf Death = "%"
glyphOf Pickup = ","
glyphOf DoorMark = "+"
glyphOf TrapMark = "^"
glyphOf LevelUpMark = "!"
glyphOf Victory = "*"

roleOf : EffectKind -> StyleRole
roleOf Trail = DimCellRole
roleOf Impact = TitleRole
roleOf (Damage _) = DangerRole
roleOf Death = DangerRole
roleOf Pickup = ItemRole
roleOf DoorMark = DoorRole
roleOf TrapMark = TrapRole
roleOf LevelUpMark = TitleRole
roleOf Victory = TitleRole

public export
mkEffect : EffectKind -> Coord -> Effect
mkEffect kind pos = MkEffect kind pos 0 (lifeOf kind)

||| Advance one tick and drop finished effects.
public export
advanceAnimations : List Effect -> List Effect
advanceAnimations es =
  filter (\e => e.age < e.life) (map (\e => { age := S e.age } e) es)

||| Keep the newest effects first.  The cap bounds the overlay when a single
||| step produces many events, such as a pack of monsters waking.
public export
mergeAnimations : List Effect -> List Effect -> List Effect
mergeAnimations fresh old = take 24 (fresh ++ old)

monsterIn : Game -> MonsterId -> Maybe Monster
monsterIn g i = find (\m => m.id == i) (currentLevel g).monsters

itemIn : Game -> ItemId -> Maybe Item
itemIn g i = find (\it => it.id == i) g.items

itemPos : Item -> Maybe Coord
itemPos i =
  case i.location of
    OnFloor _ p => Just p
    _ => Nothing

effectFor : Game -> Game -> Event -> Maybe Effect
effectFor before after e =
  case e of
    PlayerMoved _ => Just (mkEffect Trail before.player.pos)
    MonsterMoved id _ =>
      map (\m => mkEffect Trail m.pos) (monsterIn before id)
    PlayerAttacked id dmg =>
      map (\m => mkEffect (if dmg <= 0 then Impact else Damage dmg) m.pos)
          (monsterIn before id)
    MonsterAttacked _ dmg =>
      if dmg <= 0 then Nothing else Just (mkEffect (Damage dmg) before.player.pos)
    MonsterWoke _ => Nothing
    MonsterDied id =>
      map (\m => mkEffect Death m.pos) (monsterIn before id)
    ItemPicked id =>
      map (\c => mkEffect Pickup c) (itemPos =<< itemIn before id)
    ItemUsed _ => Nothing
    ItemDropped id =>
      map (\c => mkEffect Pickup c) (itemPos =<< itemIn after id)
    DoorOpened c => Just (mkEffect DoorMark c)
    TrapTriggered _ c => Just (mkEffect TrapMark c)
    LevelChanged _ => Nothing
    PlayerLevelUp _ => Just (mkEffect LevelUpMark after.player.pos)
    PlayerDied => Just (mkEffect Death after.player.pos)
    PlayerWon => Just (mkEffect Victory after.player.pos)

||| Every event that has a useful visual effect.  The old game supplies the
||| position before the step (a trail, a killed monster) and the new game
||| supplies positions after it (a dropped item, the player's death).
public export
effectsFor : Game -> Game -> List Event -> List Effect
effectsFor before after events = mapMaybe (effectFor before after) events

||| Cells to paint over the map, row-major per effect.  The list is returned
||| oldest-first so a newer effect wins when two share a cell.
public export
effectCells : List Effect -> List (Int32, Int32, Char, StyleRole)
effectCells es = concatMap cells (reverse es)
  where
    indexed : List Char -> List (Int32, Char)
    indexed cs = go 0 cs
      where
        go : Int32 -> List Char -> List (Int32, Char)
        go _ [] = []
        go n (c :: rest) = (n, c) :: go (n + 1) rest

    cells : Effect -> List (Int32, Int32, Char, StyleRole)
    cells e =
      if e.pos.y < 0 || e.pos.y >= 22
         then []
         else mapMaybe place (indexed (unpack (glyphOf e.kind)))
      where
        place : (Int32, Char) -> Maybe (Int32, Int32, Char, StyleRole)
        place (dx, c) =
          let x = e.pos.x + dx
          in if x >= 0 && x < 80
                then Just (x, e.pos.y, c, roleOf e.kind)
                else Nothing
