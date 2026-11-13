||| `lambda-rogue.save.v1` snapshots for manual saves and crash recovery.
|||
||| The save is a complete `Game` snapshot: seed, RNG state, turn, depth,
||| player, every visited level, every item, knowledge and the current log.
||| Decoding validates the whole file before returning a `Game`; a damaged
||| save is rejected rather than partially applied.
|||
||| Writes use a temporary file in the same directory, `fsync`, a `.bak`
||| rename for the previous file and a final rename.  A crash therefore
||| leaves either the old save or the new save, never half of both.
module LambdaRogue.Persist.Save

import Data.Bits
import Data.List
import Data.Maybe
import Data.String
import Data.String.RC2
import Data.Vect
import Language.JSON
import LambdaRogue.Core.Bitset
import LambdaRogue.Core.Monster
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types
import LambdaRogue.Persist.Codec
import LambdaRogue.Persist.Json
import LambdaRogue.Persist.Paths
import LambdaRogue.Version
import System.File.ReadWrite as File
import System.Posix.Errno
import System.Posix.File as Posix
import System.Posix.FileDesc as FD
import System.Posix.Process as Process
import System.Posix.Stdio as Stdio
import System.Posix.Time as Time
import Text.NumberFormat

%default covering

public export
saveFileSchema : String
saveFileSchema = "lambda-rogue.save.v1"

public export
data SaveKind = Manual | Autosave

public export
Eq SaveKind where
  Manual == Manual = True
  Autosave == Autosave = True
  _ == _ = False

public export
Show SaveKind where
  show Manual = "manual"
  show Autosave = "autosave"

public export
saveKindFromText : String -> Maybe SaveKind
saveKindFromText "manual" = Just Manual
saveKindFromText "autosave" = Just Autosave
saveKindFromText _ = Nothing

public export
record SaveFile where
  constructor MkSaveFile
  kind : SaveKind
  savedAt : String
  game : Game

-- Small JSON helpers -------------------------------------------------------

maybeIdToJSON : Maybe Bits32 -> JSON
maybeIdToJSON Nothing = JNull
maybeIdToJSON (Just i) = jsonBits32 i

maybeIdFromJSON : JSON -> Maybe (Maybe Bits32)
maybeIdFromJSON JNull = Just Nothing
maybeIdFromJSON j = Just <$> asBits32 j

maybeCoordToJSON : Maybe Coord -> JSON
maybeCoordToJSON Nothing = JNull
maybeCoordToJSON (Just c) = coordToJSON c

maybeCoordFromJSON : JSON -> Maybe (Maybe Coord)
maybeCoordFromJSON JNull = Just Nothing
maybeCoordFromJSON j = Just <$> coordFromJSON j

-- Items --------------------------------------------------------------------

locationToJSON : ItemLocation -> JSON
locationToJSON (OnFloor d p) =
  JObject [ ("kind", JString "floor")
          , ("depth", jsonInt d)
          , ("x", jsonInt p.x)
          , ("y", jsonInt p.y)
          ]
locationToJSON InPack = JObject [("kind", JString "pack")]
locationToJSON (CarriedBy m) =
  JObject [("kind", JString "monster"), ("monster", jsonBits32 m)]

locationFromJSON : JSON -> Maybe ItemLocation
locationFromJSON j = do
  kind <- field "kind" j >>= asString
  case kind of
    "floor" => do
      d <- field "depth" j >>= asInt32
      p <- coordFromJSON j
      pure (OnFloor d p)
    "pack" => Just InPack
    "monster" => CarriedBy <$> (field "monster" j >>= asBits32)
    _ => Nothing

public export
itemToJSON : Item -> JSON
itemToJSON i =
  JObject
    [ ("id", jsonBits32 i.id)
    , ("kind", JString (itemKindText i.kind))
    , ("location", locationToJSON i.location)
    , ("count", jsonInt i.count)
    , ("enchant", jsonInt i.enchant)
    , ("cursed", JBoolean i.cursed)
    , ("charges", jsonInt i.charges)
    , ("protected", JBoolean i.protected)
    ]

public export
itemFromJSON : JSON -> Maybe Item
itemFromJSON j = do
  iid <- field "id" j >>= asBits32
  kind <- field "kind" j >>= asString >>= itemKindFromText
  loc <- field "location" j >>= locationFromJSON
  count <- field "count" j >>= asInt32
  enchant <- field "enchant" j >>= asInt32
  cursed <- field "cursed" j >>= asBool
  charges <- field "charges" j >>= asInt32
  protected <- field "protected" j >>= asBool
  pure (MkItem iid kind loc count enchant cursed charges protected)

