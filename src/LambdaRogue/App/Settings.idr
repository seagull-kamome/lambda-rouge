||| Pure `settings.json` values and their JSON form.
|||
||| Settings are presentation only: theme, animation, key bindings.  They
||| never enter `Game`, a `Command`, the RNG, `Replay` or `gameDigest`.
||| Unknown command ids are ignored for forward compatibility; a malformed
||| known value rejects the whole file so a typo cannot silently create a
||| half-applied keymap.
module LambdaRogue.App.Settings

import Data.List
import Data.Maybe
import Language.JSON
import LambdaRogue.App.Catalog
import LambdaRogue.App.Keymap
import LambdaRogue.UI.Animation
import LambdaRogue.UI.Theme

%default covering

public export
record Settings where
  constructor MkSettings
  theme : Theme
  animationsEnabled : Bool
  animationSpeed : AnimationSpeed
  keymap : Keymap
  language : Language

public export
Eq Settings where
  a == b = a.theme == b.theme
           && a.animationsEnabled == b.animationsEnabled
           && a.animationSpeed == b.animationSpeed
           && a.keymap == b.keymap
           && a.language == b.language

public export
defaultSettings : Settings
defaultSettings = MkSettings ClassicCga True NormalAnimation defaultKeymap English

public export
settingsSchema : String
settingsSchema = "lambda-rogue.settings.v1"

asString : JSON -> Maybe String
asString (JString s) = Just s
asString _ = Nothing

asBool : JSON -> Maybe Bool
asBool (JBoolean b) = Just b
asBool _ = Nothing

parseChordJSON : JSON -> Maybe KeyChord
parseChordJSON (JString s) = parseKeyChord s
parseChordJSON _ = Nothing

parseChordList : JSON -> Maybe (List KeyChord)
parseChordList (JString s) = map pure (parseKeyChord s)
parseChordList (JArray xs) = traverse parseChordJSON xs
parseChordList _ = Nothing

applyEntry : Keymap -> (String, JSON) -> Maybe Keymap
applyEntry km (name, value) =
  case commandFromName name of
    Nothing => Just km
    Just cid => do
      ks <- parseChordList value
      pure (setBindingKeys cid ks km)

applyEntries : Keymap -> List (String, JSON) -> Maybe Keymap
applyEntries km [] = Just km
applyEntries km (e :: es) = do
  km' <- applyEntry km e
  applyEntries km' es

parseKeymap : JSON -> Maybe Keymap
parseKeymap (JObject entries) = do
  km <- applyEntries defaultKeymap entries
  if hasDuplicateChords km then Nothing else Just km
parseKeymap _ = Nothing

||| Parse the JSON value.  Missing optional fields keep their defaults.
public export
settingsFromJSON : JSON -> Maybe Settings
settingsFromJSON json@(JObject _) = do
  schema <- lookup "schema" json >>= asString
  if schema /= settingsSchema
     then Nothing
     else do
       theme <- case lookup "theme" json of
                  Nothing => Just ClassicCga
                  Just v => asString v >>= themeFromId
       animations <- case lookup "animation" json of
                       Nothing => Just True
                       Just v => asBool v
       speed <- case lookup "animationSpeed" json of
                  Nothing => Just NormalAnimation
                  Just (JString value) => animationSpeedFromId value
                  Just _ => Nothing
       keymap <- case lookup "keys" json of
                   Nothing => Just defaultKeymap
                   Just v => parseKeymap v
       -- Missing language keeps the documented English default.  An
       -- unknown future id also falls back to English so a newer settings
       -- file still starts this build.
       language <- case lookup "language" json of
                     Nothing => Just English
                     Just (JString value) =>
                       Just (fromMaybe English (languageFromId value))
                     Just _ => Nothing
       pure (MkSettings theme animations speed keymap language)
settingsFromJSON _ = Nothing

public export
settingsFromText : String -> Maybe Settings
settingsFromText text = parse text >>= settingsFromJSON

bindingJSON : Binding -> (String, JSON)
bindingJSON b =
  (commandName b.id, JArray (map (JString . chordText) b.keys))

public export
settingsToJSON : Settings -> JSON
settingsToJSON s =
  JObject
    [ ("schema", JString settingsSchema)
    , ("theme", JString (themeId s.theme))
    , ("animation", JBoolean s.animationsEnabled)
    , ("animationSpeed", JString (animationSpeedId s.animationSpeed))
    , ("language", JString (languageId s.language))
    , ("keys", JObject (map bindingJSON s.keymap))
    ]

||| Two-space indented JSON with a trailing newline, ready to write.
public export
settingsToText : Settings -> String
settingsToText s = format 2 (settingsToJSON s) ++ "\n"
