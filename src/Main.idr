||| M2 entry point: a seeded 80x22 dungeon rendered through `TermUI.Canvas`.
module Main

import Data.List
import LambdaRogue.App.Canvas
import LambdaRogue.App.Model
import LambdaRogue.App.Program
import LambdaRogue.App.Settings
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Types
import LambdaRogue.Persist.Save
import LambdaRogue.Persist.Score
import LambdaRogue.Persist.Settings
import System.Posix.Errno
import TermUI.Canvas
import TermUI.Len
import TermUI.Program

%default covering

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
  acquired <- acquireSessionLock
  if not acquired
     then putStrLn "lambda-rogue is already running; close that instance first."
     else do
       settings <- loadSettings
       scores <- loadScores
       resumed <- resumeGame
       let game = case resumed of
                    Just (g, notice) => noteResume g notice
                    Nothing => newGame sampleSeed
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
