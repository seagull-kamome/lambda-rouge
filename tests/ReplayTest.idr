||| Deterministic replay and score tests for M4 slice 4.
module ReplayTest

import Data.List
import Data.Maybe
import LambdaRogue.App.Model
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types
import System

check : String -> Bool -> IO ()
check name ok =
  if ok
     then putStrLn ("ok   " ++ name)
     else do
       putStrLn ("FAIL " ++ name)
       exitFailure

runCommands : List Command -> Game -> Game
runCommands cs g = foldl (\gg, c => (step c gg).game) g cs

recordAll : List Command -> Replay -> Replay
recordAll cs r = foldl (\acc, c => recordCommand c acc) r cs

public export
run : IO ()
run = do
  let seed : Bits64
      seed = 0x0123456789abcdef
  check "seedHex is 16 lowercase hex digits"
    (seedHex seed == "0123456789abcdef" && length (seedHex seed) == 16)
  check "seedHex zero-pads"
    (seedHex 0 == "0000000000000000")

  let g0 = newGame 42
      r0 = emptyReplay 42
  check "an empty replay has no commands"
    (replayCommands r0 == [])
  check "recording keeps the newest command first"
    ((recordCommand Wait (recordCommand (Move N) r0)).commands
       == [Wait, Move N])
  check "replayCommands restores play order"
    (replayCommands (recordAll [Move N, Wait, Move E] r0)
       == [Move N, Wait, Move E])
  check "an empty replay reproduces newGame"
    (gameDigest (runReplay r0) == gameDigest g0)

  let commands : List Command
      commands = [Move N, Wait, Move E, Wait, Move S]
      recorded = recordAll commands r0
      manual = runCommands commands g0
  check "a recorded replay reproduces a manual run"
    (gameDigest (runReplay recorded) == gameDigest manual)
  check "replayMatches accepts the matching state"
    (replayMatches recorded manual)
  check "an extra command changes the digest"
    (not (replayMatches (recordCommand Wait recorded) manual))
  check "a different seed does not match"
    (not (replayMatches (recordAll commands (emptyReplay 43)) manual))
  check "gameDigest is 16 lowercase hex digits"
    (length (gameDigest manual) == 16
     && all (\c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
            (unpack (gameDigest manual)))
  check "gameDigest is deterministic"
    (gameDigest manual == gameDigest (runCommands commands g0))

  check "scoreOf ignores an unfinished run"
    (isNothing (scoreOf g0))
  let gWon : Game
      gWon = { over := Just Won } g0
  check "scoreOf records a finished run"
    (case scoreOf gWon of
       Just s => s.seed == 42 && s.depth == 1 && s.level == 1
                 && s.turns == 0 && s.result == Won
       Nothing => False)
  let gDead : Game
      gDead = { over := Just (Dead Starved) } gWon
  check "scoreOf keeps the death result"
    (case scoreOf gDead of
       Just s => s.result == Dead Starved
       Nothing => False)

  putStrLn "replay tests passed"
