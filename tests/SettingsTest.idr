||| Keybinding and `settings.json` tests.
|||
||| All assertions are pure except the final file round-trip.  Settings may
||| change which `Msg` a key produces, but never the game, RNG or replay.
module SettingsTest

import Data.List
import Data.Maybe
import LambdaRogue.App.Keymap
import LambdaRogue.App.Model
import LambdaRogue.App.Settings
import LambdaRogue.App.Subs
import LambdaRogue.App.Update
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Types
import LambdaRogue.Persist.Settings
import LambdaRogue.UI.Theme
import System
import System.File
import TermUI.Canvas
import TermUI.Input
import TermUI.Len
import TermUI.Program

check : String -> Bool -> IO ()
check name ok =
  if ok
     then putStrLn ("ok   " ++ name)
     else do
       putStrLn ("FAIL " ++ name)
       exitFailure

plain : Char -> KeyChord
plain c = MkKeyChord (KChar c) noMods

isOpenInventory : Maybe Msg -> Bool
isOpenInventory (Just OpenInventory) = True
isOpenInventory _ = False

isQuaffAction : Maybe Msg -> Bool
isQuaffAction (Just (DoItemAction QuaffAction)) = True
isQuaffAction _ = False

isZapEast : Maybe Msg -> Bool
isZapEast (Just (Do (Zap 2 E))) = True
isZapEast _ = False

ctrlKey : Char -> KeyChord
ctrlKey c = MkKeyChord (KChar c) (MkMods False True False)