-- Monsters, traps, rooms and levels ---------------------------------------

monsterToJSON : Monster -> JSON
monsterToJSON m =
  JObject
    [ ("id", jsonBits32 m.id)
    , ("kind", JString (monsterKindText m.kind))
    , ("pos", coordToJSON m.pos)
    , ("hp", jsonInt m.hp)
    , ("maxHp", jsonInt m.maxHp)
    , ("state", JString (monsterStateText m.state))
    , ("statuses", statusesToJSON m.statuses)
    ]

monsterFromJSON : JSON -> Maybe Monster
monsterFromJSON j = do
  mid <- field "id" j >>= asBits32
  kind <- field "kind" j >>= asString >>= monsterKindFromText
  pos <- field "pos" j >>= coordFromJSON
  hp <- field "hp" j >>= asInt32
  maxHp <- field "maxHp" j >>= asInt32
  state <- field "state" j >>= asString >>= monsterStateFromText
  statuses <- field "statuses" j >>= statusesFromJSON
  pure (MkMonster mid kind pos hp maxHp state statuses)

trapToJSON : Trap -> JSON
trapToJSON t =
  JObject
    [ ("pos", coordToJSON t.pos)
    , ("kind", JString (trapKindText t.kind))
    , ("revealed", JBoolean t.revealed)
    ]

trapFromJSON : JSON -> Maybe Trap
trapFromJSON j = do
  pos <- field "pos" j >>= coordFromJSON
  kind <- field "kind" j >>= asString >>= trapKindFromText
  revealed <- field "revealed" j >>= asBool
  pure (MkTrap pos kind revealed)

roomToJSON : Room -> JSON
roomToJSON r =
  JObject
    [ ("x", jsonInt r.x), ("y", jsonInt r.y)
    , ("w", jsonInt r.w), ("h", jsonInt r.h)
    , ("dark", JBoolean r.dark)
    ]

roomFromJSON : JSON -> Maybe Room
roomFromJSON j = do
  x <- field "x" j >>= asInt32
  y <- field "y" j >>= asInt32
  w <- field "w" j >>= asInt32
  h <- field "h" j >>= asInt32
  dark <- field "dark" j >>= asBool
  pure (MkRoom x y w h dark)

rowText : Vect 80 Tile -> String
rowText = pack . map tileText . toList

rowFromText : String -> Maybe (Vect 80 Tile)
rowFromText s = traverse tileFromText (unpack s) >>= toVect 80

gridToJSON : Grid -> JSON
gridToJSON g = JArray (map (JString . rowText) (toList g))

gridFromJSON : JSON -> Maybe Grid
gridFromJSON j = do
  rows <- asArray j >>= traverse asString
  vect <- traverse rowFromText rows
  toVect 22 vect

bitsetHex : Bitset -> String
bitsetHex = concatMap toHex . toList

levelToJSON : Level -> JSON
levelToJSON l =
  JObject
    [ ("depth", jsonInt l.depth)
    , ("tiles", gridToJSON l.tiles)
    , ("explored", JString (bitsetHex l.explored))
    , ("rooms", JArray (map roomToJSON l.rooms))
    , ("monsters", JArray (map monsterToJSON l.monsters))
    , ("traps", JArray (map trapToJSON l.traps))
    , ("upStairs", maybeCoordToJSON l.upStairs)
    , ("downStairs", maybeCoordToJSON l.downStairs)
    ]

levelFromJSON : JSON -> Maybe Level
levelFromJSON j = do
  d <- field "depth" j >>= asInt32
  tiles <- field "tiles" j >>= gridFromJSON
  explored <- field "explored" j >>= asString >>= fromHex
  rooms <- field "rooms" j >>= arrayOf roomFromJSON
  monsters <- field "monsters" j >>= arrayOf monsterFromJSON
  traps <- field "traps" j >>= arrayOf trapFromJSON
  up <- field "upStairs" j >>= maybeCoordFromJSON
  down <- field "downStairs" j >>= maybeCoordFromJSON
  pure (MkLevel d tiles explored rooms monsters traps up down)

-- Player and messages -----------------------------------------------------

