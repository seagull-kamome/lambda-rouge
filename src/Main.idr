||| M2 entry point: a seeded 80x22 dungeon rendered through `TermUI.Canvas`.
module Main

import Data.List
import Data.Maybe
import LambdaRogue.App.Canvas
import LambdaRogue.App.Catalog
import LambdaRogue.App.Model
import LambdaRogue.App.Program
import LambdaRogue.App.Settings
import LambdaRogue.App.Startup
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Message as CoreMessage
import LambdaRogue.Core.Types
import LambdaRogue.Persist.Save
import LambdaRogue.Persist.Score
import LambdaRogue.Persist.Settings
import LambdaRogue.UI.Theme
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

useSave : SaveFile -> IO (Maybe (Game, CoreMessage.Msg))
useSave file = do
  deleteSave
  deleteAutosave
  pure (Just (file.game, CoreMessage.ResumedFromSave))

useAutosave : IO (Maybe (Game, CoreMessage.Msg))
useAutosave = do
  recovered <- loadAutosave
  case recovered of
    Just file => do
      deleteAutosave
      pure (Just (file.game, CoreMessage.RecoveredFromAutosave))
    Nothing => pure Nothing

resumeGame : IO (Maybe (Game, CoreMessage.Msg))
resumeGame = do
  saved <- loadSave
  case saved of
    Just file => useSave file
    Nothing => useAutosave

||| Show the recovery notice in the ordinary log.  Messages are excluded
||| from the replay digest, so this cannot change verification.
noteResume : Game -> CoreMessage.Msg -> Game
noteResume g message =
  { messages := [CoreMessage.mkMessage g.turn SystemMsg message] ++ take 199 g.messages } g

||| Pick the language for diagnostics that are printed before the UI
||| starts.  The full parser reports the authoritative option later.
languageArg : List String -> Language
languageArg ("--lang" :: value :: rest) =
  fromMaybe (languageArg rest) (languageFromId value)
languageArg (_ :: rest) = languageArg rest
languageArg [] = English

main : IO ()
main = do
  args <- getArgs
  let earlyLanguage = languageArg args
  case parseStartOptionsIn earlyLanguage args of
    Left err => putStrLn err
    Right requested => do
      acquired <- acquireSessionLock
      if not acquired
         then putStrLn (uiText earlyLanguage AppAlreadyRunning)
         else do
           settings <- loadSettings
           scores <- loadScores
           let language = fromMaybe settings.language requested.language
           -- An explicit --seed starts a fresh run; otherwise prefer the
           -- existing save.  Deleting the old save keeps a later launch
           -- from resuming a run the player deliberately replaced.
           resumed <- case requested.seed of
                        ExplicitSeed _ => do
                          deleteSave
                          deleteAutosave
                          pure Nothing
                        GeneratedSeed => resumeGame
           game <- case (the (Maybe (Game, CoreMessage.Msg)) resumed) of
                     Just (g, notice) => pure (noteResume g notice)
                     Nothing =>
                       case requested.seed of
                         ExplicitSeed seed => pure (newGame seed)
                         GeneratedSeed => do
                           seed <- freshSeed
                           pure (newGame seed)
           c <- newCanvas (the Len 80) (the Len 22)
           noColorEnv <- getEnv "NO_COLOR"
           colorterm <- getEnv "COLORTERM"
           term <- getEnv "TERM"
           noMotion <- getEnv "NO_MOTION"
           let support = if requested.noColour
                            then NoColour
                            else detectColourSupport noColorEnv colorterm term
               theme = themeForSupport support
                         (fromMaybe settings.theme requested.theme)
               animations = settings.animationsEnabled
                            && not (requested.noAnimation
                                    || detectReducedMotion noMotion)
               base = initModel c game
               model = { theme := theme
                       , animationsEnabled := animations
                       , keymap := settings.keymap
                       , language := language
                       , scores := scores
                       , ui := { animationSpeed := settings.animationSpeed }
                                 defaultUiState } base
           drawMapAnimated model.theme model.hover model.animations c game
           r <- runProgram (programWith model)
           case r of
             Left e => putStrLn (uiTextArgs language AppNeedsTerminal [show e])
             Right _ => do deleteAutosave
                           putStrLn (uiText language Bye)
           releaseSessionLock