public export
run : IO ()
run = do
  check "k moves north by default"
    (commandForChord (plain 'k') defaultKeymap == Just MoveNorth)
  check "Up also moves north by default"
    (commandForChord (MkKeyChord KUp noMods) defaultKeymap == Just MoveNorth)
  check "Ctrl-P opens the palette by default"
    (commandForChord (ctrlKey 'p') defaultKeymap == Just Palette)
  check "Ctrl-S shares the seed by default"
    (commandForChord (ctrlKey 's') defaultKeymap == Just Share)
  check "q quaffs by default"
    (commandForChord (plain 'q') defaultKeymap == Just Quaff)
  check "Q quits by default"
    (commandForChord (plain 'Q') defaultKeymap == Just Quit)
  check "the default keymap has no duplicate chords"
    (not (hasDuplicateChords defaultKeymap))
  check "the default quit keys are Q and Ctrl-C"
    (formatKeys (keysFor Quit defaultKeymap) == "Q / Ctrl-C")

  check "parse k"
    (parseKeyChord "k" == Just (plain 'k'))
  check "parse F4"
    (parseKeyChord "F4" == Just (MkKeyChord (KF 4) noMods))
  check "parse Up"
    (parseKeyChord "Up" == Just (MkKeyChord KUp noMods))
  check "parse Space"
    (parseKeyChord "Space" == Just (plain ' '))
  check "parse >"
    (parseKeyChord ">" == Just (plain '>'))
  check "parse Ctrl-S"
    (parseKeyChord "Ctrl-S" == Just (ctrlKey 's'))
  check "Ctrl-S renders with a capital letter"
    (case parseKeyChord "Ctrl-S" of
       Just k => chordText k == "Ctrl-S"
       Nothing => False)
  check "parse Ctrl-L"
    (parseKeyChord "Ctrl-L" == Just (ctrlKey 'l'))
  check "an unknown key name is rejected"
    (isNothing (parseKeyChord "NoSuchKey"))
  check "an empty key name is rejected"
    (isNothing (parseKeyChord ""))

  let kmInventory : Keymap
      kmInventory = setBindingKeys Inventory [plain 'I'] defaultKeymap
  check "a rebound key resolves to the same command"
    (commandForChord (plain 'I') kmInventory == Just Inventory)
  check "the old key stops resolving after a rebind"
    (isNothing (commandForChord (plain 'i') kmInventory))

  let kmQuaff : Keymap
      kmQuaff = setBindingKeys Quaff [plain 'V'] defaultKeymap
  check "a rebound keymap stays duplicate-free"
    (not (hasDuplicateChords kmQuaff))

  let kmDirection : Keymap
      kmDirection = setBindingKeys MoveEast [plain 'L'] defaultKeymap
  check "a rebound movement key still has a direction"
    (commandForChord (plain 'L') kmDirection == Just MoveEast)

  let baseSettings : Settings
      baseSettings =
        MkSettings ModernDark False
          (setBindingKeys Help [MkKeyChord (KF 9) noMods] defaultKeymap)
  check "settings text round-trips"
    (case settingsFromText (settingsToText baseSettings) of
       Just s => s == baseSettings
       Nothing => False)
  check "settings output names the schema"
    (isInfixOf (unpack "lambda-rogue.settings.v1")
               (unpack (settingsToText baseSettings)))
  check "missing optional fields keep defaults"
    (settingsFromText "{\"schema\":\"lambda-rogue.settings.v1\"}"
       == Just defaultSettings)
  check "an unknown command id is ignored"
    (case settingsFromText
            "{\"schema\":\"lambda-rogue.settings.v1\",\"keys\":{\"teleport\":[\"T\"],\"help\":[\"F9\"]}}" of
       Just s => keysFor Help s.keymap == [MkKeyChord (KF 9) noMods]
       Nothing => False)
  check "an empty key list unbinds a command"
    (case settingsFromText
            "{\"schema\":\"lambda-rogue.settings.v1\",\"keys\":{\"help\":[]}}" of
       Just s => null (keysFor Help s.keymap)
       Nothing => False)
  check "an invalid chord rejects the settings file"
    (isNothing (settingsFromText
      "{\"schema\":\"lambda-rogue.settings.v1\",\"keys\":{\"help\":[\"NoSuchKey\"]}}"))
  check "a duplicate chord rejects the settings file"
    (isNothing (settingsFromText
      "{\"schema\":\"lambda-rogue.settings.v1\",\"keys\":{\"move-north\":[\"j\"]}}"))
  check "an unknown theme rejects the settings file"
    (isNothing (settingsFromText
      "{\"schema\":\"lambda-rogue.settings.v1\",\"theme\":\"neon\"}"))
  check "a non-boolean animation flag rejects the settings file"
    (isNothing (settingsFromText
      "{\"schema\":\"lambda-rogue.settings.v1\",\"animation\":\"yes\"}"))
  check "an unknown schema rejects the settings file"
    (isNothing (settingsFromText
      "{\"schema\":\"lambda-rogue.settings.v2\"}"))
  check "every theme id round-trips"
    (all (\t => themeFromId (themeId t) == Just t) themes)

  c <- newCanvas (the Len 80) (the Len 22)
  let m0 = initModel c sampleGame
      mInventory : Model
      mInventory = { keymap := kmInventory, inventoryOpen := False } m0
  check "the keymap in the model routes a rebound inventory key"
    (isOpenInventory (key mInventory (Press (KChar 'I') noMods)))
  check "the old inventory key is no longer routed"
    (isNothing (key mInventory (Press (KChar 'i') noMods)))

  let potion : Item
      potion = MkItem 2 (Potion PotionHealing) InPack 1 0 False 0 False
      potionGame : Game
      potionGame =
        { player := { inventory := [2] } sampleGame.player
        , items := [potion] } sampleGame
      mQuaff : Model
      mQuaff = { keymap := kmQuaff, inventoryOpen := True,
                 selectedItem := Just 2 } (initModel c potionGame)
  check "inventory actions use the keymap"
    (isQuaffAction (key mQuaff (Press (KChar 'V') noMods)))
  check "the default quaff key no longer acts in this keymap"
    (isNothing (key mQuaff (Press (KChar 'q') noMods)))

  let mDirection : Model
      mDirection = { keymap := kmDirection, inventoryOpen := False,
                     pendingDir := Just (ZapDir 2) } m0
  check "direction prompts use the keymap"
    (isZapEast (key mDirection (Press (KChar 'L') noMods)))

  check "palette hints use the active keymap"
    (case paletteEntryAtIn kmInventory 0 of
       Just e => e.hint == "I"
       Nothing => False)

  let applied = fst (update
        (ApplySettings baseSettings.theme
                       baseSettings.animationsEnabled
                       baseSettings.keymap) m0)
  check "applying settings changes only presentation state"
    (applied.theme == ModernDark
     && not applied.animationsEnabled
     && applied.keymap == baseSettings.keymap)
  check "applying settings keeps the game and replay"
    (gameDigest applied.game == gameDigest m0.game
     && applied.replay.commands == m0.replay.commands)
  check "Save settings returns a file action"
    (case snd (update SaveSettings m0) of
       Perform _ => True
       _ => False)
  check "Reload settings returns a load action"
    (case snd (update ReloadSettings m0) of
       Perform _ => True
       _ => False)

  let testPath = "/tmp/opencode/lambda-rogue-settings-test.json"
  saved <- saveSettingsAt testPath baseSettings
  loaded <- loadSettingsAt testPath
  check "settings save to and load from a file"
    (saved && loaded == baseSettings)
  missing <- loadSettingsAt "/tmp/opencode/lambda-rogue-missing-settings.json"
  check "a missing settings file falls back to defaults"
    (missing == defaultSettings)
  _ <- removeFile testPath
  pure ()

  putStrLn "settings tests passed"
