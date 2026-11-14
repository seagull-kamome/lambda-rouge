||| Presentation language and the message/UI catalog.
|||
||| Core builds `Message` values with a stable key, stable arguments and
||| the canonical English `text`.  This module never feeds a language back
||| into Core: `renderMessage` only picks how the same message is drawn.
||| Therefore `--lang`, `settings.json` and the help screens cannot change
||| `gameDigest`, replays or the save format.
|||
||| English is the default.  Unknown keys and messages from old saves (key
||| `""`) always fall back to their stored English text.
module LambdaRogue.App.Catalog

import Data.List
import Data.Maybe
import Data.String
import LambdaRogue.Core.Message
import LambdaRogue.Core.Survival
import LambdaRogue.Core.Types

%default covering

public export
data Language = English | Japanese

public export
Eq Language where
  English == English = True
  Japanese == Japanese = True
  _ == _ = False

public export
Show Language where
  show English = "English"
  show Japanese = "Japanese"

public export
defaultLanguage : Language
defaultLanguage = English

public export
languageId : Language -> String
languageId English = "en"
languageId Japanese = "ja"

public export
languageFromId : String -> Maybe Language
languageFromId "en" = Just English
languageFromId "ja" = Just Japanese
languageFromId _ = Nothing

||| The language the palette entry switches to.
public export
nextLanguage : Language -> Language
nextLanguage English = Japanese
nextLanguage Japanese = English

||| Names for the values Core keeps language-neutral.
public export
statusName : Language -> StatusKind -> String
statusName English s = show s
statusName Japanese Confused = "混乱"
statusName Japanese Blinded = "目暗まし"
statusName Japanese Hasted = "加速"
statusName Japanese SeeInvisible = "不可視を見る"
statusName Japanese DetectMonsters = "怪物感知"
statusName Japanese DetectFood = "食料感知"
statusName Japanese DetectMagic = "魔法感知"
statusName Japanese Invisible = "透明"
statusName Japanese Poisoned = "毒"
statusName Japanese Held = "拘束"
statusName Japanese Slowed = "鈍足"
statusName Japanese Paralyzed = "麻痺"
statusName Japanese Scared = "恐怖"
statusName Japanese Sleeping = "睡眠"
statusName Japanese Hallucinating = "幻覚"
statusName Japanese Levitated = "浮遊"
statusName Japanese ConfuseNext = "混乱付与"
statusName Japanese Mimicking = "物体擬態"
statusName Japanese Fainted = "気絶"

public export
hungerName : Language -> HungerState -> String
hungerName English h = show h
hungerName Japanese Satiated = "満腹"
hungerName Japanese Normal = "普通"
hungerName Japanese Hungry = "空腹"
hungerName Japanese Weak = "虚弱"
hungerName Japanese Fainting = "卒倒"

public export
deathName : Language -> DeathCause -> String
deathName English cause = show cause
deathName Japanese (KilledBy kind) = monsterName kind ++ "に殺された"
deathName Japanese (KilledByTrap kind) = show kind ++ "で死んだ"
deathName Japanese Starved = "飢え死にした"
deathName Japanese Drained = "生命力を吸い尽くされた"
deathName Japanese (OtherDeath text) = text

public export
monsterStateName : Language -> MonsterState -> String
monsterStateName English s = show s
monsterStateName Japanese Asleep = "眠り"
monsterStateName Japanese Awake = "目覚め"
monsterStateName Japanese Chasing = "追跡"
monsterStateName Japanese Fleeing = "逃走"

-- Templates ---------------------------------------------------------------

||| Replace each `{}` with the next argument.  Missing arguments become an
||| empty string, so a partially translated or damaged message can never
||| crash the UI.
public export
renderTemplate : String -> List String -> String
renderTemplate template args = go (unpack template) args ""
  where
    go : List Char -> List String -> String -> String
    go [] _ acc = acc
    go ('{' :: '}' :: rest) (arg :: more) acc =
      go rest more (acc ++ arg)
    go ('{' :: '}' :: rest) [] acc = go rest [] acc
    go (c :: rest) as acc = go rest as (acc ++ pack [c])

-- Game messages ------------------------------------------------------------

||| Split at the first colon, returning an empty tail when there is none.
splitColon : String -> (String, String)
splitColon s =
  case span (/= ':') (unpack s) of
    (a, ':' :: b) => (pack a, pack b)
    (a, _) => (pack a, "")

dieCauseJa : String -> String
dieCauseJa cause =
  let (tag, name) = splitColon cause
  in case tag of
       "monster" => name ++ "に殺された"
       "trap" => name ++ "で死んだ"
       "other" => name
       "starved" => "飢え死にした"
       "drained" => "生命力を吸い尽くされた"
       _ => cause

leadJa : String -> String
leadJa "none" = ""
leadJa "lightning" = "稲妻が走った！ "
leadJa "fire" = "炎の矢が放たれた！ "
leadJa "cold" = "冷気が吹き荒れた！ "
leadJa "magic-missile" = "魔法の矢が飛んでいった！ "
leadJa "drain" = "杖が命を吸い取った！ "
leadJa "thrown" = "投げたものが当たった！ "
leadJa lead =
  let (tag, name) = splitColon lead
  in case tag of
       "breath" => name ++ "が炎を吐いた！ "
       "arrow" => name ++ "が矢を放った！ "
       _ => ""

rustLeadJa : String -> String
rustLeadJa "trap" = "錆びた罠が鎧を腐食させた。"
rustLeadJa src =
  let (tag, name) = splitColon src
  in case tag of
       "monster" => name ++ "が鎧を腐食させた。"
       _ => "鎧が腐食した。"

trapNameJa : String -> String
trapNameJa "trapdoor" = "落とし戸"
trapNameJa "arrow trap" = "矢の罠"
trapNameJa "sleeping gas" = "睡眠ガスの罠"
trapNameJa "bear trap" = "熊罠"
trapNameJa "teleport trap" = "テレポートの罠"
trapNameJa "dart trap" = "吹き矢の罠"
trapNameJa "rust trap" = "錆の罠"
trapNameJa "mysterious trap" = "謎の罠"
trapNameJa other = other

