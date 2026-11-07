||| Loading and saving `settings.json`.
|||
||| The pure schema lives in `App.Settings`; this module only chooses the
||| data directory and performs file IO.  A missing or invalid file yields
||| the defaults, so a bad edit cannot stop the game from starting.
module LambdaRogue.Persist.Settings

import Data.Maybe
import LambdaRogue.App.Settings
import LambdaRogue.Persist.Paths
import System.File

%default covering

||| Read a settings file at an explicit path.  Missing or malformed files
||| produce `defaultSettings`; this function never throws.
public export
loadSettingsAt : String -> IO Settings
loadSettingsAt path = do
  result <- readFile path
  case result of
    Left _ => pure defaultSettings
    Right text => pure (fromMaybe defaultSettings (settingsFromText text))

public export
saveSettingsAt : String -> Settings -> IO Bool
saveSettingsAt path settings = do
  result <- writeFile path (settingsToText settings)
  case result of
    Left _ => pure False
    Right _ => pure True

public export
loadSettings : IO Settings
loadSettings = settingsFile >>= loadSettingsAt

public export
saveSettings : Settings -> IO Bool
saveSettings settings = do
  ensureDataDir
  path <- settingsFile
  saveSettingsAt path settings
