||| Startup option tests.
module StartupTest

import Data.List
import Data.String
import LambdaRogue.App.Catalog
import LambdaRogue.App.Startup
import LambdaRogue.Core.Rng
import LambdaRogue.UI.Theme
import System

check : String -> Bool -> IO ()
check name ok =
  if ok
     then putStrLn ("ok   " ++ name)
     else do
       putStrLn ("FAIL " ++ name)
       exitFailure

isGenerated : Either String StartSeed -> Bool
isGenerated (Right GeneratedSeed) = True
isGenerated _ = False

isExplicit : Bits64 -> Either String StartSeed -> Bool
isExplicit seed (Right (ExplicitSeed actual)) = seed == actual
isExplicit _ _ = False

isError : Either String StartSeed -> Bool
isError (Left _) = True
isError _ = False

optionsLanguage : Either String StartOptions -> Maybe (Maybe Language)
optionsLanguage (Right opts) = Just opts.language
optionsLanguage _ = Nothing

optionsSeed : Either String StartOptions -> Maybe StartSeed
optionsSeed (Right opts) = Just opts.seed
optionsSeed _ = Nothing

optionsFailed : Either String StartOptions -> Bool
optionsFailed (Left _) = True
optionsFailed _ = False

optionsTheme : Either String StartOptions -> Maybe (Maybe Theme)
optionsTheme (Right opts) = Just opts.theme
optionsTheme _ = Nothing

optionsNoColour : Either String StartOptions -> Maybe Bool
optionsNoColour (Right opts) = Just opts.noColour
optionsNoColour _ = Nothing

optionsNoAnimation : Either String StartOptions -> Maybe Bool
optionsNoAnimation (Right opts) = Just opts.noAnimation
optionsNoAnimation _ = Nothing

public export
run : IO ()
run = do
  check "no arguments requests a generated seed"
    (isGenerated (parseStartSeed []))
  check "--seed accepts 16 lowercase hex digits"
    (isExplicit 0x0123456789abcdef
      (parseStartSeed ["lambda-rogue", "--seed", "0123456789abcdef"]))
  check "--seed rejects an invalid value"
    (isError (parseStartSeed ["--seed", "0123456789ABCDEF"]))
  check "--seed rejects a missing value"
    (isError (parseStartSeed ["--seed"]))
  check "unrelated arguments are ignored"
    (isGenerated (parseStartSeed ["--verbose"]))
  check "--lang en selects English"
    (optionsLanguage (parseStartOptions ["--lang", "en"])
     == Just (Just English))
  check "--lang ja selects Japanese"
    (optionsLanguage (parseStartOptions ["--lang", "ja"])
     == Just (Just Japanese))
  check "no --lang leaves the settings language in charge"
    (optionsLanguage (parseStartOptions []) == Just Nothing)
  check "--seed and --lang can be combined"
    (optionsLanguage
       (parseStartOptions ["--seed", "0123456789abcdef", "--lang", "ja"])
     == Just (Just Japanese)
     && optionsSeed
          (parseStartOptions ["--seed", "0123456789abcdef", "--lang", "ja"])
        == Just (ExplicitSeed 0x0123456789abcdef))
  check "--lang rejects a missing value"
    (optionsFailed (parseStartOptions ["--lang"]))
  check "--lang rejects an unknown value"
    (optionsFailed (parseStartOptions ["--lang", "de"]))
  check "--lang rejects an uppercase value"
    (optionsFailed (parseStartOptions ["--lang", "JA"]))
  check "a missing --lang value is localized"
    (case parseStartOptionsIn Japanese ["--lang"] of
       Left message => isInfixOf (unpack "値がない") (unpack message)
       Right _ => False)
  check "an invalid --lang value keeps the bad value in the message"
    (case parseStartOptionsIn Japanese ["--lang", "de"] of
       Left message => isInfixOf (unpack "de") (unpack message)
       Right _ => False)
  check "an invalid --seed value is localized"
    (case parseStartOptionsIn Japanese ["--seed", "NOPE"] of
       Left message => isInfixOf (unpack "NOPE") (unpack message)
       Right _ => False)
  check "--theme amber selects the amber theme"
    (optionsTheme (parseStartOptions ["--theme", "amber"])
     == Just (Just Amber))
  check "--theme monochrome selects monochrome"
    (optionsTheme (parseStartOptions ["--theme", "monochrome"])
     == Just (Just Monochrome))
  check "no --theme leaves the settings theme in charge"
    (optionsTheme (parseStartOptions []) == Just Nothing)
  check "--theme rejects an unknown id"
    (optionsFailed (parseStartOptions ["--theme", "neon"]))
  check "--theme rejects a missing value"
    (optionsFailed (parseStartOptions ["--theme"]))
  check "--theme rejects an uppercase id"
    (optionsFailed (parseStartOptions ["--theme", "Amber"]))
  check "--no-color disables colour"
    (optionsNoColour (parseStartOptions ["--no-color"]) == Just True)
  check "colour is enabled by default"
    (optionsNoColour (parseStartOptions []) == Just False)
  check "--no-animation disables animation"
    (optionsNoAnimation (parseStartOptions ["--no-animation"]) == Just True)
  check "animation is enabled by default"
    (optionsNoAnimation (parseStartOptions []) == Just False)
  check "the new flags combine with --lang"
    (case parseStartOptions ["--theme", "amber", "--no-color",
                             "--no-animation", "--lang", "ja"] of
       Right opts => opts.theme == Just Amber
                     && opts.noColour && opts.noAnimation
                     && opts.language == Just Japanese
       Left _ => False)
  check "an invalid --theme value is localized"
    (case parseStartOptionsIn Japanese ["--theme", "neon"] of
       Left message => isInfixOf (unpack "neon") (unpack message)
       Right _ => False)
  check "clock seeds depend on both time and process"
    (combineSeed 1 1 /= combineSeed 2 1
     && combineSeed 1 1 /= combineSeed 1 2)
  putStrLn "startup tests passed"