statusExpiryJa : String -> String
statusExpiryJa "confused" = "混乱が解けた。"
statusExpiryJa "blinded" = "目が見えるようになった。"
statusExpiryJa "hasted" = "体の動きが元に戻った。"
statusExpiryJa "see invisible" = "目が正常に戻った。"
statusExpiryJa "detect monsters" = "感覚が正常に戻った。"
statusExpiryJa "detect food" = "食料の気配が消えた。"
statusExpiryJa "detect magic" = "魔法の気配が消えた。"
statusExpiryJa "invisible" = "透明でなくなった。"
statusExpiryJa "poisoned" = "毒が抜けた。"
statusExpiryJa "held" = "再び動けるようになった。"
statusExpiryJa "slowed" = "体の動きが正常に戻った。"
statusExpiryJa "paralyzed" = "再び動けるようになった。"
statusExpiryJa "scared" = "勇気が戻った。"
statusExpiryJa "sleeping" = "目を覚ました。"
statusExpiryJa "hallucinating" = "すべてが正常に見える。"
statusExpiryJa "levitated" = "ゆっくり床に降りた。"
statusExpiryJa "confuse next" = "手の光が消えた。"
statusExpiryJa "fainted" = "意識を取り戻した。"
statusExpiryJa other = other

stairNameJa : String -> String
stairNameJa "up" = "上"
stairNameJa "down" = "下"
stairNameJa other = other

identifyGroupJa : String -> String
identifyGroupJa "potions" = "ポーション"
identifyGroupJa "scrolls" = "巻物"
identifyGroupJa "weapons" = "武器"
identifyGroupJa "armor" = "鎧"
identifyGroupJa "rings or wands" = "指輪や杖"
identifyGroupJa other = other

||| Adapt stable arguments that are tokens rather than display text.
adjustArgs : String -> List String -> List String
adjustArgs "die" (_ :: cause :: _) = [dieCauseJa cause]
adjustArgs "kill-monster" (lead :: kind :: _) = [leadJa lead, kind]
adjustArgs "monster-takes-damage" (lead :: kind :: dmg :: _) =
  [leadJa lead, kind, dmg]
adjustArgs "ranged-hit" (lead :: dmg :: _) = [leadJa lead, dmg]
adjustArgs "ranged-miss" (lead :: _) = [leadJa lead]
adjustArgs "armor-unaffected" (src :: _) = [rustLeadJa src]
adjustArgs "armor-weakens" (src :: item :: _) =
  [rustLeadJa src, item]
adjustArgs "hit-monster" (kind :: dmg :: confused :: _) =
  [kind, dmg, if confused == "yes" then kind ++ "は混乱した。" else ""]
adjustArgs "throw-item" (name :: shatters :: _) =
  [name, if shatters == "yes" then "それは砕けた。" else ""]
adjustArgs "found-trap" (kind :: _) = [trapNameJa kind]
adjustArgs "trigger-trap" (kind :: _) = [trapNameJa kind]
adjustArgs "not-on-stairs" (dir :: _) = [stairNameJa dir]
adjustArgs "no-unidentified" (what :: _) = [identifyGroupJa what]
adjustArgs "status-expires" (status :: _) = [statusExpiryJa status]
adjustArgs _ args = args