playerToJSON : Player -> JSON
playerToJSON p =
  JObject
    [ ("pos", coordToJSON p.pos)
    , ("hp", jsonInt p.hp)
    , ("maxHp", jsonInt p.maxHp)
    , ("strength", jsonInt p.strength)
    , ("maxStrength", jsonInt p.maxStrength)
    , ("armor", jsonInt p.armor)
    , ("level", jsonInt p.level)
    , ("exp", jsonInt p.exp)
    , ("gold", jsonInt p.gold)
    , ("hunger", jsonInt p.hunger)
    , ("inventory", JArray (map jsonBits32 p.inventory))
    , ("wielded", maybeIdToJSON p.wielded)
    , ("worn", maybeIdToJSON p.worn)
    , ("leftRing", maybeIdToJSON p.leftRing)
    , ("rightRing", maybeIdToJSON p.rightRing)
    , ("weaponDice", jsonInt p.weaponDice)
    , ("weaponSides", jsonInt p.weaponSides)
    , ("weaponBonus", jsonInt p.weaponBonus)
    , ("ringArmor", jsonInt p.ringArmor)
    , ("ringDamage", jsonInt p.ringDamage)
    , ("ringAccuracy", jsonInt p.ringAccuracy)
    , ("ringStrength", jsonInt p.ringStrength)
    , ("statuses", statusesToJSON p.statuses)
    ]

playerFromJSON : JSON -> Maybe Player
playerFromJSON j = do
  pos <- field "pos" j >>= coordFromJSON
  hp <- field "hp" j >>= asInt32
  maxHp <- field "maxHp" j >>= asInt32
  strength <- field "strength" j >>= asInt32
  maxStrength <- field "maxStrength" j >>= asInt32
  armor <- field "armor" j >>= asInt32
  level <- field "level" j >>= asInt32
  exp <- field "exp" j >>= asInt32
  gold <- field "gold" j >>= asInt32
  hunger <- field "hunger" j >>= asInt32
  inventory <- field "inventory" j >>= arrayOf asBits32
  wielded <- field "wielded" j >>= maybeIdFromJSON
  worn <- field "worn" j >>= maybeIdFromJSON
  leftRing <- field "leftRing" j >>= maybeIdFromJSON
  rightRing <- field "rightRing" j >>= maybeIdFromJSON
  weaponDice <- field "weaponDice" j >>= asInt32
  weaponSides <- field "weaponSides" j >>= asInt32
  weaponBonus <- field "weaponBonus" j >>= asInt32
  ringArmor <- field "ringArmor" j >>= asInt32
  ringDamage <- field "ringDamage" j >>= asInt32
  ringAccuracy <- field "ringAccuracy" j >>= asInt32
  ringStrength <- field "ringStrength" j >>= asInt32
  statuses <- field "statuses" j >>= statusesFromJSON
  pure (MkPlayer pos hp maxHp strength maxStrength armor level exp gold
                  hunger inventory wielded worn leftRing rightRing
                  weaponDice weaponSides weaponBonus
                  ringArmor ringDamage ringAccuracy ringStrength statuses)

messageToJSON : Message -> JSON
messageToJSON m =
  JObject
    [ ("turn", jsonInt m.turn)
    , ("kind", JString (messageKindText m.kind))
    , ("key", JString m.key)
    , ("args", JArray (map JString m.args))
    , ("text", JString m.text)
    ]

||| `key` and `args` are optional so saves written before the message
||| catalog still load.  Those messages keep `key = ""` and always render
||| their stored English `text`.
messageFromJSON : JSON -> Maybe Message
messageFromJSON j = do
  turn <- field "turn" j >>= asInt32
  kind <- field "kind" j >>= asString >>= messageKindFromText
  text <- field "text" j >>= asString
  key <- optionalString "key" j
  args <- optionalStrings "args" j
  pure (MkMessage turn kind key args text)
  where
    optionalString : String -> JSON -> Maybe String
    optionalString name obj =
      case field name obj of
        Nothing => Just ""
        Just (JString value) => Just value
        Just _ => Nothing
    optionalStrings : String -> JSON -> Maybe (List String)
    optionalStrings name obj =
      case field name obj of
        Nothing => Just []
        Just value => arrayOf asString value

-- Validation ---------------------------------------------------------------

maxOf : List Bits32 -> Bits32
maxOf = foldl max 0

ids : List Item -> List Bits32
ids = map (.id)

monsterIds : List Level -> List Bits32
monsterIds ls = concatMap (map (.id) . monsters) ls

