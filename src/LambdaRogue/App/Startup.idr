||| Startup options for a fresh run.
|||
||| The executable generates a new seed from the clock and process ID when no
||| seed is supplied.  `--seed` makes a run reproducible, which is what the
||| share-seed screen tells another player to use.
module LambdaRogue.App.Startup

import Data.Bits
import LambdaRogue.App.Catalog
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types

%default covering

public export
data StartSeed
  = GeneratedSeed
  | ExplicitSeed Bits64

public export
Eq StartSeed where
  GeneratedSeed == GeneratedSeed = True
  ExplicitSeed a == ExplicitSeed b = a == b
  _ == _ = False

public export
Show StartSeed where
  show GeneratedSeed = "generated"
  show (ExplicitSeed seed) = seedHex seed

||| Combine a nanosecond timestamp with the process ID.  The time gives a
||| different value on every launch, and the PID keeps two processes that
||| start within the same clock tick apart.
public export
combineSeed : Integer -> Int -> Bits64
combineSeed nanos pid =
  let time = the Bits64 (cast nanos)
      process = the Bits64 (cast pid)
  in time `xor` (process `shiftL` 32)

||| Everything the command line can select for this launch.
public export
record StartOptions where
  constructor MkStartOptions
  seed : StartSeed
  language : Maybe Language

||| Parse the command line.  Unknown arguments are ignored so that the
||| executable name and terminal wrappers do not have to be special-cased.
||| A malformed `--seed` or `--lang` is an error rather than silently
||| starting a different run from the one the player asked for.
public export
parseStartOptionsIn : Language -> List String -> Either String StartOptions
parseStartOptionsIn lang args = go args GeneratedSeed Nothing
  where
    go : List String -> StartSeed -> Maybe Language -> Either String StartOptions
    go [] seed language = Right (MkStartOptions seed language)
    go ("--seed" :: []) _ _ =
      Left (uiText lang MissingSeedValue)
    go ("--seed" :: value :: rest) _ language =
      case seedFromHex value of
        Just seed => go rest (ExplicitSeed seed) language
        Nothing =>
          Left (uiTextArgs lang InvalidSeedValue [value])
    go ("--lang" :: []) _ _ =
      Left (uiText lang MissingLangValue)
    go ("--lang" :: value :: rest) seed _ =
      case languageFromId value of
        Just language => go rest seed (Just language)
        Nothing =>
          Left (uiTextArgs lang InvalidLangValue [value])
    go (_ :: rest) seed language = go rest seed language

public export
parseStartOptions : List String -> Either String StartOptions
parseStartOptions = parseStartOptionsIn English

||| The seed-only view retained for callers that do not need `--lang`.
public export
parseStartSeed : List String -> Either String StartSeed
parseStartSeed args = map (.seed) (parseStartOptions args)