||| Japanese templates keyed by the same stable keys as `Core.Message`.
public export
messageTemplatesJa : List (String, String)
messageTemplatesJa =
  [ ("damage", "あなたは{}のダメージを受けた。")
  , ("die", "あなたは死んだ……{}。")
  , ("welcome-level", "レベル{}に上がった！")
  , ("armor-unaffected", "{} 鎧は影響を受けなかった。")
  , ("armor-protected", "鎧は錆から守られている。")
  , ("armor-weakens", "{} あなたの{}が弱った。")
  , ("kill-monster", "{}あなたは{}を倒した。")
  , ("monster-takes-damage", "{}あなたは{}に{}のダメージを与えた。")
  , ("monster-resists", "怪物は抵抗した。")
  , ("monster-vanishes", "{}は消え去った。")
  , ("monster-appears", "{}が現れた！")
  , ("scroll-fizzles", "巻物は不発に終わった。")
  , ("miss-monster", "あなたは{}を外した。")
  , ("hit-monster", "あなたは{}に{}のダメージを与えた。{}")
  , ("kill-monster-plain", "あなたは{}を倒した。")
  , ("found-secret-door", "隠し扉を見つけた。")
  , ("open-door", "扉を開けた。")
  , ("trigger-trap", "{}を作動させてしまった。")
  , ("teleport-fizzles", "テレポートの罠は不発だった。")
  , ("teleported", "あなたは({}, {})へテレポートした。")
  , ("cannot-descend", "これ以上下へは進めない。")
  , ("descend-level", "レベル{}へ降りた。")
  , ("win-game", "アミュレット・オブ・イェンドールを持って地上へ戻った！ 勝利！")
  , ("cannot-return", "アミュレット・オブ・イェンドールなしでは戻れない。")
  , ("ascend-level", "レベル{}へ上がった。")
  , ("way-up-blocked", "上への道は塞がれている。")
  , ("strength-holds", "弱ったが、力は保たれている。")
  , ("feel-weaker", "弱くなった気がする。")
  , ("bear-trap", "熊罠が足に食い込んだ！")
  , ("fall-asleep", "あなたは眠りに落ちた。")
  , ("float-over-trap", "あなたは罠の上を浮かんで通過した。")
  , ("strange-noise", "遠くで奇妙な音が聞こえる。")
  , ("found-trap", "{}を見つけた。")
  , ("found-trap-unknown", "罠を見つけた。")
  , ("search-nothing", "探したが何も見つからなかった。")
  , ("held-in-place", "その場に拘束されている。")
  , ("wall-there", "そこは壁だ。")
  , ("door-locked", "扉には鍵がかかっている。")
  , ("not-on-stairs", "{}への階段の上に立っていない。")
  , ("nothing-here", "ここには拾えるものがない。")
  , ("pick-up-gold", "{}ゴールドを拾った。")
  , ("pick-up-amulet", "アミュレット・オブ・イェンドールを拾った！")
  , ("pick-up-item", "{}を拾った。")
  , ("pack-full", "持ち物が一杯だ。")
  , ("feel-better", "気分が良くなった。")
  , ("feel-much-better", "とても気分が良くなった。")
  , ("already-strong", "すでに十分に強い。")
  , ("feel-stronger", "力が強くなった。")
  , ("strength-returns", "力が戻った。")
  , ("sick-strength-holds", "少し気分が悪いが、力は保たれている。")
  , ("weaker-head-clears", "弱くなったが、頭はすっきりした。")
  , ("feel-confused", "頭が混乱してきた。")
  , ("everything-strange", "なんてこった！ すべてが奇妙に見える。")
  , ("blinded", "目が見えなくなった。")
  , ("sense-monsters", "怪物の気配を感じる。")
  , ("sense-magic", "魔法の気配を感じる。")
  , ("moving-faster", "体の動きが速くなった。")
  , ("eyes-strange", "目が奇妙な感じになった。")
  , ("float", "ふわりと宙に浮いた。")
  , ("more-experienced", "経験を積んだ気がする。")
  , ("no-such-item", "そのアイテムを持っていない。")
  , ("cannot-quaff", "それは飲めない。")
  , ("quaff-item", "{}を飲んだ。")
  , ("cannot-eat", "それは食べられない。")
  , ("eat-ration", "保存食を食べた。満足した。")
  , ("already-wearing-ring", "その指輪はすでにはめている。")
  , ("fingers-full", "指はすでに塞がっている。")
  , ("cannot-put-on", "それは身につけられない。")
  , ("identify-item", "{}の正体を見破った。")
  , ("no-unidentified", "識別できる{}はなかった。")
  , ("hands-glow-red", "手が赤く光り始めた。")
  , ("map-forms", "この階の地図が頭に浮かんだ。")
  , ("monsters-freeze", "怪物たちが凍りついた。")
  , ("monsters-sleep", "怪物たちは眠りに落ちた。")
  , ("monsters-flee", "怪物たちは逃げ出した。")
  , ("sense-food", "近くに食料の気配を感じる。")
  , ("not-wearing-armor", "鎧を着ていない。")
  , ("armor-glows-silver", "あなたの{}が銀色に光った。")
  , ("not-wielding-weapon", "武器を持っていない。")
  , ("weapon-glows-blue", "あなたの{}が青く光った。")
  , ("surge-of-relief", "安堵の気持ちが広がった。")
  , ("growl-everywhere", "四方八方から唸り声が聞こえる。")
  , ("armor-feels-protected", "あなたの{}は守られている気がする。")
  , ("cannot-read", "それは読めない。")
  , ("read-scroll", "{}を読んだ。")
  , ("beam-fizzles", "光線は不発に終わった。")
  , ("wand-floods-light", "杖が部屋を光で満たした。")
  , ("fade-out-of-sight", "姿が見えなくなった。")
  , ("monster-polymorphs", "{}は{}になった！")
  , ("monster-speeds-up", "{}は速くなった！")
  , ("monster-slows-down", "{}は遅くなった。")
  , ("nothing-happens", "何も起こらなかった。")
  , ("monster-ordinary", "{}は元の姿に戻った。")
  , ("wand-sputters", "杖は火花を散らしただけだった。")
  , ("zap-wand", "{}を振った。")
  , ("cannot-zap", "それは振れない。")
  , ("take-off-before-throwing", "投げる前に外さなければならない。")
  , ("throw-item", "あなたは{}を投げた。{}")
  , ("already-wielding", "それはすでに持っている。")
  , ("weapon-welded", "武器が手に溶接されて離れない！")
  , ("weapon-welds-to-hand", "{}が手に溶接された！")
  , ("cannot-wield", "それは武器として使えない。")
  , ("wield-item", "{}を装備した。")
  , ("ring-tightens", "指輪が指にきつく食い込んだ！")
  , ("put-on-ring", "{}をはめた。")
  , ("already-wearing-armor", "その鎧はすでに着ている。")
  , ("armor-tightens", "{}が体にきつく食い込んだ！")
  , ("wear-armor", "{}を着た。")
  , ("cannot-wear", "それは着られない。")
  , ("cannot-remove-cursed-armor", "呪われた鎧は外せない！")
  , ("cannot-remove-cursed-ring", "呪われた指輪は外せない！")
  , ("take-off-item", "{}を外した。")
  , ("not-wearing-that", "それは身につけていない。")
  , ("cannot-let-go-cursed", "呪われたアイテムは手放せない！")
  , ("drop-item", "{}を落とした。")
  , ("monster-finds-no-gold", "{}は奪うゴールドを見つけられなかった。")
  , ("monster-snatches-gold", "{}が{}ゴールドを奪って消えた！")
  , ("monster-finds-nothing", "{}は奪うものを見つけられなかった。")
  , ("monster-snatches-item", "{}があなたの{}を奪って消えた！")
  , ("monster-freezes-you", "{}があなたを凍らせた！")
  , ("monster-holds-you", "{}があなたを拘束した！")
  , ("monster-drains-max-hp", "{}が最大HPを{}吸い取った！")
  , ("monster-tries-weaken", "{}はあなたを弱めようとしたが、力は保たれた。")
  , ("monster-weakens-you", "{}があなたを弱らせた！")
  , ("monster-drains-life-force", "{}があなたの生命力を吸い取った！")
  , ("monster-corrodes-armor", "{}があなたの鎧を腐食させた。")
  , ("monster-misses", "{}は外した。")
  , ("monster-hits-you", "{}があなたに{}のダメージを与えた。")
  , ("monster-opens-door", "{}が扉を開けた。")
  , ("monster-wakes-up", "{}が目を覚ました。")
  , ("ranged-miss", "{}あなたはかわした。")
  , ("ranged-hit", "{}あなたは{}のダメージを受けた。")
  , ("ring-hums", "指輪が唸り、世界が変わった。")
  , ("you-are-asleep", "あなたは眠っている。")
  , ("you-are-paralyzed", "あなたは麻痺している。")
  , ("status-expires", "{}")
  , ("hungry", "腹が減った。")
  , ("weak-from-hunger", "空腹で弱っている。")
  , ("faint-from-hunger", "食料不足で気を失った。")
  , ("welcome", "lambda-rogueへようこそ。hjkl/yubnで移動、.で待機、,で拾う、>で降りる、iで持ち物、qで飲む。")
  , ("resumed-from-save", "セーブから再開した。")
  , ("recovered-from-autosave", "オートセーブから復元した。")
  ]

