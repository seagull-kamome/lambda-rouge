||| `lambda-rogue.replay.v1` files.
|||
||| A replay stores the run seed and semantic `Command`s, never key presses.
||| Checkpoints are not part of the first on-disk format; verification uses
||| the same `gameDigest` path as the in-memory replay.
module LambdaRogue.Persist.Replay

import Data.Bits
import Data.List
import Data.Maybe
import Data.String
import Language.JSON
import LambdaRogue.Core.Game
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types
import LambdaRogue.Persist.Codec
import LambdaRogue.Persist.Json
import LambdaRogue.Persist.Paths
import LambdaRogue.Version
import System.Clock
import System.Directory
import System.File

%default covering

public export
replayFileSchema : String
replayFileSchema = "lambda-rogue.replay.v1"

commandToJSON : Command -> JSON
commandToJSON (Move d) =
  JObject [("type", JString "Move"), ("dir", JString (dirText d))]
commandToJSON Wait = JObject [("type", JString "Wait")]
commandToJSON Search = JObject [("type", JString "Search")]
commandToJSON PickUp = JObject [("type", JString "PickUp")]
commandToJSON (Quaff i) =
  JObject [("type", JString "Quaff"), ("item", jsonBits32 i)]
commandToJSON (Read i) =
  JObject [("type", JString "Read"), ("item", jsonBits32 i)]
commandToJSON (Eat i) =
  JObject [("type", JString "Eat"), ("item", jsonBits32 i)]
commandToJSON (Wield i) =
  JObject [("type", JString "Wield"), ("item", jsonBits32 i)]
commandToJSON (Wear i) =
  JObject [("type", JString "Wear"), ("item", jsonBits32 i)]
commandToJSON (PutOnRing i) =
  JObject [("type", JString "PutOnRing"), ("item", jsonBits32 i)]
commandToJSON (TakeOff i) =
  JObject [("type", JString "TakeOff"), ("item", jsonBits32 i)]
commandToJSON (Drop i) =
  JObject [("type", JString "Drop"), ("item", jsonBits32 i)]
commandToJSON (Throw i d) =
  JObject [("type", JString "Throw"), ("item", jsonBits32 i),
           ("dir", JString (dirText d))]
commandToJSON (Zap i d) =
  JObject [("type", JString "Zap"), ("item", jsonBits32 i),
           ("dir", JString (dirText d))]
commandToJSON Descend = JObject [("type", JString "Descend")]
commandToJSON Ascend = JObject [("type", JString "Ascend")]

itemArg : JSON -> Maybe ItemId
itemArg j = field "item" j >>= asBits32

dirArg : JSON -> Maybe Dir
dirArg j = field "dir" j >>= asString >>= dirFromText

commandFromJSON : JSON -> Maybe Command
commandFromJSON j = do
  typ <- field "type" j >>= asString
  case typ of
    "Move" => Move <$> dirArg j
    "Wait" => Just Wait
    "Search" => Just Search
    "PickUp" => Just PickUp
    "Quaff" => Quaff <$> itemArg j
    "Read" => Read <$> itemArg j
    "Eat" => Eat <$> itemArg j
    "Wield" => Wield <$> itemArg j
    "Wear" => Wear <$> itemArg j
    "PutOnRing" => PutOnRing <$> itemArg j
    "TakeOff" => TakeOff <$> itemArg j
    "Drop" => Drop <$> itemArg j
    "Throw" => Throw <$> itemArg j <*> dirArg j
    "Zap" => Zap <$> itemArg j <*> dirArg j
    "Descend" => Just Descend
    "Ascend" => Just Ascend
    _ => Nothing

public export
replayToJSON : Replay -> JSON
replayToJSON r =
  JObject
    [ ("schema", JString replayFileSchema)
    , ("gameVersion", JString version)
    , ("seed", JString (seedHex r.seed))
    , ("commands", JArray (map commandToJSON (replayCommands r)))
    ]

public export
replayFromJSON : JSON -> Maybe Replay
replayFromJSON j = do
  schema <- field "schema" j >>= asString
  if schema /= replayFileSchema
     then Nothing
     else do
       recordedVersion <- field "gameVersion" j >>= asString
       if recordedVersion /= version
          then Nothing
          else do
            seed <- field "seed" j >>= asString >>= seedFromHex
            commands <- field "commands" j >>= arrayOf commandFromJSON
            pure (MkReplay seed (reverse commands))

public export
replayToText : Replay -> String
replayToText r = format 2 (replayToJSON r) ++ "\n"

public export
replayFromText : String -> Maybe Replay
replayFromText text = parse text >>= replayFromJSON

public export
saveReplayAt : String -> Replay -> IO Bool
saveReplayAt path replay = do
  result <- writeFile path (replayToText replay)
  case result of
    Left _ => pure False
    Right _ => pure True

public export
loadReplayAt : String -> IO (Maybe Replay)
loadReplayAt path = do
  result <- readFile path
  case result of
    Left _ => pure Nothing
    Right text => pure (replayFromText text)

public export
replayFileName : Replay -> Bits64 -> String
replayFileName r stamp = seedHex r.seed ++ "-" ++ show stamp ++ ".replay.json"

||| Save under `replays/<seed>-<utc-seconds>.replay.json`.  The timestamp is
||| presentation metadata only; it is not part of the replay or its digest.
public export
saveReplay : Replay -> IO Bool
saveReplay replay = do
  ensureReplaysDir
  dir <- replaysDir
  utc <- clockTime UTC
  let stamp : Bits64
      stamp = cast (seconds utc)
  saveReplayAt (joinPath dir (replayFileName replay stamp)) replay

public export
loadReplayFile : String -> IO (Maybe Replay)
loadReplayFile name = do
  dir <- replaysDir
  loadReplayAt (joinPath dir name)

||| File names of saved replays, newest-looking last only by lexical order.
public export
listReplayFiles : IO (List String)
listReplayFiles = do
  dir <- replaysDir
  result <- listDir dir
  case result of
    Left _ => pure []
    Right names =>
      pure (sort (filter (\n => isSuffixOf ".replay.json" n) names))
