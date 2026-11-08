||| M2 entry point: a seeded 80x22 dungeon rendered through `TermUI.Canvas`.
module Main

import Data.List
import LambdaRogue.App.Canvas
import LambdaRogue.App.Model
import LambdaRogue.App.Program
import LambdaRogue.App.Settings
import LambdaRogue.App.Startup
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Types
import LambdaRogue.Persist.Save
import LambdaRogue.Persist.Score
import LambdaRogue.Persist.Settings
import System
import System.Clock
import System.Posix.Errno
import TermUI.Canvas
import TermUI.Len
import TermUI.Program

%default covering

freshSeed : IO Bits64
freshSeed = do
  now <- clockTime UTC
  pid <- getPID
  pure (combineSeed (toNano now) pid)

useSave : SaveFile -> IO (Maybe (Game, String))
useSave file = do
  deleteSave
  deleteAutosave
  pure (Just (file.game, "Resumed from save."))

useAutosave : IO (Maybe (Game, String))
useAutosave = do
  recovered <- loadAutosave
  case recovered of
    Just file => do
      deleteAutosave
      pure (Just (file.game, "Recovered from autosave."))
    Nothing => pure Nothing

resumeGame : IO (Maybe (Game, String))
resumeGame = do
  saved <- loadSave
  case saved of
    Just file => useSave file
    Nothing => useAutosave

||| Show the recovery notice in the ordinary log.  Messages are excluded
||| from the replay digest, so this cannot change verification.
noteResume : Game -> String -> Game
noteResume g text =
  { messages := [MkMessage g.turn SystemMsg text] ++ take 199 g.messages } g

main : IO ()
main = do
  args <- getArgs
  case parseStartSeed args of
    Left err => putStrLn err
    Right requested => do
      acquired <- acquireSessionLock
      if not acquired
         then putStrLn "lambda-rogue is already running; close that instance first."
         else do
           settings <- loadSettings
           scores <- loadScores
           -- An explicit --seed starts a fresh run; otherwise prefer the
           -- existing save.  Deleting the old save keeps a later launch
           -- from resuming a run the player deliberately replaced.
           resumed <- case requested of
                        ExplicitSeed _ => do
                          deleteSave
                          deleteAutosave
                          pure Nothing
                        GeneratedSeed => resumeGame
           game <- case (the (Maybe (Game, String)) resumed) of
                     Just (g, notice) => pure (noteResume g notice)
                     Nothing =>
                       case requested of
                         ExplicitSeed seed => pure (newGame seed)
                         GeneratedSeed => do
                           seed <- freshSeed
                           pure (newGame seed)
           c <- newCanvas (the Len 80) (the Len 22)
           let base = initModel c game
               model = { theme := settings.theme
                       , animationsEnabled := settings.animationsEnabled
                       , keymap := settings.keymap
                       , scores := scores } base
           drawMapAnimated model.theme model.hover model.animations c game
           r <- runProgram (programWith model)
           case r of
             Left e => putStrLn ("lambda-rogue needs a terminal: " ++ show e)
             Right _ => do deleteAutosave
                           putStrLn "bye"
           releaseSessionLock