||| Render one stored message.  English always uses the saved canonical
||| text; Japanese uses the keyed template and falls back to that text for
||| legacy or unknown keys.
public export
messageJa : Message -> String
messageJa m =
  if m.key == ""
     then m.text
     else case lookup m.key messageTemplatesJa of
            Nothing => m.text
            Just template => renderTemplate template
                               (adjustArgs m.key m.args)

public export
renderMessage : Language -> Message -> String
renderMessage English m = m.text
renderMessage Japanese m = messageJa m

-- UI text ----------------------------------------------------------------

public export
data TextKey
  = Brand
  | LabelDepth | LabelDlvl | LabelLevel | LabelHp | LabelStrength | LabelGold
  | LabelExp | LabelTurn | LabelFood | LabelLog | LabelTheme | LabelSeed
  | LabelStatus | LabelKeys | LabelWeapon | LabelArmor | LabelRings
  | LabelVisible | LabelExplored | LabelRooms | LabelTraps | LabelPos
  | StatusNone | MonstersNone | MonsterSummary | ItemNone | ItemFloor
  | ItemPack | ItemCarried | Dead | Won | Hover
  | ReplayBar | ReplaySlow | ReplayNormal | ReplayFast | ReplayComplete
  | ReplayPlaying | ReplayPaused | ReplayVerified | ReplayMismatch
  | ReplayControls
  | ReplayBrowserTitle | ReplayBrowserEmpty | ReplayBrowserControls
  | ReplayBrowserError
  | LogAll | LogCombat | LogItems | LogSystem | LogWarnings | NoMessages
  | ZapPrompt | ThrowPrompt
  | Minimap | MinimapYou | MinimapSymbols | MinimapOnlyExplored
  | InventoryTitle | InventoryEquippedNote | PackEmpty | EmptySlot | ItemDetails
  | Slot | Equipped | InPack | ProtectedFromTheft | EnterUses | SelectSlot
  | InventoryHelp1 | InventoryHelp2
  | CategoryWeapon | CategoryArmor | CategoryFood | CategoryPotion
  | CategoryScroll | CategoryWand | CategoryRing | CategoryGold | CategoryAmulet
  | Enchantment | CursedCannotRemove | Unidentified | Charges | AmountGold
  | Wielded | Worn | LeftRing | RightRing | WieldedLabel | WornLabel
  | RingsLabel
  | HelpTitle | HelpClose | HelpMovement | HelpMove | HelpWaitSearchPickUp
  | HelpStairs | HelpItems | HelpInventory | HelpQuaffReadEat | HelpWieldWear
  | HelpPutOnTakeOff | HelpZapThrow | HelpDrop | HelpInterface
  | HelpHelpPalette | HelpLogThemeAnimation | HelpRedraw | HelpScoresShare
  | HelpQuit | HelpMouse | HelpSymbols | HelpSymbols1 | HelpSymbols2
  | HelpSymbols3 | HelpTactics | HelpSettings | HelpPaletteHint
  | HelpUnbound | HelpArrows | HelpReplay | HelpAccessibility
  | PaletteTitle | PaletteControls
  | Scores | ScoresSubtitle | ScoreDepth | ScoreLv | ScoreExp | ScoreGold
  | ScoreTurns | ScoreResult | ScoreCause | ResultWon | ResultDead | NoScores
  | NotChecked | Verified | Mismatch | ScoreSeed | ScoreReplay | ScoreControls
  | ShareTitle | ShareSeed | ShareGive | ShareRule | ShareStart
  | ShareDepthLine | ShareCommands | ShareReplay | ShareCopy | ShareClose
  | EquippedNone
  | KeysMove | KeysPickUpDescend | KeysReadZapThrow | KeysTakeOffRedrawQuit
  | KeysHelpLogTheme | KeysScoresShare | KeysMouse | HelpMouseLabel
  | MissingSeedValue | InvalidSeedValue | MissingLangValue | InvalidLangValue
  | MissingThemeValue | InvalidThemeValue
  | TerminalTooSmall | AppAlreadyRunning | AppNeedsTerminal | Bye

