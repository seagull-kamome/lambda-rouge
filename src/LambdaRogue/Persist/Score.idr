||| `scores.jsonl`: one completed run per line, oldest first on disk.
|||
||| A malformed line is skipped rather than rejecting the whole history.
||| The score screen expects newest first, so `loadScores` reverses the
||| file order after parsing.
module LambdaRogue.Persist.Score

import Data.List
import Data.Maybe
import Data.String
import Language.JSON
import LambdaRogue.App.Model
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types
import LambdaRogue.Persist.Codec
import LambdaRogue.Persist.Json
import LambdaRogue.Persist.Paths
import System.File

%default covering

public export
scoreSchema : String
scoreSchema = "lambda-rogue.score.v1"

public export
scoreToJSON : Score -> JSON
scoreToJSON s =
  JObject
    [ ("schema", JString scoreSchema)
    , ("seed", JString (seedHex s.seed))
    , ("depth", jsonInt s.depth)
    , ("level", jsonInt s.level)
    , ("exp", jsonInt s.exp)
    , ("gold", jsonInt s.gold)
    , ("turns", jsonInt s.turns)
    , ("result", gameOverToJSON s.result)
    ]

public export
scoreFromJSON : JSON -> Maybe Score
scoreFromJSON j = do
  schema <- field "schema" j >>= asString
  if schema /= scoreSchema
     then Nothing
     else do
       seed <- field "seed" j >>= asString >>= seedFromHex
       depth <- field "depth" j >>= asInt32
       level <- field "level" j >>= asInt32
       exp <- field "exp" j >>= asInt32
       gold <- field "gold" j >>= asInt32
       turns <- field "turns" j >>= asInt32
       result <- field "result" j >>= gameOverFromJSON
       pure (MkScore seed depth level exp gold turns result)

public export
scoreToLine : Score -> String
scoreToLine = show . scoreToJSON

public export
scoreFromLine : String -> Maybe Score
scoreFromLine line = parse line >>= scoreFromJSON

||| Parse every valid line, skipping blank or damaged records.
public export
scoresFromText : String -> List Score
scoresFromText text =
  mapMaybe scoreFromLine (filter (not . null . trim) (lines text))

public export
loadScoresAt : String -> IO (List Score)
loadScoresAt path = do
  result <- readFile path
  case result of
    Left _ => pure []
    Right text => pure (reverse (scoresFromText text))

public export
appendScoreAt : String -> Score -> IO Bool
appendScoreAt path score = do
  result <- appendFile path (scoreToLine score ++ "\n")
  case result of
    Left _ => pure False
    Right _ => pure True

public export
loadScores : IO (List Score)
loadScores = scoresFile >>= loadScoresAt

public export
appendScore : Score -> IO Bool
appendScore score = do
  ensureDataDir
  path <- scoresFile
  appendScoreAt path score
