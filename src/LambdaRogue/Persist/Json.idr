||| Small, total helpers shared by the JSON codecs in `Persist.*`.
|||
||| The game writes its own files, but every reader still validates shape
||| and type.  A malformed record is rejected as a whole rather than
||| producing a half-loaded game.
module LambdaRogue.Persist.Json

import Data.Bits
import Data.List
import Data.Maybe
import Language.JSON
import Text.NumberFormat

%default covering

public export
asString : JSON -> Maybe String
asString (JString s) = Just s
asString _ = Nothing

public export
asBool : JSON -> Maybe Bool
asBool (JBoolean b) = Just b
asBool _ = Nothing

public export
asInt32 : JSON -> Maybe Int32
asInt32 (JNumber d) =
  let n : Int32
      n = cast d
  in if cast n == d then Just n else Nothing
asInt32 _ = Nothing

public export
asBits32 : JSON -> Maybe Bits32
asBits32 j = map cast (asInt32 j)

public export
field : String -> JSON -> Maybe JSON
field name (JObject fields) = lookup name fields
field _ _ = Nothing

public export
required : String -> JSON -> Maybe JSON
required = field

public export
asArray : JSON -> Maybe (List JSON)
asArray (JArray xs) = Just xs
asArray _ = Nothing

public export
arrayOf : (JSON -> Maybe a) -> JSON -> Maybe (List a)
arrayOf f j = asArray j >>= traverse f

public export
hex64 : Bits64 -> String
hex64 = toHex