uiEn : TextKey -> String
uiEn Brand = "lambda-rogue"
uiEn LabelDepth = "Depth"
uiEn LabelDlvl = "Dlvl"
uiEn LabelLevel = "Lv"
uiEn LabelHp = "HP"
uiEn LabelStrength = "Str"
uiEn LabelGold = "Gold"
uiEn LabelExp = "Exp"
uiEn LabelTurn = "Turn"
uiEn LabelFood = "Food"
uiEn LabelLog = "Log"
uiEn LabelTheme = "Theme"
uiEn LabelSeed = "Seed"
uiEn LabelStatus = "Status"
uiEn LabelKeys = "Keys"
uiEn LabelWeapon = "Weapon"
uiEn LabelArmor = "Armor"
uiEn LabelRings = "Rings"
uiEn LabelVisible = "Visible"
uiEn LabelExplored = "Explored"
uiEn LabelRooms = "Rooms"
uiEn LabelTraps = "Traps"
uiEn LabelPos = "Pos"
uiEn StatusNone = "Status: none"
uiEn MonstersNone = "Monsters: none"
uiEn MonsterSummary = "Monsters: {}  {} ({}) {}"
uiEn ItemNone = "Item: none"
uiEn ItemFloor = "Item: {} {}"
uiEn ItemPack = "Item: {} (pack)"
uiEn ItemCarried = "Item: {} (carried)"
uiEn Dead = "  DEAD: {}"
uiEn Won = "  WON"
uiEn Hover = "Hover {}"
uiEn ReplayBar = "REPLAY {}/{}"
uiEn ReplaySlow = "slow"
uiEn ReplayNormal = "normal"
uiEn ReplayFast = "fast"
uiEn ReplayComplete = "complete"
uiEn ReplayPlaying = "playing"
uiEn ReplayPaused = "paused"
uiEn ReplayVerified = "verified"
uiEn ReplayMismatch = "MISMATCH"
uiEn ReplayControls = "Space . -/+ Left/Right Home/End R Esc"
uiEn ReplayBrowserTitle = "Replays"
uiEn ReplayBrowserEmpty = "No saved replays."
uiEn ReplayBrowserControls = "Up/Down or j/k move   Enter play   r refresh   Esc close"
uiEn ReplayBrowserError = "Could not load this replay."
uiEn LogAll = "all"
uiEn LogCombat = "combat"
uiEn LogItems = "items"
uiEn LogSystem = "system"
uiEn LogWarnings = "warnings"
uiEn NoMessages = "(no {} messages)"
uiEn ZapPrompt = "Zap in which direction?  hjkl/yubn or arrows, Esc cancels"
uiEn ThrowPrompt = "Throw in which direction?  hjkl/yubn or arrows, Esc cancels"
uiEn Minimap = "Minimap"
uiEn MinimapYou = "@ you   < > stairs"
uiEn MinimapSymbols = "+ door   # wall   . floor"
uiEn MinimapOnlyExplored = "Only explored cells are shown."
uiEn InventoryTitle = "Inventory  {}/{}"
uiEn InventoryEquippedNote = "Equipped items are marked with *."
uiEn PackEmpty = "The pack is empty."
uiEn EmptySlot = "(empty)"
uiEn ItemDetails = "Item details"
uiEn Slot = "Slot {}"
uiEn Equipped = "Equipped: {}"
uiEn InPack = "In pack"
uiEn ProtectedFromTheft = "Protected from theft"
uiEn EnterUses = "Enter uses this item."
uiEn SelectSlot = "a-z selects another slot."
uiEn InventoryHelp1 = "a-z select  Enter use  q quaff  r read  e eat  w wield"
uiEn InventoryHelp2 = "W wear  P put on  R/T take off  z zap  t throw  d drop  Esc"
uiEn CategoryWeapon = "weapon"
uiEn CategoryArmor = "armor"
uiEn CategoryFood = "food"
uiEn CategoryPotion = "potion"
uiEn CategoryScroll = "scroll"
uiEn CategoryWand = "wand"
uiEn CategoryRing = "ring"
uiEn CategoryGold = "gold"
uiEn CategoryAmulet = "amulet"
uiEn Enchantment = "Enchantment: {}"
uiEn CursedCannotRemove = "Cursed: cannot remove"
uiEn Unidentified = "Unidentified: effects hidden"
uiEn Charges = "Charges: {}"
uiEn AmountGold = "Amount: {} gold"
uiEn Wielded = "wielded"
uiEn Worn = "worn"
uiEn LeftRing = "left ring"
uiEn RightRing = "right ring"
uiEn WieldedLabel = "Wielded: {}"
uiEn WornLabel = "Worn: {}"
uiEn RingsLabel = "Rings: {}"
uiEn HelpTitle = "lambda-rogue help"
uiEn HelpClose = "Esc, ? or F1 closes this help."
uiEn HelpMovement = "Movement"
uiEn HelpMove = "move (8 directions)"
uiEn HelpWaitSearchPickUp = "wait / search / pick up"
uiEn HelpStairs = "descend / ascend stairs"
uiEn HelpItems = "Items"
uiEn HelpInventory = "inventory (a-z, Enter)"
uiEn HelpQuaffReadEat = "quaff / read / eat"
uiEn HelpWieldWear = "wield / wear"
uiEn HelpPutOnTakeOff = "put on / take off"
uiEn HelpZapThrow = "zap / throw (then direction)"
uiEn HelpDrop = "drop"
uiEn HelpInterface = "Interface"
uiEn HelpHelpPalette = "help / command palette"
uiEn HelpLogThemeAnimation = "log / theme / animation"
uiEn HelpRedraw = "redraw"
uiEn HelpScoresShare = "scores / share seed / replay browser"
uiEn HelpQuit = "quit"
uiEn HelpMouse = "click map, inventory, palette"
uiEn HelpSymbols = "Symbols"
uiEn HelpSymbols1 = "  @ you   A-Z monsters   # wall   . floor   + door   < > stairs"
uiEn HelpSymbols2 = "  ) weapon   [ armor   % food   ! potion   ? scroll   / wand   = ring"
uiEn HelpSymbols3 = "  $ gold   \" amulet   ^ trap"
uiEn HelpTactics = "  Bump to attack. The Amulet is on depth 26; return it to depth 1."
uiEn HelpSettings = "Settings: $XDG_DATA_HOME/lambda-rogue/settings.json"
uiEn HelpPaletteHint = "Palette: Save settings / Reload settings."
uiEn HelpReplay =
  "Replays: F5 lists files; Left/Right seek, Home/End jump, R restarts."
uiEn HelpAccessibility =
  "Accessibility: --theme, --no-color, NO_COLOR, NO_MOTION, ASCII glyphs."
