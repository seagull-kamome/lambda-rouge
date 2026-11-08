||| Startup option tests.
module StartupTest

import LambdaRogue.App.Startup
import LambdaRogue.Core.Rng
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
  check "clock seeds depend on both time and process"
    (combineSeed 1 1 /= combineSeed 2 1
     && combineSeed 1 1 /= combineSeed 1 2)
  putStrLn "startup tests passed"
