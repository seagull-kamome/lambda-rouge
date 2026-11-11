||| M1 screen tests: the classic 80x24 and wide 120x40 layouts.
module ViewTest

import Data.List
import LambdaRogue.App.Canvas
import LambdaRogue.App.Keymap
import LambdaRogue.App.Model
import LambdaRogue.App.View
import LambdaRogue.Core.Dungeon
import LambdaRogue.Core.Game
import LambdaRogue.Core.Message
import LambdaRogue.Core.Replay
import LambdaRogue.Core.Rng
import LambdaRogue.Core.Types
import LambdaRogue.UI.Animation
import LambdaRogue.UI.Theme
import System
import TermUI.Canvas
import TermUI.Frame
import TermUI.Input
import TermUI.Len
import TermUI.Width

check : String -> Bool -> IO ()
check name ok =
  if ok
     then putStrLn ("ok   " ++ name)
     else do
       putStrLn ("FAIL " ++ name)
       exitFailure

contains : String -> String -> Bool
contains needle hay = isInfixOf (unpack needle) (unpack hay)

renderLines : Len -> Len -> Model -> IO (List String)
renderLines w h m = do
  frame <- render (view m) w h
  frameLines frame

public export
run : IO ()
run = do
  c80 <- newCanvas (the Len 80) (the Len 22)
  drawMap c80 sampleGame
  let m80 = MkModel c80 sampleGame 80 24 False Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  lines80 <- renderLines 80 24 m80
  check "80x24 has 24 lines" (length lines80 == 24)
  check "80x24 starts with the latest message"
    (case lines80 of
       (l :: _) => contains "Welcome to lambda-rogue" l
       [] => False)

  let mHover : Model
      mHover = { hover := Just (MkCoord 4 5) } m80
  hoverLines <- renderLines 80 24 mHover
  check "a hovered cell replaces the latest message with a tooltip"
    (case hoverLines of
       (l :: _) => contains "Hover" l && contains "you" l
       [] => False)
  check "80x24 shows the map"
    (any (\l => contains "#" l && contains "@" l) lines80)
  check "80x24 status line has the depth and HP"
    (case reverse lines80 of
       (l :: _) => contains "Dlvl 1" l && contains "HP 12/12" l
       [] => False)

  c120 <- newCanvas (the Len 80) (the Len 22)
  drawMap c120 sampleGame
  let m120 = MkModel c120 sampleGame 120 40 False Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  lines120 <- renderLines 120 40 m120
  check "120x40 has 40 lines" (length lines120 == 40)
  check "120x40 header has the seed and turn"
    (case lines120 of
       (l :: _) => contains "Seed" l && contains "Turn 0" l
       [] => False)
  check "120x40 sidebar has the HP bar and keys"
    (any (\l => contains "HP 12/12" l && contains "[" l) lines120
     && any (\l => contains "hjkl/yubn move" l) lines120)
  check "120x40 log contains the welcome message"
    (any (\l => contains "Welcome to lambda-rogue" l) lines120)
  check "120x40 status line has the depth"
    (case reverse lines120 of
       (l :: _) => contains "Dlvl 1" l
       [] => False)
  let mDark = { theme := ModernDark } m120
  darkLines <- renderLines 120 40 mDark
  check "the wide header names the active theme"
    (any (\l => contains "Theme Modern Dark" l) darkLines)

  let mSmall = MkModel c80 sampleGame 40 10 False Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  small <- renderLines 40 10 mSmall
  check "a small terminal shows the size warning"
    (any (\l => contains "Terminal too small" l) small)

  let invItem : Item
      invItem = MkItem 1 (Food FoodRation) InPack 1 0 False 0 False
      pInv : Player
      pInv = { inventory := [1] } sampleGame.player
      gInv : Game
      gInv = { player := pInv, items := [invItem] } sampleGame
      mInv = MkModel c80 gInv 80 24 True Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  invLines <- renderLines 80 24 mInv
  check "inventory mode shows the pack title"
    (any (\l => contains "Inventory  1/23" l) invLines)
  check "inventory mode lists the item"
    (any (\l => contains "a   food ration" l) invLines)
  check "inventory mode keeps the status line"
    (case reverse invLines of
       (l :: _) => contains "Dlvl 1" l
       [] => False)

  let ids : List ItemId
      ids = map (\n : Nat => cast n) [1 .. 23]
      manyItems : List Item
      manyItems = map (\i => MkItem i (Food FoodRation) InPack 1 0 False 0 False) ids
      pMany : Player
      pMany = { inventory := ids } sampleGame.player
      gMany : Game
      gMany = { player := pMany, items := manyItems } sampleGame
      mMany = MkModel c80 gMany 80 24 True Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  manyLines <- renderLines 80 24 mMany
  check "the classic inventory shows all 23 pack slots"
    (any (\l => contains "a   food ration" l) manyLines
     && any (\l => contains "w   food ration" l) manyLines)

  let ringItem = MkItem 20 (Ring RingProtection) InPack 1 2 False 0 False
      wandItem = MkItem 21 (Wand WandLight) InPack 1 0 False 5 False
      pRing : Player
      pRing = { inventory := [20, 21], leftRing := Just 20 }
                sampleGame.player
      gRing : Game
      gRing = { player := pRing, items := [ringItem, wandItem]
              , knownKinds := [Ring RingProtection, Wand WandLight] }
                sampleGame
      mRing = MkModel c80 gRing 80 24 True Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  ringLines <- renderLines 80 24 mRing
  check "inventory marks a worn ring"
    (any (\l => contains "*" l && contains "ring of protection +2" l) ringLines)
  check "a known wand shows its charges"
    (any (\l => contains "wand of light (5 charges)" l) ringLines)

  let gUnknownWand : Game
      gUnknownWand = { player := { inventory := [21] } sampleGame.player
                     , items := [wandItem] } sampleGame
      mUnknownWand = MkModel c80 gUnknownWand 80 24 True Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  unknownLines <- renderLines 80 24 mUnknownWand
  check "an unidentified wand shows its appearance"
    (any (\l => contains "oak wand" l) unknownLines)
  check "an unidentified wand hides its charges"
    (not (any (\l => contains "charges" l) unknownLines))

  let mWideRing = MkModel c120 gRing 120 40 False Nothing Nothing Nothing False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  wideRingLines <- renderLines 120 40 mWideRing
  check "the wide sidebar shows both ring slots"
    (any (\l => contains "Rings: ring of protection +2 / none" l)
         wideRingLines)

  let mPrompt = MkModel c80 sampleGame 80 24 False Nothing Nothing
                  (Just (ZapDir 1)) False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  promptLines <- renderLines 80 24 mPrompt
  check "the direction prompt replaces the latest message"
    (case promptLines of
       (l :: _) => contains "Zap in which direction?" l
       [] => False)

  let mHelp = MkModel c80 sampleGame 80 24 False Nothing Nothing Nothing
                True False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  helpScreen <- renderLines 80 24 mHelp
  check "help shows its title"
    (any (\l => contains "lambda-rogue help" l) helpScreen)
  check "help lists the command palette key"
    (any (\l => contains "Ctrl-P" l) helpScreen)
  check "help lists the theme key"
    (any (\l => contains "F3" l) helpScreen)
  check "help lists the animation key"
    (any (\l => contains "F4" l) helpScreen)
  check "help mentions the mouse"
    (any (\l => contains "Mouse" l) helpScreen)
  check "help lists the search command"
    (any (\l => contains "search" l) helpScreen)
  check "help shows how to close it"
    (any (\l => contains "closes this help" l) helpScreen)

  let mWideHelp = MkModel c120 sampleGame 120 40 False Nothing Nothing
                    Nothing True False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  wideHelp <- renderLines 120 40 mWideHelp
  check "wide help includes the symbol legend"
    (any (\l => contains "A-Z monsters" l) wideHelp)
  check "wide help includes the amulet objective"
    (any (\l => contains "Amulet is on depth 26" l) wideHelp)
  check "wide help names the settings file"
    (any (\l => contains "settings.json" l) wideHelp)
  check "wide help explains replay seeking"
    (any (\l => contains "Left/Right seek" l) wideHelp)
  check "wide help lists accessibility switches"
    (any (\l => contains "NO_COLOR" l) wideHelp)

  let reboundHelp : Keymap
      reboundHelp = setBindingKeys Help [MkKeyChord (KChar 'H') noMods]
                                 defaultKeymap
      mReboundHelp : Model
      mReboundHelp = { keymap := reboundHelp } mHelp
  reboundHelpLines <- renderLines 80 24 mReboundHelp
  check "help follows a rebound key"
    (any (\l => contains "H / Ctrl-P" l) reboundHelpLines)
  check "help no longer shows the old help key"
    (not (any (\l => contains "? / F1 / Ctrl-P" l) reboundHelpLines))

  let mPalette = MkModel c80 sampleGame 80 24 False Nothing Nothing Nothing
                   False True 2 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  paletteScreen <- renderLines 80 24 mPalette
  check "the palette shows its title"
    (any (\l => contains "Command palette" l) paletteScreen)
  check "the palette lists commands"
    (any (\l => contains "Inventory" l) paletteScreen)
  check "the palette lists the theme command"
    (any (\l => contains "Cycle theme" l) paletteScreen)
  check "the palette lists the animation command"
    (any (\l => contains "Toggle animation" l) paletteScreen)
  check "the palette lists the language command"
    (any (\l => contains "Switch language" l) paletteScreen)
  check "the palette lists the animation speed command"
    (any (\l => contains "Cycle animation speed" l) paletteScreen)
  check "the palette lists the replay browser command"
    (any (\l => contains "Replay browser" l) paletteScreen)
  check "the palette shows the active animation speed"
    (any (\l => contains "Cycle animation speed" l
                  && contains "normal" l) paletteScreen)
  check "palette rows use terminal column widths"
    (case find (\e => case e.action of
                        SwitchLanguage => True
                        _ => False)
               (paletteEntriesForLang Japanese defaultKeymap) of
       Just e => stringWidth (paletteRowText mPalette (0, e)) == 32
       Nothing => False)

  let mWidePalette = { paletteOpen := True, paletteIndex := 0 } m120
  widePalette <- renderLines 120 40 mWidePalette
  check "the wide palette keeps its controls visible"
    (any (\l => contains "Enter run" l) widePalette)
  check "the palette marks the selected entry"
    (any (\l => contains "> Wait one turn" l) paletteScreen)
  check "the palette shows its key hints"
    (any (\l => contains "Enter run" l) paletteScreen)

  let reboundPalette : Keymap
      reboundPalette = setBindingKeys Inventory [MkKeyChord (KChar 'I') noMods]
                                    defaultKeymap
      mReboundPalette : Model
      mReboundPalette = { keymap := reboundPalette } mPalette
  reboundPaletteLines <- renderLines 80 24 mReboundPalette
  check "palette hints follow a rebound key"
    (any (\l => contains "Inventory" l && contains "  I" l)
         reboundPaletteLines)

  let logMessages : List Message
      logMessages =
        [ legacyMessage 3 ItemMsg "You quaff the potion."
        , legacyMessage 2 CombatMsg "You hit the kobold."
        , legacyMessage 1 SystemMsg "Welcome to lambda-rogue."
        ]
      gLog : Game
      gLog = { messages := logMessages } sampleGame
      mCombatClassic = MkModel c80 gLog 80 24 False Nothing Nothing Nothing
                         False False 0 CombatMessages
                         (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  combatClassic <- renderLines 80 24 mCombatClassic
  check "the classic latest line follows the log filter"
    (case combatClassic of
       (l :: _) => contains "You hit the kobold." l
       [] => False)
  check "the classic latest line names the active filter"
    (case combatClassic of
       (l :: _) => contains "[combat]" l
       [] => False)

  let mCombatWide = MkModel c120 gLog 120 40 False Nothing Nothing Nothing
                      False False 0 CombatMessages
                      (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  combatWide <- renderLines 120 40 mCombatWide
  check "the wide log filter keeps combat messages"
    (any (\l => contains "You hit the kobold." l) combatWide)
  check "the wide log filter hides item messages"
    (not (any (\l => contains "You quaff the potion." l) combatWide))
  check "the wide header names the active filter"
    (any (\l => contains "Log combat" l) combatWide)

  check "the wide layout includes the minimap"
    (any (\l => contains "Minimap" l) lines120)
  check "the wide minimap explains what it shows"
    (any (\l => contains "Only explored cells are shown." l) lines120)

  let mWideInv = MkModel c120 gRing 120 40 True (Just 20) Nothing Nothing
                   False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  wideInv <- renderLines 120 40 mWideInv
  check "the wide inventory has a detail pane"
    (any (\l => contains "Item details" l) wideInv)
  check "the detail pane shows the selected item"
    (any (\l => contains "ring of protection +2" l) wideInv)
  check "the detail pane shows the pack slot"
    (any (\l => contains "Slot a" l) wideInv)
  check "the detail pane shows the equipped slot"
    (any (\l => contains "Equipped: left ring" l) wideInv)
  check "the detail pane shows the enchantment"
    (any (\l => contains "Enchantment: +2" l) wideInv)
  check "the detail pane compares ring slots"
    (any (\l => contains "Rings: ring of protection +2 / none" l) wideInv)

  let mWideWand = MkModel c120 gRing 120 40 True (Just 21) Nothing Nothing
                    False False 0 AllMessages (emptyReplay sampleGame.seed) [] False False Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  wideWand <- renderLines 120 40 mWideWand
  check "the detail pane shows known wand charges"
    (any (\l => contains "Charges: 5" l) wideWand)

  let score : Score
      score = MkScore sampleGame.seed 7 5 123 87 1240
                       (Dead (KilledBy Kestrel))
      gWon : Game
      gWon = { over := Just Won } sampleGame
      mScore = MkModel c80 gWon 80 24 False Nothing Nothing Nothing
                 False False 0 AllMessages (emptyReplay sampleGame.seed)
                 [score] True False (Just True) ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  scoreScreen <- renderLines 80 24 mScore
  check "the score screen shows its title"
    (any (\l => contains "Scores" l) scoreScreen)
  check "the score screen lists a completed run"
    (any (\l => contains "dead" l && contains "1240" l) scoreScreen)
  check "the score screen records the cause of death"
    (any (\l => contains "Cause" l) scoreScreen
     && any (\l => contains "killed by a kestrel" l) scoreScreen)
  check "English score columns fill the panel exactly"
    (stringWidth (scoreHeader mScore) == 74
     && stringWidth (scoreRow mScore score) == 74)
  check "the score screen shows the seed"
    (any (\l => contains (seedHex sampleGame.seed) l) scoreScreen)
  check "the score screen reports a verified replay"
    (any (\l => contains "Replay: verified" l) scoreScreen)
  check "the score screen explains how to close"
    (any (\l => contains "Esc, S or Enter closes." l) scoreScreen)
  check "the score screen offers replay playback"
    (any (\l => contains "P replays" l) scoreScreen)
  check "the score screen points at the replay browser"
    (any (\l => contains "F5 lists saved replays" l) scoreScreen)

  let mMismatch = { replayOk := Just False } mScore
  mismatchScreen <- renderLines 80 24 mMismatch
  check "the score screen reports a replay mismatch"
    (any (\l => contains "Replay: MISMATCH" l) mismatchScreen)

  let pb : Playback
      pb = MkPlayback gWon (emptyReplay sampleGame.seed) [] 0 0
                      False NormalPlayback True (Just True) True
      mPlayback : Model
      mPlayback = { playback := Just pb } m80
  playbackScreen <- renderLines 80 24 mPlayback
  check "the playback screen names the replay"
    (any (\l => contains "REPLAY" l) playbackScreen)
  check "the playback screen shows a progress bar"
    (any (\l => contains "REPLAY 0/0" l && contains "[" l) playbackScreen)
  check "the playback screen shows the verification state"
    (any (\l => contains "verified" l) playbackScreen)

  let pbUnchecked : Playback
      pbUnchecked = { verified := Nothing } pb
      mUnchecked : Model
      mUnchecked = { playback := Just pbUnchecked } m80
  uncheckedScreen <- renderLines 80 24 mUnchecked
  check "an unchecked replay says so"
    (any (\l => contains "not checked" l) uncheckedScreen)

  let mBrowser : Model
      mBrowser = { ui := { replayBrowserOpen := True
                         , replayFiles := ["a.replay.json", "b.replay.json"]
                         , replayIndex := 1 } m80.ui } m80
  browserScreen <- renderLines 80 24 mBrowser
  check "the replay browser shows its title"
    (any (\l => contains "Replays" l) browserScreen)
  check "the replay browser lists saved files"
    (any (\l => contains "a.replay.json" l) browserScreen
     && any (\l => contains "b.replay.json" l) browserScreen)
  check "the replay browser marks the selected file"
    (any (\l => contains "> b.replay.json" l) browserScreen)
  check "the replay browser shows its controls"
    (any (\l => contains "Enter play" l) browserScreen)

  let mEmptyBrowser : Model
      mEmptyBrowser = { ui := { replayBrowserOpen := True } m80.ui } m80
  emptyBrowserScreen <- renderLines 80 24 mEmptyBrowser
  check "an empty replay browser says there are no files"
    (any (\l => contains "No saved replays." l) emptyBrowserScreen)

  let mShare = MkModel c80 sampleGame 80 24 False Nothing Nothing Nothing
                 False False 0 AllMessages (emptyReplay sampleGame.seed)
                 [] False True Nothing ClassicCga Nothing [] True Nothing defaultKeymap English defaultUiState
  shareScreen <- renderLines 80 24 mShare
  check "the share screen shows its title"
    (any (\l => contains "Share seed" l) shareScreen)
  check "the share screen shows the seed"
    (any (\l => contains (seedHex sampleGame.seed) l) shareScreen)
  check "the share screen counts recorded commands"
    (any (\l => contains "Recorded commands: 0" l) shareScreen)
  check "the share screen explains copying"
    (any (\l => contains "copies the seed" l) shareScreen)

  let mJa80 = { language := Japanese } m80
  ja80 <- renderLines 80 24 mJa80
  check "Japanese renders the keyed welcome message"
    (case ja80 of
       (l :: _) => contains "lambda-rogueへようこそ" l
       [] => False)
  check "Japanese localizes the classic status line"
    (case reverse ja80 of
       (l :: _) => contains "階 1" l && contains "ターン 0" l
       [] => False)
  let mJaHover = { hover := Just (MkCoord 4 5) } mJa80
  jaHover <- renderLines 80 24 mJaHover
  check "Japanese localizes the hover prefix"
    (case jaHover of
       (l :: _) => contains "カーソル" l
       [] => False)
  let mJaSmall = { language := Japanese } mSmall
  jaSmall <- renderLines 40 10 mJaSmall
  check "Japanese localizes the terminal warning"
    (any (\l => contains "端末が小さすぎる" l) jaSmall)

  let mJa120 = { language := Japanese } m120
  ja120 <- renderLines 120 40 mJa120
  check "Japanese localizes the wide header"
    (case ja120 of
       (l :: _) => contains "シード" l && contains "ターン 0" l
       [] => False)
  check "Japanese localizes the sidebar labels and key hints"
    (any (\l => contains "深さ 1" l) ja120
     && any (\l => contains "操作" l) ja120
     && any (\l => contains "hjkl/yubn 移動" l) ja120)
  check "Japanese localizes the minimap legend"
    (any (\l => contains "ミニマップ" l) ja120
     && any (\l => contains "探索した場所だけ" l) ja120)

  let mJaHelp = { language := Japanese } mHelp
  jaHelp <- renderLines 80 24 mJaHelp
  check "Japanese help uses the localized title"
    (any (\l => contains "lambda-rogue ヘルプ" l) jaHelp)
  check "Japanese help localizes the mouse row"
    (any (\l => contains "マウス" l) jaHelp)
  check "Japanese help keeps the key hints generated from the keymap"
    (any (\l => contains "Ctrl-P" l) jaHelp)

  let mJaPalette = { language := Japanese } mPalette
  jaPalette <- renderLines 80 24 mJaPalette
  check "Japanese palette localizes its title"
    (any (\l => contains "コマンドパレット" l) jaPalette)
  check "Japanese palette localizes command labels"
    (any (\l => contains "持ち物" l) jaPalette
     && any (\l => contains "テーマを切り替え" l) jaPalette
     && any (\l => contains "言語を切り替え" l) jaPalette)
  check "Japanese palette localizes its controls"
    (any (\l => contains "Enterで実行" l) jaPalette)

  let mJaScore = { language := Japanese } mScore
  jaScore <- renderLines 80 24 mJaScore
  check "Japanese score screen localizes the title and result"
    (any (\l => contains "スコア" l) jaScore
     && any (\l => contains "死亡" l) jaScore)
  check "Japanese score screen records the cause of death"
    (any (\l => contains "死因" l) jaScore
     && any (\l => contains "kestrelに殺された" l) jaScore)
  check "Japanese score columns fill the panel exactly"
    (stringWidth (scoreHeader mJaScore) == 74
     && stringWidth (scoreRow mJaScore score) == 74)
  check "Japanese score screen localizes the replay label"
    (any (\l => contains "リプレイ: 検証済み" l) jaScore)

  let mJaShare = { language := Japanese } mShare
  jaShare <- renderLines 80 24 mJaShare
  check "Japanese share screen localizes its title and rules"
    (any (\l => contains "シードを共有" l) jaShare
     && any (\l => contains "同じシード + 同じコマンド" l) jaShare)
  check "Japanese share screen localizes the command count"
    (any (\l => contains "記録済みコマンド: 0" l) jaShare)

  let mJaWideInv = { language := Japanese } mWideInv
  jaWideInv <- renderLines 120 40 mJaWideInv
  check "Japanese inventory localizes the empty ring slot"
    (any (\l => contains "指輪:" l && contains "なし" l) jaWideInv)
  check "Japanese inventory localizes the detail labels"
    (any (\l => contains "アイテムの詳細" l) jaWideInv
     && any (\l => contains "スロット a" l) jaWideInv)

  let mJaCombat = { language := Japanese } mCombatClassic
  jaCombat <- renderLines 80 24 mJaCombat
  check "Japanese log prefixes the localized filter name"
    (case jaCombat of
       (l :: _) => contains "[戦闘]" l
                   && contains "You hit the kobold." l
       [] => False)

  putStrLn "view tests passed"