uiEn HelpUnbound = "unbound"
uiEn HelpArrows = "arrows"
uiEn PaletteTitle = "Command palette"
uiEn PaletteControls = "Up/Down or j/k move   Enter run   Esc close"
uiEn Scores = "Scores"
uiEn ScoresSubtitle = "Completed runs, newest first."
uiEn ScoreDepth = "Depth"
uiEn ScoreLv = "Lv"
uiEn ScoreExp = "Exp"
uiEn ScoreGold = "Gold"
uiEn ScoreTurns = "Turns"
uiEn ScoreResult = "Result"
uiEn ScoreCause = "Cause"
uiEn ResultWon = "won"
uiEn ResultDead = "dead"
uiEn NoScores = "No completed runs yet."
uiEn NotChecked = "not checked"
uiEn Verified = "verified"
uiEn Mismatch = "MISMATCH"
uiEn ScoreSeed = "Seed: {}"
uiEn ScoreReplay = "Replay: {}"
uiEn ScoreControls = "P replays.  F5 lists saved replays.  Esc, S or Enter closes."
uiEn ShareTitle = "Share seed"
uiEn ShareSeed = "Seed: {}"
uiEn ShareGive = "Give this seed to another player."
uiEn ShareRule = "Same seed + same commands = same run."
uiEn ShareStart = "Start with: lambda-rogue --seed {}"
uiEn ShareDepthLine = "Depth {}   Level {}   Turn {}"
uiEn ShareCommands = "Recorded commands: {}"
uiEn ShareReplay = "Replay: {}"
uiEn ShareCopy = "c or Enter copies the seed to the clipboard."
uiEn ShareClose = "Esc or Ctrl-S closes."
uiEn EquippedNone = "none"
uiEn KeysMove = "hjkl/yubn move   . wait   i inventory"
uiEn KeysPickUpDescend = ", pick up   > descend   < ascend"
uiEn KeysReadZapThrow = "r read   z zap   t throw   P put on ring"
uiEn KeysTakeOffRedrawQuit = "R take off   ^R redraw   q quit"
uiEn KeysHelpLogTheme = "? help  ^P palette  F2 log  F3 theme"
uiEn KeysScoresShare = "S scores   ^S share seed"
uiEn KeysMouse = "Mouse: map click, wheel lists"
uiEn HelpMouseLabel = "Mouse"
uiEn MissingSeedValue =
  "missing value for --seed (expected 16 lowercase hex digits)"
uiEn InvalidSeedValue =
  "invalid --seed value: {} (expected 16 lowercase hex digits)"
uiEn MissingLangValue = "missing value for --lang (expected en or ja)"
uiEn InvalidLangValue = "invalid --lang value: {} (expected en or ja)"
uiEn MissingThemeValue =
  "missing value for --theme (see README for the theme ids)"
uiEn InvalidThemeValue =
  "invalid --theme value: {} (expected classic-cga, modern-dark, amber, green-phosphor, high-contrast, colorblind-safe or monochrome)"
uiEn TerminalTooSmall = "Terminal too small: need 80x24, have {}x{}"
uiEn AppAlreadyRunning =
  "lambda-rogue is already running; close that instance first."
uiEn AppNeedsTerminal = "lambda-rogue needs a terminal: {}"
uiEn Bye = "bye"

uiJa : TextKey -> String
uiJa Brand = "lambda-rogue"
uiJa LabelDepth = "深さ"
uiJa LabelDlvl = "階"
uiJa LabelLevel = "レベル"
uiJa LabelHp = "HP"
uiJa LabelStrength = "力"
uiJa LabelGold = "金"
uiJa LabelExp = "経験値"
uiJa LabelTurn = "ターン"
uiJa LabelFood = "食料"
uiJa LabelLog = "ログ"
uiJa LabelTheme = "テーマ"
uiJa LabelSeed = "シード"
uiJa LabelStatus = "状態"
uiJa LabelKeys = "操作"
uiJa LabelWeapon = "武器"
uiJa LabelArmor = "鎧"
uiJa LabelRings = "指輪"
uiJa LabelVisible = "視界"
uiJa LabelExplored = "探索済み"
uiJa LabelRooms = "部屋"
uiJa LabelTraps = "罠"
uiJa LabelPos = "位置"
uiJa StatusNone = "状態: なし"
uiJa MonstersNone = "怪物: なし"
uiJa MonsterSummary = "怪物: {}  {} ({}) {}"
uiJa ItemNone = "アイテム: なし"
uiJa ItemFloor = "アイテム: {} {}"
uiJa ItemPack = "アイテム: {} (持ち物)"
uiJa ItemCarried = "アイテム: {} (運搬中)"
uiJa Dead = "  死亡: {}"
uiJa Won = "  勝利"
uiJa Hover = "カーソル {}"
uiJa ReplayBar = "リプレイ {}/{}"
uiJa ReplaySlow = "遅い"
uiJa ReplayNormal = "普通"
uiJa ReplayFast = "速い"
uiJa ReplayComplete = "完了"
uiJa ReplayPlaying = "再生中"
uiJa ReplayPaused = "一時停止"
uiJa ReplayVerified = "検証済み"
uiJa ReplayMismatch = "不一致"
uiJa ReplayControls = "Space . -/+ ←/→ Home/End R Esc"
uiJa ReplayBrowserTitle = "リプレイ一覧"
uiJa ReplayBrowserEmpty = "保存されたリプレイはない。"
uiJa ReplayBrowserControls =
  "上下またはj/kで移動   Enterで再生   rで再読込   Escで閉じる"
