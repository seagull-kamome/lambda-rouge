||| Message and UI catalog tests.
|||
||| Core stores a stable key and stable arguments for every game message.
||| These tests prove that the English renderer still reproduces the
||| canonical text, that the Japanese table covers every constructor, and
||| that choosing a language cannot touch the game, RNG or replay.
module CatalogTest

import Data.List
import Data.Maybe
import Data.String
import LambdaRogue.App.Catalog
import LambdaRogue.App.Model
import LambdaRogue.App.Settings
import LambdaRogue.App.Update
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Message
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Types
import LambdaRogue.UI.Theme
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

contains : String -> String -> Bool
contains needle haystack = isInfixOf (unpack needle) (unpack haystack)

public export
run : IO ()
run = do
  let keys = map msgKey sampleMessages
      templateKeys = map fst messageTemplatesJa
      -- One representative per constructor.  Keeping this number explicit
      -- means adding a constructor without a sample and a Japanese
      -- template fails here instead of silently shipping English text.
      messageCount = 141

  check "the sample table has one message per constructor"
    (length sampleMessages == messageCount)
  check "message keys are unique"
    (length keys == length (nub keys))
  check "Japanese templates use unique keys"
    (length templateKeys == length (nub templateKeys))
  check "every message has a Japanese template"
    (all (`elem` templateKeys) keys)
  check "every Japanese template has a message"
    (all (`elem` keys) templateKeys)

  check "English rendering equals the canonical text"
    (all (\msg => renderMessage English (mkMessage 0 SystemMsg msg)
                  == msgEn msg) sampleMessages)
  check "stored text is the canonical English sentence"
    (all (\msg => (mkMessage 0 SystemMsg msg).text == msgEn msg)
         sampleMessages)
  check "every message renders in Japanese"
    (all (\msg => not (null (renderMessage Japanese
                              (mkMessage 0 SystemMsg msg)))) sampleMessages)

  check "Japanese renders damage in argument order"
    (renderMessage Japanese (mkMessage 0 CombatMsg (TakeDamage 3))
     == "あなたは3のダメージを受けた。")
  check "Japanese keeps the lead, monster and damage in order"
    (renderMessage Japanese
       (mkMessage 0 CombatMsg (MonsterTakesDamage ThrownItem Orc 5))
     == "投げたものが当たった！ あなたはorcに5のダメージを与えた。")
  check "Japanese teleport keeps x before y"
    (renderMessage Japanese
       (mkMessage 0 SystemMsg (Teleported (MkCoord 3 4)))
     == "あなたは(3, 4)へテレポートした。")
  check "Japanese death drops the capitalization argument"
    (renderMessage Japanese
       (mkMessage 0 CombatMsg (Die True (KilledBy Orc)))
     == "あなたは死んだ……orcに殺された。")

  check "a legacy message keeps its stored English text"
    (renderMessage Japanese (legacyMessage 0 SystemMsg "old cave text")
     == "old cave text")
  check "an unknown key falls back to stored English text"
    (renderMessage Japanese
       (MkMessage 0 SystemMsg "future-key" [] "future cave text")
     == "future cave text")
  check "English always uses the stored text"
    (renderMessage English
       (MkMessage 0 SystemMsg "future-key" [] "future cave text")
     == "future cave text")

  -- UI text ---------------------------------------------------------------
  check "the UI key table is complete"
    (length allTextKeys == 165)
  check "the language toggle flips both ways"
    (nextLanguage English == Japanese
     && nextLanguage Japanese == English)
  check "every UI key has English and Japanese text"
    (all (\k => not (null (uiText English k))
                && not (null (uiText Japanese k))) allTextKeys)
  check "UI text keeps its English default"
    (uiText English PaletteTitle == "Command palette")
  check "UI text switches to Japanese"
    (uiText Japanese PaletteTitle == "コマンドパレット")
  check "UI arguments render in English order"
    (uiTextArgs English ShareStart ["abc"]
     == "Start with: lambda-rogue --seed abc")
  check "UI arguments render in Japanese order"
    (uiTextArgs Japanese ShareStart ["abc"]
     == "開始: lambda-rogue --seed abc")
  check "the too-small message carries both dimensions"
    (uiTextArgs Japanese TerminalTooSmall ["80", "24"]
     == "端末が小さすぎる: 80x24 が必要、現在 80x24")
  check "localized palette labels keep the canonical English label"
    (case paletteEntriesForLang Japanese defaultKeymap of
       e :: _ => e.label == "持ち物"
                 && (case paletteEntriesForLang English defaultKeymap of
                       x :: _ => x.label == "Inventory"
                       [] => False)
       [] => False)
  check "the palette offers a language switch"
    (case find (\e => case e.action of
                        SwitchLanguage => True
                        _ => False)
               (paletteEntriesForLang English defaultKeymap) of
       Just e => e.label == "Switch language" && e.hint == "ja"
       Nothing => False)
  check "the Japanese palette localizes the language switch"
    (case find (\e => case e.action of
                        SwitchLanguage => True
                        _ => False)
               (paletteEntriesForLang Japanese defaultKeymap) of
       Just e => e.label == "言語を切り替え" && e.hint == "en"
       Nothing => False)

  -- Language isolation ----------------------------------------------------
  c <- newCanvas (the Len 80) (the Len 22)
  let m0 = initModel c sampleGame
      mEn = fst (update (ApplySettings ClassicCga True defaultKeymap English) m0)
      mJa = fst (update (ApplySettings ClassicCga True defaultKeymap Japanese) m0)
  check "switching to Japanese updates only the display language"
    (mEn.language == English && mJa.language == Japanese)
  check "switching language cannot change the game digest"
    (gameDigest mEn.game == gameDigest mJa.game
     && gameDigest mJa.game == gameDigest m0.game)
  check "switching language cannot change the replay"
    (mEn.replay.commands == mJa.replay.commands
     && mJa.replay.commands == m0.replay.commands)

  let mToggled = fst (update SwitchLanguage m0)
  check "the palette message toggles the display language"
    (mToggled.language == Japanese)
  check "the palette language toggle keeps the game digest"
    (gameDigest mToggled.game == gameDigest m0.game)
  check "the palette language toggle keeps the replay"
    (mToggled.replay.commands == m0.replay.commands)

  putStrLn "catalog tests passed"
