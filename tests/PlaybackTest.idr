||| Visible replay playback tests.  The playback owns the displayed game but
||| never changes the recorded replay or the original run.
module PlaybackTest

import Data.List
import Data.Maybe
import LambdaRogue.App.Model
import LambdaRogue.App.Update
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Types
import System
import TermUI.Canvas
import TermUI.Len
import TermUI.Program

check : String -> Bool -> IO ()
check name ok =
  if ok
     then putStrLn ("ok   " ++ name)
     else do
       putStrLn ("FAIL " ++ name)
       exitFailure

runCommands : List Command -> Game -> Game
runCommands cs g = foldl (\gg, c => (step c gg).game) g cs

public export
run : IO ()
run = do
  c <- newCanvas (the Len 80) (the Len 22)
  let seed : Bits64
      seed = 42
      g0 = newGame seed
      commands : List Command
      commands = [Move N, Wait, Move E, Wait, Move S]
      recorded = foldl (flip recordCommand) (emptyReplay seed) commands
      manual = runCommands commands g0
      base = initModel c manual
      m : Model
      m = { replay := recorded, replayOk := Just True, scoreOpen := True } base

  let started = fst (update StartReplay m)
  check "starting a replay shows the initial state"
    (isJust started.playback
     && not started.scoreOpen
     && gameDigest started.game == gameDigest g0)
  check "starting a replay keeps the recorded replay"
    (started.replay.commands == m.replay.commands)
  check "a started replay is playing"
    (case started.playback of
       Just pb => pb.playing && not pb.done && pb.played == 0
                  && pb.commandCount == length commands
       Nothing => False)

  let stepped = fst (update ReplayStep started)
  check "a replay step applies one command"
    (gameDigest stepped.game == gameDigest (runCommands (take 1 commands) g0))
  check "a replay step advances the counter"
    (case stepped.playback of
       Just pb => pb.played == 1
       Nothing => False)
  check "replay commands are not recorded again"
    (stepped.replay.commands == m.replay.commands)

  let paused = fst (update ReplayToggle stepped)
      ticked = fst (update ReplayTick paused)
  check "pausing a replay stops its timer"
    (case paused.playback of
       Just pb => not pb.playing
       Nothing => False)
  check "a paused replay ignores a tick"
    (gameDigest ticked.game == gameDigest paused.game)
  let resumed = fst (update ReplayToggle paused)
  check "resuming a replay sets playing again"
    (case resumed.playback of
       Just pb => pb.playing
       Nothing => False)

  let faster = fst (update ReplaySpeedUp started)
      slower = fst (update ReplaySpeedDown started)
  check "the replay speed can increase"
    (case faster.playback of
       Just pb => pb.speed == FastPlayback
       Nothing => False)
  check "the replay speed can decrease"
    (case slower.playback of
       Just pb => pb.speed == SlowPlayback
       Nothing => False)

  let restarted = fst (update ReplayRestart stepped)
  check "restarting a replay returns to the first command"
    (gameDigest restarted.game == gameDigest g0
     && (case restarted.playback of
           Just pb => pb.played == 0 && pb.playing
           Nothing => False))

  let finished = foldl (\mm, _ => fst (update ReplayStep mm)) started
                       (replicate (length commands) 0)
  check "a full replay reaches the recorded state"
    (gameDigest finished.game == gameDigest manual)
  check "a full replay stops at the end"
    (case finished.playback of
       Just pb => pb.done && not pb.playing && pb.played == pb.commandCount
       Nothing => False)

  let closed = fst (update CloseReplay finished)
  check "closing a replay restores the original game"
    (isNothing closed.playback
     && closed.scoreOpen
     && gameDigest closed.game == gameDigest manual)
  check "closing a replay keeps the recorded replay"
    (closed.replay.commands == recorded.commands)

  let empty = { replay := emptyReplay seed } m
      emptyStarted = fst (update StartReplay empty)
  check "an empty replay starts finished"
    (case emptyStarted.playback of
       Just pb => pb.done && not pb.playing && pb.commandCount == 0
       Nothing => False)

  putStrLn "playback tests passed"