uiJa ReplayBrowserError = "このリプレイを読み込めなかった。"
uiJa LogAll = "すべて"
uiJa LogCombat = "戦闘"
uiJa LogItems = "アイテム"
uiJa LogSystem = "システム"
uiJa LogWarnings = "警告"
uiJa NoMessages = "({}のメッセージはない)"
uiJa ZapPrompt = "どの方向へ撃ちますか？  hjkl/yubnか矢印キー、Escで取消"
uiJa ThrowPrompt = "どの方向へ投げますか？  hjkl/yubnか矢印キー、Escで取消"
uiJa Minimap = "ミニマップ"
uiJa MinimapYou = "@ あなた   < > 階段"
uiJa MinimapSymbols = "+ 扉   # 壁   . 床"
uiJa MinimapOnlyExplored = "探索した場所だけを表示している。"
uiJa InventoryTitle = "持ち物  {}/{}"
uiJa InventoryEquippedNote = "* は装備中のアイテム。"
uiJa PackEmpty = "持ち物は空だ。"
uiJa EmptySlot = "(空)"
uiJa ItemDetails = "アイテムの詳細"
uiJa Slot = "スロット {}"
uiJa Equipped = "装備: {}"
uiJa InPack = "持ち物の中"
uiJa ProtectedFromTheft = "盗難から守られている"
uiJa EnterUses = "Enterでこのアイテムを使う。"
uiJa SelectSlot = "a-zで別のスロットを選ぶ。"
uiJa InventoryHelp1 = "a-z 選択  Enter 使用  q 飲む  r 読む  e 食べる  w 装備"
uiJa InventoryHelp2 = "W 着る  P 指輪  R/T 外す  z 振る  t 投げる  d 落とす  Esc"
uiJa CategoryWeapon = "武器"
uiJa CategoryArmor = "鎧"
uiJa CategoryFood = "食料"
uiJa CategoryPotion = "ポーション"
uiJa CategoryScroll = "巻物"
uiJa CategoryWand = "杖"
uiJa CategoryRing = "指輪"
uiJa CategoryGold = "金"
uiJa CategoryAmulet = "アミュレット"
uiJa Enchantment = "付加値: {}"
uiJa CursedCannotRemove = "呪い: 外せない"
uiJa Unidentified = "未識別: 効果は不明"
uiJa Charges = "残り回数: {}"
uiJa AmountGold = "金額: {} ゴールド"
uiJa Wielded = "装備中"
uiJa Worn = "着用中"
uiJa LeftRing = "左手の指輪"
uiJa RightRing = "右手の指輪"
uiJa WieldedLabel = "武器: {}"
uiJa WornLabel = "鎧: {}"
uiJa RingsLabel = "指輪: {}"
uiJa HelpTitle = "lambda-rogue ヘルプ"
uiJa HelpClose = "Esc、? または F1 でヘルプを閉じる。"
uiJa HelpMovement = "移動"
uiJa HelpMove = "移動 (8方向)"
uiJa HelpWaitSearchPickUp = "待機 / 探索 / 拾う"
uiJa HelpStairs = "階段を降りる / 昇る"
uiJa HelpItems = "アイテム"
uiJa HelpInventory = "持ち物 (a-z, Enter)"
uiJa HelpQuaffReadEat = "飲む / 読む / 食べる"
uiJa HelpWieldWear = "武器を持つ / 鎧を着る"
uiJa HelpPutOnTakeOff = "指輪をはめる / 外す"
uiJa HelpZapThrow = "杖を振る / 投げる (続けて方向)"
uiJa HelpDrop = "落とす"
uiJa HelpInterface = "インターフェース"
uiJa HelpHelpPalette = "ヘルプ / コマンドパレット"
uiJa HelpLogThemeAnimation = "ログ / テーマ / アニメーション"
uiJa HelpRedraw = "再描画"
uiJa HelpScoresShare = "スコア / シード共有 / リプレイ一覧"
uiJa HelpQuit = "終了"
uiJa HelpMouse = "地図・持ち物・パレットをクリック"
uiJa HelpSymbols = "記号"
uiJa HelpSymbols1 = "  @ あなた   A-Z 怪物   # 壁   . 床   + 扉   < > 階段"
uiJa HelpSymbols2 = "  ) 武器   [ 鎧   % 食料   ! ポーション   ? 巻物   / 杖   = 指輪"
uiJa HelpSymbols3 = "  $ 金   \" アミュレット   ^ 罠"
uiJa HelpTactics = "  体当たりで攻撃。アミュレットは26階にあり、1階へ持ち帰れば勝利。"
uiJa HelpSettings = "設定: $XDG_DATA_HOME/lambda-rogue/settings.json"
uiJa HelpPaletteHint = "パレット: 設定を保存 / 設定を再読み込み。"
uiJa HelpReplay =
  "リプレイ: F5で一覧。←/→でシーク、Home/Endで先頭/末尾、Rで最初から。"
uiJa HelpAccessibility =
  "アクセシビリティ: --theme、--no-color、NO_COLOR、NO_MOTION、ASCIIグリフ。"
uiJa HelpUnbound = "未割り当て"
uiJa HelpArrows = "矢印キー"
uiJa PaletteTitle = "コマンドパレット"
uiJa PaletteControls = "上下またはj/kで移動   Enterで実行   Escで閉じる"
uiJa Scores = "スコア"
uiJa ScoresSubtitle = "完了した冒険、新しい順。"
uiJa ScoreDepth = "深さ"
uiJa ScoreLv = "レベル"
uiJa ScoreExp = "経験値"
uiJa ScoreGold = "金"
uiJa ScoreTurns = "ターン"
uiJa ScoreResult = "結果"
uiJa ScoreCause = "死因"
uiJa ResultWon = "勝利"
uiJa ResultDead = "死亡"
uiJa NoScores = "完了した冒険はまだない。"
uiJa NotChecked = "未検証"
uiJa Verified = "検証済み"
uiJa Mismatch = "不一致"
uiJa ScoreSeed = "シード: {}"
uiJa ScoreReplay = "リプレイ: {}"
uiJa ScoreControls = "Pで再生。F5でリプレイ一覧。Esc、SまたはEnterで閉じる。"
uiJa ShareTitle = "シードを共有"
uiJa ShareSeed = "シード: {}"
uiJa ShareGive = "このシードを他のプレイヤーに渡そう。"
uiJa ShareRule = "同じシード + 同じコマンド = 同じ冒険。"
uiJa ShareStart = "開始: lambda-rogue --seed {}"
uiJa ShareDepthLine = "深さ {}   レベル {}   ターン {}"
uiJa ShareCommands = "記録済みコマンド: {}"
uiJa ShareReplay = "リプレイ: {}"
uiJa ShareCopy = "c または Enter でシードをクリップボードへコピー。"
uiJa ShareClose = "Esc または Ctrl-S で閉じる。"
uiJa EquippedNone = "なし"
uiJa KeysMove = "hjkl/yubn 移動   . 待機   i 持ち物"
uiJa KeysPickUpDescend = ", 拾う   > 降りる   < 昇る"
uiJa KeysReadZapThrow = "r 読む   z 振る   t 投げる   P 指輪をはめる"
uiJa KeysTakeOffRedrawQuit = "R 外す   ^R 再描画   q 終了"
uiJa KeysHelpLogTheme = "? ヘルプ  ^P パレット  F2 ログ  F3 テーマ"
uiJa KeysScoresShare = "S スコア   ^S シード共有"
uiJa KeysMouse = "マウス: 地図クリック、ホイールで一覧"
uiJa HelpMouseLabel = "マウス"
uiJa MissingSeedValue =
  "--seed の値がない（16桁の小文字16進数を指定）"
uiJa InvalidSeedValue =
  "--seed の値が不正: {}（16桁の小文字16進数を指定）"
