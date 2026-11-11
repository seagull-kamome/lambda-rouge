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
  check "a finished replay verifies its final state"
    (case finished.playback of
       Just pb => pb.verified == Just (replayMatches recorded finished.game)
       Nothing => False)

  let sought = fst (update ReplaySeekForward started)
  check "seeking forward clamps at the end"
    (case sought.playback of
       Just pb => pb.played == length commands && pb.done && not pb.playing
       Nothing => False)
  check "seeking forward reaches the recorded state"
    (gameDigest sought.game == gameDigest manual)
  check "seeking keeps the recorded replay"
    (sought.replay.commands == m.replay.commands)
  let back = fst (update ReplaySeekBack sought)
  check "seeking back moves ten commands at a time"
    (case back.playback of
       Just pb => pb.played == 0 && not pb.done && not pb.playing
       Nothing => False)
  let third = fst (update ReplaySeekStart sought)
  check "seeking to the start rewinds the game"
    (case third.playback of
       Just pb => pb.played == 0 && pb.verified == Nothing
       Nothing => False)
  check "seek to the start matches a fresh game"
    (gameDigest third.game == gameDigest g0)
  let atEnd = fst (update ReplaySeekEnd started)
  check "End jumps to the last command"
    (case atEnd.playback of
       Just pb => pb.played == length commands && pb.done
                  && pb.verified == Just True
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
  -- A replay opened from the browser during normal play returns to the run.
  let midRun = { scoreOpen := False } m
      loadedMid = fst (update (ReplayFileLoaded "mid.json" (Just recorded)) midRun)
      midClosed = fst (update CloseReplay loadedMid)
  check "closing a browser replay returns to the interrupted game"
    (isNothing midClosed.playback
     && not midClosed.scoreOpen
     && gameDigest midClosed.game == gameDigest manual)
  check "closing a browser replay keeps the recorded replay"
    (midClosed.replay.commands == m.replay.commands)

  check "an empty replay starts finished"
    (case emptyStarted.playback of
       Just pb => pb.done && not pb.playing && pb.commandCount == 0
       Nothing => False)

  -- Loaded replays have no recorded final digest, so they start unchecked.
  let loaded = fst (update (ReplayFileLoaded "run.replay.json" (Just recorded)) m)
  check "a loaded replay starts unchecked"
    (case loaded.playback of
       Just pb => pb.verified == Nothing && pb.played == 0
       Nothing => False)
  check "loading a replay closes the browser"
    (not loaded.ui.replayBrowserOpen)
  check "a loaded replay keeps its recorded commands"
    (loaded.replay.commands == recorded.commands)
  let loadedDone = foldl (\mm, _ => fst (update ReplayStep mm)) loaded
                         (replicate (length commands) 0)
  check "a loaded replay verifies when it finishes"
    (case loadedDone.playback of
       Just pb => pb.verified == Just True
       Nothing => False)

  let browserOut = update OpenReplayBrowser m
      mBrowser = fst browserOut
  check "opening the browser sets its flag"
    (mBrowser.ui.replayBrowserOpen && not mBrowser.scoreOpen
     && mBrowser.ui.replayIndex == 0)
  let listed = fst (update (ReplayFiles ["b.json", "a.json"]) mBrowser)
  check "the browser stores the file list"
    (listed.ui.replayFiles == ["b.json", "a.json"]
     && listed.ui.replayIndex == 0)
  let nexted = fst (update ReplayBrowserNext listed)
  check "the browser moves to the next file"
    (nexted.ui.replayIndex == 1)
  let wrapped = fst (update ReplayBrowserNext nexted)
  check "the browser wraps to the first file"
    (wrapped.ui.replayIndex == 0)
  let prevWrapped = fst (update ReplayBrowserPrev wrapped)
  check "the browser wraps backwards to the last file"
    (prevWrapped.ui.replayIndex == 1)
  let selected = fst (update (ReplayBrowserSelect 99) prevWrapped)
  check "selecting out of range keeps the index"
    (selected.ui.replayIndex == 1)
  let failed = fst (update (ReplayFileLoaded "bad.json" Nothing) mBrowser)
  check "a malformed replay reports an error"
    (failed.ui.replayError == Just "bad.json"
     && isNothing failed.playback)
  let closedBrowser = fst (update CloseReplayBrowser mBrowser)
  check "closing the browser clears its flag"
    (not closedBrowser.ui.replayBrowserOpen)

  putStrLn "playback tests passed"
