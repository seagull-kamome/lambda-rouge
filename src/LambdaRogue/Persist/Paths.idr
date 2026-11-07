||| Where lambda-rogue keeps its data files.
|||
||| Only `Persist.*` imports this module.  Core never sees a path or an
||| environment variable.
module LambdaRogue.Persist.Paths

import Data.String
import System
import System.Directory

%default covering

public export
joinPath : String -> String -> String
joinPath dir name =
  if isSuffixOf "/" dir then dir ++ name else dir ++ "/" ++ name

||| `$XDG_DATA_HOME/lambda-rogue`, else `$HOME/.local/share/lambda-rogue`.
public export
dataDir : IO String
dataDir = do
  xdg <- getEnv "XDG_DATA_HOME"
  case xdg of
    Just d =>
      if d == ""
         then homeDir
         else pure (joinPath d "lambda-rogue")
    Nothing => homeDir
  where
    homeDir : IO String
    homeDir = do
      home <- getEnv "HOME"
      case home of
        Just h => pure (joinPath h ".local/share/lambda-rogue")
        Nothing => pure "."

public export
dataPath : String -> IO String
dataPath name = map (\d => joinPath d name) dataDir

public export
settingsFile : IO String
settingsFile = dataPath "settings.json"

public export
scoresFile : IO String
scoresFile = dataPath "scores.jsonl"

public export
saveFile : IO String
saveFile = dataPath "save.json"

public export
autosaveFile : IO String
autosaveFile = dataPath "autosave.json"

public export
sessionLockFile : IO String
sessionLockFile = dataPath "session.lock"

public export
replaysDir : IO String
replaysDir = dataPath "replays"

ignoreResult : IO (Either a b) -> IO ()
ignoreResult act = do
  _ <- act
  pure ()

mkdir : String -> IO ()
mkdir dir = ignoreResult (createDir dir)

||| Create the parent directories needed for the data directory.  A failure
||| is ignored: the following write reports it.
public export
ensureDataDir : IO ()
ensureDataDir = do
  xdg <- getEnv "XDG_DATA_HOME"
  case xdg of
    Just d =>
      if d == ""
         then ensureHome
         else do
           mkdir d
           mkdir (joinPath d "lambda-rogue")
    Nothing => ensureHome
  where
    ensureHome : IO ()
    ensureHome = do
      home <- getEnv "HOME"
      case home of
        Just h => do
          mkdir (joinPath h ".local")
          mkdir (joinPath h ".local/share")
          mkdir (joinPath h ".local/share/lambda-rogue")
        Nothing => pure ()

public export
ensureReplaysDir : IO ()
ensureReplaysDir = do
  ensureDataDir
  dir <- replaysDir
  mkdir dir