uiJa MissingLangValue = "--lang の値がない（en または ja を指定）"
uiJa InvalidLangValue = "--lang の値が不正: {}（en または ja を指定）"
uiJa MissingThemeValue =
  "--theme の値がない（テーマIDを指定）"
uiJa InvalidThemeValue =
  "--theme の値が不正: {}（classic-cga, modern-dark, amber, green-phosphor, high-contrast, colorblind-safe, monochrome のいずれか）"
uiJa TerminalTooSmall = "端末が小さすぎる: 80x24 が必要、現在 {}x{}"
uiJa AppAlreadyRunning =
  "lambda-rogue はすでに起動している。先にそちらを閉じてほしい。"
uiJa AppNeedsTerminal = "lambda-rogue には端末が必要: {}"
uiJa Bye = "またね"

||| Localised labels for the command palette.  The palette keeps English
||| labels as its canonical identity; this lookup is presentation only.
public export
paletteLabel : Language -> String -> String
paletteLabel English label = label
paletteLabel Japanese label =
  case label of
    "Inventory" => "持ち物"
    "Help" => "ヘルプ"
    "Wait one turn" => "1ターン待機"
    "Pick up" => "拾う"
    "Descend stairs" => "階段を降りる"
    "Ascend stairs" => "階段を昇る"
    "Read a scroll" => "巻物を読む"
    "Quaff a potion" => "ポーションを飲む"
    "Eat food" => "食料を食べる"
    "Zap a wand" => "杖を振る"
    "Throw an item" => "アイテムを投げる"
    "Put on a ring" => "指輪をはめる"
    "Take off an item" => "アイテムを外す"
    "Drop an item" => "アイテムを落とす"
    "Cycle log filter" => "ログ表示を切り替え"
    "Scores" => "スコア"
    "Share seed" => "シードを共有"
    "Cycle theme" => "テーマを切り替え"
    "Toggle animation" => "アニメーション切替"
    "Cycle animation speed" => "アニメーション速度"
    "Switch language" => "言語を切り替え"
    "Replay browser" => "リプレイ一覧"
    "Save settings" => "設定を保存"
    "Reload settings" => "設定を再読み込み"
    "Save and quit" => "保存して終了"
    "Load game" => "ゲームを読み込む"
    "Search for traps" => "罠を探す"
    "Quit" => "終了"
    _ => label

||| All keys, used by the catalog tests to prove English and Japanese are
||| both complete.
public export
allTextKeys : List TextKey
allTextKeys =
  [ Brand
  , LabelDepth, LabelDlvl, LabelLevel, LabelHp, LabelStrength, LabelGold
  , LabelExp, LabelTurn, LabelFood, LabelLog, LabelTheme, LabelSeed
  , LabelStatus, LabelKeys, LabelWeapon, LabelArmor, LabelRings
  , LabelVisible, LabelExplored, LabelRooms, LabelTraps, LabelPos
  , StatusNone, MonstersNone, MonsterSummary, ItemNone, ItemFloor
  , ItemPack, ItemCarried, Dead, Won, Hover
  , ReplayBar, ReplaySlow, ReplayNormal, ReplayFast, ReplayComplete
  , ReplayPlaying, ReplayPaused, ReplayVerified, ReplayMismatch
  , ReplayControls
  , ReplayBrowserTitle, ReplayBrowserEmpty, ReplayBrowserControls
  , ReplayBrowserError
  , LogAll, LogCombat, LogItems, LogSystem, LogWarnings, NoMessages
  , ZapPrompt, ThrowPrompt
  , Minimap, MinimapYou, MinimapSymbols, MinimapOnlyExplored
  , InventoryTitle, InventoryEquippedNote, PackEmpty, EmptySlot, ItemDetails
  , Slot, Equipped, InPack, ProtectedFromTheft, EnterUses, SelectSlot
  , InventoryHelp1, InventoryHelp2
  , CategoryWeapon, CategoryArmor, CategoryFood, CategoryPotion
  , CategoryScroll, CategoryWand, CategoryRing, CategoryGold, CategoryAmulet
  , Enchantment, CursedCannotRemove, Unidentified, Charges, AmountGold
  , Wielded, Worn, LeftRing, RightRing, WieldedLabel, WornLabel
  , RingsLabel
  , HelpTitle, HelpClose, HelpMovement, HelpMove, HelpWaitSearchPickUp
  , HelpStairs, HelpItems, HelpInventory, HelpQuaffReadEat, HelpWieldWear
  , HelpPutOnTakeOff, HelpZapThrow, HelpDrop, HelpInterface
  , HelpHelpPalette, HelpLogThemeAnimation, HelpRedraw, HelpScoresShare
  , HelpQuit, HelpMouse, HelpSymbols, HelpSymbols1, HelpSymbols2
  , HelpSymbols3, HelpTactics, HelpSettings, HelpPaletteHint
  , HelpUnbound, HelpArrows, HelpReplay, HelpAccessibility
  , PaletteTitle, PaletteControls
  , Scores, ScoresSubtitle, ScoreDepth, ScoreLv, ScoreExp, ScoreGold
  , ScoreTurns, ScoreResult, ScoreCause, ResultWon, ResultDead, NoScores
  , NotChecked, Verified, Mismatch, ScoreSeed, ScoreReplay, ScoreControls
  , ShareTitle, ShareSeed, ShareGive, ShareRule, ShareStart
  , ShareDepthLine, ShareCommands, ShareReplay, ShareCopy, ShareClose
  , EquippedNone
  , KeysMove, KeysPickUpDescend, KeysReadZapThrow, KeysTakeOffRedrawQuit
  , KeysHelpLogTheme, KeysScoresShare, KeysMouse, HelpMouseLabel
  , MissingSeedValue, InvalidSeedValue, MissingLangValue, InvalidLangValue
  , MissingThemeValue, InvalidThemeValue
  , TerminalTooSmall, AppAlreadyRunning, AppNeedsTerminal, Bye
  ]

public export
uiText : Language -> TextKey -> String
uiText English key = uiEn key
uiText Japanese key = uiJa key

||| Render a UI string with positional `{}` arguments.
public export
uiTextArgs : Language -> TextKey -> List String -> String
uiTextArgs lang key args = renderTemplate (uiText lang key) args