validStatuses : List Status -> Bool
validStatuses ss =
  length (nub (map (.statusKind) ss)) == length ss
  && all (\s => s.remaining >= 0) ss

validPlayer : Game -> Bool
validPlayer g =
  let p = g.player
      packIds = map (.id) (filter (\i => i.location == InPack) g.items)
      inPack = \i => elem i packIds
      equipped : List (Maybe Bits32)
      equipped = [p.wielded, p.worn, p.leftRing, p.rightRing]
  in p.hp >= 0 && p.hp <= p.maxHp
     && p.strength >= 0 && p.strength <= p.maxStrength
     && p.gold >= 0 && p.hunger >= 0
     && p.level >= 1 && p.exp >= 0
     && length p.inventory <= maxPack
     && length (nub p.inventory) == length p.inventory
     && all inPack p.inventory
     && all (\m => maybe True inPack m) equipped
     && validStatuses p.statuses
     && not (any (\s => s.statusKind == Mimicking) p.statuses)

validLevels : Game -> Bool
validLevels g =
  let depths = map (\l : Level => l.depth) g.levels
      found = \d => any (\l : Level => l.depth == d) g.levels
  in not (null g.levels)
     && length (nub depths) == length depths
     && all (\d => d >= 1 && d <= 26) depths
     && found g.depth
     && all (\l => all (\m => m.hp <= m.maxHp) l.monsters
                && all (\m => validStatuses m.statuses) l.monsters
                && all (\m => not (isMimicking m)
                               || hasAbility MimicObject m.kind) l.monsters)
             g.levels

validItems : Game -> Bool
validItems g =
  let itemIds = ids g.items
      monIds = monsterIds g.levels
      levelDepths = map (\l : Level => l.depth) g.levels
      packIds = map (.id) (filter (\i => i.location == InPack) g.items)
  in length (nub itemIds) == length itemIds
     && all (\i => i.count > 0 && i.charges >= 0) g.items
     && all (\i => case i.location of
                     OnFloor d _ => elem d levelDepths
                     InPack => True
                     CarriedBy m => elem m monIds) g.items
     && all (\i => elem i packIds) g.player.inventory
     && all (\i => elem i itemIds) g.player.inventory
     && length (nub monIds) == length monIds

validCounters : Game -> Bool
validCounters g =
  let itemIds = ids g.items
      monIds = monsterIds g.levels
  in g.nextItemId > maxOf itemIds && g.nextMonsterId > maxOf monIds

validGame : Game -> Bool
validGame g =
  g.turn >= 0
  && g.quietTurns >= 0
  && g.depth >= 1 && g.depth <= 26
  && length g.messages <= 200
  && validPlayer g
  && validLevels g
  && validItems g
  && validCounters g

-- Game ---------------------------------------------------------------------

public export
gameToJSON : Game -> JSON
gameToJSON g =
  JObject
    [ ("seed", JString (seedHex g.seed))
    , ("rng", JString (stateHex g.rng))
    , ("turn", jsonInt g.turn)
    , ("quietTurns", jsonInt g.quietTurns)
    , ("depth", jsonInt g.depth)
    , ("player", playerToJSON g.player)
    , ("levels", JArray (map levelToJSON g.levels))
    , ("items", JArray (map itemToJSON g.items))
    , ("nextMonsterId", jsonBits32 g.nextMonsterId)
    , ("nextItemId", jsonBits32 g.nextItemId)
    , ("knownKinds", JArray (map (JString . itemKindText) g.knownKinds))
    , ("appearances", JArray (map appearanceToJSON g.appearances))
    , ("messages", JArray (map messageToJSON g.messages))
    , ("over", maybe (JNull) gameOverToJSON g.over)
    , ("visible", JString (bitsetHex g.visible))
    ]
  where
    appearanceToJSON : (ItemKind, String) -> JSON
    appearanceToJSON (k, name) =
      JObject [("kind", JString (itemKindText k)), ("name", JString name)]

appearanceFromJSON : JSON -> Maybe (ItemKind, String)
appearanceFromJSON j = do
  k <- field "kind" j >>= asString >>= itemKindFromText
  name <- field "name" j >>= asString
  pure (k, name)

