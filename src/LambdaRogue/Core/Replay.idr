||| Deterministic command replays and state digests.
|||
||| A replay is just the starting seed and the semantic `Command` values
||| the player issued, newest first.  Running it from `newGame seed` must
||| reproduce the same `Game` state; `gameDigest` gives a compact value
||| for that comparison without needing `Eq Game`.
|||
||| The digest deliberately ignores `Game.messages`: those are
||| presentation history, and a replay may be checked after the log has
||| been trimmed.  Everything that affects future play is included.
module LambdaRogue.Core.Replay

import Data.Bits
import Data.List
import Data.Vect
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types
import Text.NumberFormat

%default covering

public export
record Replay where
  constructor MkReplay
  seed : Bits64
  commands : List Command

||| A replay with no commands, ready for the first turn.
public export
emptyReplay : Bits64 -> Replay
emptyReplay s = MkReplay s []

||| Record one semantic command.  The newest command is kept at the head
||| so recording is O(1); `replayCommands` restores play order.
public export
recordCommand : Command -> Replay -> Replay
recordCommand c r = { commands := c :: r.commands } r

public export
replayCommands : Replay -> List Command
replayCommands r = reverse r.commands

||| Re-run the whole game from its seed.
public export
runReplay : Replay -> Game
runReplay r =
  foldl (\g, c => (step c g).game) (newGame r.seed) (replayCommands r)

-- Canonical state encoding -------------------------------------------------
--
-- The digest is FNV-1a over a deterministic textual encoding.  It is not
-- a cryptographic hash; it only has to notice a replay diverging from
-- the recorded run.

fnvOffset : Bits64
fnvOffset = 0xcbf29ce484222325

fnvPrime : Bits64
fnvPrime = 0x100000001b3

hashStep : Bits64 -> Char -> Bits64
hashStep h c = (h `xor` the Bits64 (cast (ord c))) * fnvPrime

listCode : (a -> String) -> List a -> String
listCode f xs = "[" ++ concatMap (\x => f x ++ ";") xs ++ "]"

maybeCode : (a -> String) -> Maybe a -> String
maybeCode f Nothing = "-"
maybeCode f (Just x) = f x

bitsetCode : Bitset -> String
bitsetCode bs = concatMap toHex (toList bs)

statusCode : Status -> String
statusCode s = show s.statusKind ++ ":" ++ show s.remaining

playerCode : Player -> String
playerCode p =
  show p.pos
  ++ "|hp:" ++ show p.hp ++ "/" ++ show p.maxHp
  ++ "|str:" ++ show p.strength ++ "/" ++ show p.maxStrength
  ++ "|ac:" ++ show p.armor
  ++ "|lv:" ++ show p.level ++ "|exp:" ++ show p.exp
  ++ "|gold:" ++ show p.gold ++ "|food:" ++ show p.hunger
  ++ "|inv:" ++ listCode (\i => show i) p.inventory
  ++ "|w:" ++ maybeCode (\i => show i) p.wielded
  ++ "|a:" ++ maybeCode (\i => show i) p.worn
  ++ "|lr:" ++ maybeCode (\i => show i) p.leftRing
  ++ "|rr:" ++ maybeCode (\i => show i) p.rightRing
  ++ "|wd:" ++ show p.weaponDice ++ "/" ++ show p.weaponSides
  ++ "/" ++ show p.weaponBonus
  ++ "|ring:" ++ show p.ringArmor ++ "/" ++ show p.ringDamage
  ++ "/" ++ show p.ringAccuracy ++ "/" ++ show p.ringStrength
  ++ "|st:" ++ listCode statusCode p.statuses

monsterCode : Monster -> String
monsterCode m =
  show m.id ++ ":" ++ show m.kind ++ ":" ++ show m.pos
  ++ ":" ++ show m.hp ++ "/" ++ show m.maxHp
  ++ ":" ++ show m.state ++ ":" ++ listCode statusCode m.statuses

itemCode : Item -> String
itemCode i =
  show i.id ++ ":" ++ show i.kind ++ ":" ++ show i.location
  ++ ":" ++ show i.count ++ ":" ++ show i.enchant
  ++ ":" ++ show i.cursed ++ ":" ++ show i.charges
  ++ ":" ++ show i.protected

trapCode : Trap -> String
trapCode t = show t.pos ++ ":" ++ show t.kind ++ ":" ++ show t.revealed

roomCode : Room -> String
roomCode r =
  show r.x ++ ":" ++ show r.y ++ ":" ++ show r.w ++ ":" ++ show r.h
  ++ ":" ++ show r.dark

levelCode : Level -> String
levelCode l =
  show l.depth
  ++ "|tiles:" ++ show l.tiles
  ++ "|seen:" ++ bitsetCode l.explored
  ++ "|rooms:" ++ listCode roomCode l.rooms
  ++ "|mon:" ++ listCode monsterCode l.monsters
  ++ "|traps:" ++ listCode trapCode l.traps
  ++ "|up:" ++ maybeCode (\c => show c) l.upStairs
  ++ "|down:" ++ maybeCode (\c => show c) l.downStairs

gameOverCode : GameOver -> String
gameOverCode Won = "Won"
gameOverCode (Dead c) = "Dead:" ++ show c

appearanceCode : (ItemKind, String) -> String
appearanceCode (k, name) = show k ++ "=" ++ name

gameCode : Game -> String
gameCode g =
  toHex g.seed
  ++ "|rng:" ++ stateHex g.rng
  ++ "|turn:" ++ show g.turn
  ++ "|depth:" ++ show g.depth
  ++ "|player:" ++ playerCode g.player
  ++ "|levels:" ++ listCode levelCode g.levels
  ++ "|items:" ++ listCode itemCode g.items
  ++ "|next:" ++ show g.nextMonsterId ++ "/" ++ show g.nextItemId
  ++ "|known:" ++ listCode (\k => show k) g.knownKinds
  ++ "|appearance:" ++ listCode appearanceCode g.appearances
  ++ "|over:" ++ maybeCode gameOverCode g.over
  ++ "|visible:" ++ bitsetCode g.visible

||| A 16-character lowercase hexadecimal digest of the gameplay state.
public export
gameDigest : Game -> String
gameDigest g = toHex (foldl hashStep fnvOffset (unpack (gameCode g)))

||| True when re-running the replay produces the same state as `g`.
public export
replayMatches : Replay -> Game -> Bool
replayMatches r g = gameDigest (runReplay r) == gameDigest g