public export
gameFromJSON : JSON -> Maybe Game
gameFromJSON j = do
  seed <- field "seed" j >>= asString >>= seedFromHex
  rng <- field "rng" j >>= asString >>= stateFromHex
  turn <- field "turn" j >>= asInt32
  quietTurns <- case field "quietTurns" j of
                  Nothing => pure 0
                  Just v => asInt32 v
  depth <- field "depth" j >>= asInt32
  player <- field "player" j >>= playerFromJSON
  levels <- field "levels" j >>= arrayOf levelFromJSON
  items <- field "items" j >>= arrayOf itemFromJSON
  nextMonsterId <- field "nextMonsterId" j >>= asBits32
  nextItemId <- field "nextItemId" j >>= asBits32
  knownKinds <- field "knownKinds" j >>= arrayOf (asString >=> itemKindFromText)
  appearances <- field "appearances" j >>= arrayOf appearanceFromJSON
  messages <- field "messages" j >>= arrayOf messageFromJSON
  over <- field "over" j >>= maybeGameOverFromJSON
  visible <- field "visible" j >>= asString >>= fromHex
  let g = MkGame seed rng turn quietTurns depth player levels items
                  nextMonsterId nextItemId knownKinds appearances
                  messages over visible
  if validGame g then Just g else Nothing
  where
    maybeGameOverFromJSON : JSON -> Maybe (Maybe GameOver)
    maybeGameOverFromJSON JNull = Just Nothing
    maybeGameOverFromJSON j = Just <$> gameOverFromJSON j

-- File format --------------------------------------------------------------

public export
saveToJSON : SaveKind -> String -> Game -> JSON
saveToJSON kind savedAt g =
  JObject
    [ ("schema", JString saveFileSchema)
    , ("kind", JString (show kind))
    , ("gameVersion", JString version)
    , ("savedAt", JString savedAt)
    , ("game", gameToJSON g)
    ]

public export
saveFromJSON : JSON -> Maybe SaveFile
saveFromJSON j = do
  schema <- field "schema" j >>= asString
  if schema /= saveFileSchema
     then Nothing
     else do
       kind <- field "kind" j >>= asString >>= saveKindFromText
       gameVersion <- field "gameVersion" j >>= asString
       if gameVersion /= version
          then Nothing
          else do
            savedAt <- field "savedAt" j >>= asString
            if null savedAt
               then Nothing
               else do
                 g <- field "game" j >>= gameFromJSON
                 pure (MkSaveFile kind savedAt g)

public export
saveToText : SaveKind -> String -> Game -> String
saveToText kind savedAt g = format 2 (saveToJSON kind savedAt g) ++ "\n"

public export
saveFromText : String -> Maybe SaveFile
saveFromText text = parse text >>= saveFromJSON

-- Timestamp ---------------------------------------------------------------

pad2 : Int32 -> String
pad2 n = if n < 10 then "0" ++ show n else show n

formatTime : Time.Tm -> String
formatTime t =
  show (t.tmYear + 1900) ++ "-" ++ pad2 (t.tmMon + 1) ++ "-"
  ++ pad2 t.tmMday ++ "T" ++ pad2 t.tmHour ++ ":" ++ pad2 t.tmMin
  ++ ":" ++ pad2 t.tmSec ++ "Z"

currentTimestamp : IO String
currentTimestamp = do
  seconds <- Time.time
  case !(Time.gmtime seconds) of
    Left _ => pure "1970-01-01T00:00:00Z"
    Right t => pure (formatTime t)

-- Atomic write -------------------------------------------------------------

writeAll : FD.FileDesc -> String -> IO Bool
writeAll fd s = do
  result <- Posix.String.write fd s
  case result of
    Left _ => pure False
    -- A short write to a regular file is exceptional.  Treat it as a failed
    -- save instead of retrying with character offsets that would not match
    -- the byte count returned by write(2).
    Right n => pure (n >= cast (byteLength s))

parentDir : String -> String
parentDir path =
  case span (/= '/') (reverse (unpack path)) of
    (_, '/' :: revDir) => pack (reverse revDir)
    _ => "."

syncDirectory : String -> IO ()
syncDirectory dir = do
  result <- Posix.openFile dir Posix.O_RDONLY 0
  case result of
    Left _ => pure ()
    Right fd => do
      _ <- Posix.fsync fd
      _ <- FD.close fd
      pure ()

atomicWrite : String -> String -> IO Bool
atomicWrite path contents = do
  pid <- Process.getpid
  let tmp = path ++ ".tmp." ++ show pid
  _ <- File.removeFile tmp
  opened <- Posix.openFile tmp
              (Posix.O_WRONLY .|. Posix.O_CREAT .|. Posix.O_TRUNC)
              420
  case opened of
    Left _ => pure False
    Right fd => do
      written <- writeAll fd contents
      synced <- if written
                   then do r <- Posix.fsync fd
                           pure (case r of
                                   Left _ => False
                                   Right _ => True)
                   else pure False
      _ <- FD.close fd
      if not synced
         then do _ <- File.removeFile tmp
                 pure False
         else do
           _ <- Stdio.rename path (path ++ ".bak")
           renamed <- Stdio.rename tmp path
           case renamed of
             Left _ => do _ <- File.removeFile tmp
                          pure False
             Right _ => do syncDirectory (parentDir path)
                           pure True

-- Session lock -------------------------------------------------------------

data LockState = NoLock | LockedBy Int32 | DamagedLock

lockStateAt : String -> IO LockState
lockStateAt path = do
  result <- File.readFile path
  case result of
    Left _ => pure NoLock
    Right text =>
      case parse text >>= field "pid" >>= asInt32 of
        Just pid => pure (LockedBy pid)
        Nothing => pure DamagedLock

%foreign "CExpr:(kill($1, 0)),libc,signal.h"
prim__probeProcess : Int32 -> PrimIO Int32

||| A process exists when signal 0 is accepted, or when it exists but belongs
||| to another user (`EPERM`).  `ESRCH` is the only proof of absence.
processAlive : Int32 -> IO Bool
processAlive pid = do
  result <- primIO (prim__probeProcess pid)
  if result == 0
     then pure True
     else do
       e <- errno
       pure (not (e == ESRCH))

writeLockAt : String -> IO Bool
writeLockAt path = do
  pid <- Process.getpid
  stamp <- currentTimestamp
  let payload : JSON
      payload = JObject
        [ ("pid", jsonInt (cast pid))
        , ("startedAt", JString stamp)
        ]
  result <- File.writeFile path (format 2 payload ++ "\n")
  case result of
    Left _ => pure False
    Right _ => pure True

||| Claim `path` for this process.  A lock whose PID is gone, or whose JSON is
||| unreadable, is stale and replaced.  A live PID keeps the lock.
public export
acquireLockAt : String -> IO Bool
acquireLockAt path = do
  state <- lockStateAt path
  case state of
    LockedBy pid => do
      alive <- processAlive pid
      if alive then pure False else claim
    _ => claim
  where
    claim : IO Bool
    claim = do
      _ <- File.removeFile path
      writeLockAt path

||| Remove the lock only when it still names this process.
public export
releaseLockAt : String -> IO ()
releaseLockAt path = do
  state <- lockStateAt path
  me <- Process.getpid
  let mine : Int32
      mine = cast me
  case state of
    LockedBy pid =>
      if pid == mine
         then do _ <- File.removeFile path
                 pure ()
         else pure ()
    DamagedLock => do _ <- File.removeFile path
                      pure ()
    NoLock => pure ()

public export
acquireSessionLock : IO Bool
acquireSessionLock = do
  ensureDataDir
  sessionLockFile >>= acquireLockAt

public export
releaseSessionLock : IO ()
releaseSessionLock = sessionLockFile >>= releaseLockAt

-- Public IO ----------------------------------------------------------------

public export
saveGameAt : String -> SaveKind -> Game -> IO Bool
saveGameAt path kind g = do
  stamp <- currentTimestamp
  atomicWrite path (saveToText kind stamp g)

public export
loadSaveAt : String -> IO (Maybe SaveFile)
loadSaveAt path = do
  result <- File.readFile path
  case result of
    Left _ => pure Nothing
    Right text => pure (saveFromText text)

public export
saveGame : SaveKind -> Game -> IO Bool
saveGame kind g = do
  ensureDataDir
  path <- saveFile
  saveGameAt path kind g

public export
loadSave : IO (Maybe SaveFile)
loadSave = saveFile >>= loadSaveAt

public export
autoSave : Game -> IO Bool
autoSave g = do
  ensureDataDir
  path <- autosaveFile
  saveGameAt path Autosave g

public export
loadAutosave : IO (Maybe SaveFile)
loadAutosave = autosaveFile >>= loadSaveAt

public export
deleteSave : IO ()
deleteSave = do
  path <- saveFile
  _ <- File.removeFile path
  pure ()

public export
deleteAutosave : IO ()
deleteAutosave = do
  path <- autosaveFile
  _ <- File.removeFile path
  pure ()
