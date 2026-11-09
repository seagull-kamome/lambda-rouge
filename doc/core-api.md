# lambda-rogue Core API 設計

- Status: Draft 1.7（M5 スライス 1 の探索・回復・魔法の矢を反映）
- Date: 2026-11-09
- 対象: `LambdaRogue.Core.*` と `LambdaRogue.UI.*`、`LambdaRogue.Persist.*`
- 前提: `doc/design.md` Draft 1.8

## 1. 境界

- Core はゲームの真実だけを持つ。`IO`、`termui`、ファイル、端末、時計を import しない。
- Core の入力は `Command`、状態は `Game`、出力は `Outcome` の 3 つだけ。
- UI は `Game` を直接書き換えない。UI のモーダル、選択、スクロール、アニメーションは
  `App` の状態であり、Core の `Command` には含めない。
- 乱数は `LambdaRogue.Core.Rng.Rng` の純粋な値を使う。rc2base の
  `Xoroshiro128PlusPlus.Gen` は状態を取り出せないため、Core では状態型として使わない。
  `Rng` は同じ xoroshiro128++ を実装し、`Gen` との一致をテストで検証する。
- セーブ、スコア、JSON 永続化は `App` / `Persist` が担当する。Core は JSON を知らない。
  リプレイの意味的コマンド列と状態ダイジェストは純粋な `Core.Replay` が持つ。

```
Core.Types ── Core.Geometry ── Core.Rng ── Core.Bitset
     │              │              │           │
     ├──────────────┴──────────────┴───────────┤
     ▼                                         ▼
Core.Dungeon  Core.Fov  Core.Path  Core.Combat  Core.Monster
     │           │         │          │             │
     └───────────┴─────────┴──────────┴─────────────┘
                              │
                    Core.Item / Core.Effects
                              │
                         Core.Turn
                              │
                         Core.Game
                              │
                         Core.Message
```

`Core.Game` は他の Core モジュールを import してよいが、`App` / `UI` / `Persist` を
import してはならない。`UI` は `Core.Types` と `UI.ViewModel` だけを見る。

## 2. 基本型

```idris
public export
Depth : Type
Depth = Int32          -- 1 .. 26

public export
Turn : Type
Turn = Int32           -- 0 から始まる

public export
MonsterId, ItemId, RoomId, AppearanceId : Type
MonsterId = Bits32
ItemId = Bits32
RoomId = Bits32
AppearanceId = Bits32

public export
Bitset : Type
Bitset = Vect 28 Bits64     -- 80 * 22 = 1,760 bit

public export
record Coord where
  constructor MkCoord
  x, y : Int32

public export
data Dir = N | NE | E | SE | S | SW | W | NW

public export
delta : Dir -> Coord
```

- 座標はマップの左上を `(0, 0)` とする。
- マップは `80 x 22`。`x` は `0..79`、`y` は `0..21`。
- 範囲外は「壁でも床でもない」として扱い、`Command` の検証で弾く。
- 距離は `Int32` のチェビシェフ距離または二乗距離で計算する。`Nat` の
  `div`/`mod` は使わない。

## 3. 地形

```idris
public export
data DoorState = Open | Closed | Secret | Locked

public export
data StairDir = Up | Down

public export
data Tile
  = Rock
  | Floor
  | Corridor
  | Door DoorState
  | Stairs StairDir

public export
record Room where
  constructor MkRoom
  x, y, w, h : Int32
  dark : Bool

public export
data TrapKind
  = TrapDoor
  | ArrowTrap
  | Sleep
  | Bear
  | Teleport
  | DartTrap
  | Rust
  | Mysterious

public export
record Trap where
  constructor MkTrap
  pos : Coord
  kind : TrapKind
  revealed : Bool

public export
record Level where
  constructor MkLevel
  depth : Depth
  tiles : Vect 22 (Vect 80 Tile)  -- 行優先。`index y` が 80 列の行
  explored : Bitset           -- 80 * 22 bit
  rooms : List Room
  monsters : List Monster
  traps : List Trap
  upStairs, downStairs : Maybe Coord
```

- Idris 2 0.8 の base には不変 `Array` がないため、`tiles` は
  `Vect 22 (Vect 80 Tile)` とする。1,760 セルなので不変コピーで十分。
- `visible` は保存しない。各ターンの終わりに FOV から再計算する。
- `explored` は単調増加。見た地形は消さない。
- トラップは地形ではなく `Level.traps` に置く。未発見のトラップは
  `revealed = False` で、UI に出さない。
- ドアの `Secret` は探索するまで `Closed` に見える。`Locked` は現状開けられず、
  「The door is locked.」を返してターンを消費しない。
- アイテムは `Level` ではなく `Game.items` に置く。`Item.location` が
  「床・所持・モンスター所持」を表す。
- `MonsterId` はラン全体で一意。`Level.monsters` は現在その階層にいる
  モンスターだけを持ち、訪問済み階層のモンスターは各 `Level` に残る。

## 4. アクター

```idris
public export
data Hand = LeftHand | RightHand

public export
record Player where
  constructor MkPlayer
  pos : Coord
  hp, maxHp : Int32
  strength, maxStrength : Int32
  armor : Int32
  level : Int32
  exp : Int32
  gold : Int32
  hunger : Int32
  inventory : List ItemId
  wielded, worn : Maybe ItemId
  leftRing, rightRing : Maybe ItemId
  weaponDice, weaponSides, weaponBonus : Int32
  ringArmor, ringDamage, ringAccuracy, ringStrength : Int32
  statuses : List Status

public export
data MonsterState
  = Asleep
  | Awake
  | Chasing
  | Fleeing

public export
record Monster where
  constructor MkMonster
  id : MonsterId
  kind : MonsterKind
  pos : Coord
  hp, maxHp : Int32
  state : MonsterState
  statuses : List Status
```

- `MonsterKind` は 26 種の有限列挙。名前・記号・レベル・AC・攻撃・基礎経験値・
  出現深度は `doc/rogue-reference.md` 4 章の表を正とする。HP は `レベル d8`。
- `MonsterId` はラン全体で単調増加。UI のアニメーションとログは ID で個体を追う。
- `Held` / `Confused` は `Status` だけに持たせ、`MonsterState` には入れない。
  `MonsterState` は AI の基本状態（睡眠・起床・追跡・逃走）だけを表す。
- `Player.armor` は装備中の防具の AC（10 が素手、低いほど良い）。強化値は
  `防具の AC - enchant` として `recomputeArmor` が反映する。
- `weaponDice` / `weaponSides` / `weaponBonus` は装備中の武器から展開した
  攻撃プロファイル。素手は `1d4`、武器なしの投擲は別経路。
- `ringArmor` / `ringDamage` / `ringAccuracy` / `ringStrength` は装備中の
  指輪の合計補正。`ringStrength` は `effectiveStrength` で基礎筋力に加算する。
- `hunger` は栄養値。初期値 1300、1 消費ターンごとに 1 減る。
- `Player.inventory` は所持順（新しい順）。UI の a-z は表示上のスロットであり、
  Core の ID とは独立させる。
- 装備中の ID は必ず `inventory` に含まれる。装備品を落とす・投げる前に
  外すことを `step` が強制する。
- モンスターがアイテムを持っているときは、`Item.location = CarriedBy id` で
  表す。`Monster` に所持リストを重複して持たせない。

## 5. アイテム

```idris
public export
data ItemKind
  = Weapon WeaponKind
  | Armor ArmorKind
  | Food FoodKind
  | Potion PotionKind
  | Scroll ScrollKind
  | Wand WandKind
  | Ring RingKind
  | Gold
  | Amulet

public export
data ItemLocation
  = OnFloor Depth Coord      -- 指定した階層の床
  | InPack                   -- プレイヤーの所持品
  | CarriedBy MonsterId      -- モンスターが所持

public export
record Item where
  constructor MkItem
  id : ItemId
  kind : ItemKind
  location : ItemLocation
  count : Int32
  enchant : Int32
  cursed : Bool
  charges : Int32
  protected : Bool
```

- `WeaponKind` / `ArmorKind` / `FoodKind` / `PotionKind` / `ScrollKind` /
  `WandKind` / `RingKind` は `doc/rogue-reference.md` 7〜12 章の表に対応する
  有限列挙。名前・記号・重み・価値・ダイスは `Core.Types` と `Core.Item` を正とする。
- `enchant` は武器・防具・指輪の強化値。武器は命中とダメージの両方に、
  防具は AC に、指輪は種類ごとの効果に使う。負値は呪い・逆効果を表す。
- `cursed` は外せない状態。`protected` は防具が錆びない状態。
- `charges` は杖の残り充填数。光の杖は生成時 10–19、それ以外は 3–7。
- 識別状態はアイテム個体ではなく `Game.knownKinds : List ItemKind` に持つ。
  同じ種別を 1 度識別すれば、以後の同種アイテムは実名で表示する。
- 未識別の外見は `Game.appearances : List (ItemKind, String)` に保存する。
  `itemDisplayNameIn : Game -> Item -> String` が実名・外見・強化値・呪い・
  充填数をまとめて表示名にする。`Gold` と `Amulet` は常に既知。
- `Gold` の `count` は金額。`Amulet` は 1 個だけ存在し、`count = 1`。
- 呪い・強化値・充填数は識別状態と独立に保持する。識別しても呪いが
  解けるとは限らない。

## 6. 状態異常

```idris
public export
data StatusKind
  = Confused
  | Blinded
  | Hasted
  | SeeInvisible
  | DetectMonsters
  | DetectFood
  | DetectMagic
  | Invisible
  | Poisoned
  | Held
  | Slowed
  | Paralyzed
  | Scared
  | Sleeping
  | Hallucinating
  | Levitated
  | ConfuseNext

public export
record Status where
  constructor MkStatus
  statusKind : StatusKind
  remaining : Int32
```

- `remaining` はターン数。0 以下になったら `step` の終わりに取り除き、
  解除メッセージを出す。
- 状態は付与したターンの終わりにも 1 減る。`addStatus Held 4` は実効 3 行動、
  `addStatus Sleeping 6` は実効 5 行動のブロックになる。
- 同じ `StatusKind` を重複して持たない。`addStatus` は既存の残りターンと
  新しい残りターンの大きい方を採用する。
- 毒は毎ターン 1 HP のダメージ。HP 0 で死亡する。
- `Sleeping` / `Paralyzed` のプレイヤーはコマンドを受け付けず、ターンだけ消費する。
  `Held` は移動を封じるが、隣接モンスターへの攻撃は許可する。
- UI はアイコン・名前・残りターンを表示する。色だけに依存しない。
- 効果の発生源と持続の詳細は `doc/rogue-reference.md` 15 章を参照する。

## 7. ゲーム状態

```idris
public export
data DeathCause
  = KilledBy MonsterKind
  | KilledByTrap TrapKind
  | Starved
  | Drained
  | OtherDeath String

public export
data GameOver = Dead DeathCause | Won

public export
record Game where
  constructor MkGame
  seed : Bits64
  rng : Rng
  turn : Turn
  depth : Depth
  player : Player
  levels : List Level        -- 現在の階層が先頭、以下は訪問順
  items : List Item          -- ラン全体のアイテム（床・所持・モンスター所持）
  nextMonsterId, nextItemId : Bits32
  knownKinds : List ItemKind
  appearances : List (ItemKind, String)
  messages : List Message    -- 直近 200 件程度
  over : Maybe GameOver
  visible : Bitset
```

- `levels` は現在の階層を先頭に持つ。同じ `depth` の `Level` を 2 つ持たない。
  `currentLevel` は先頭を返し、`updateCurrentLevel` は先頭だけを更新する。
- `items` はラン全体のアイテムを ID 昇順で持つ。現在の階層の床にあるものは
  `location = OnFloor depth pos` で引く。
- `knownKinds` は識別済みの種別、`appearances` はラン固有の未識別名。
  どちらもセーブ・リプレイ・状態ダイジェストに含める。
- `messages` は Core が生成したメッセージ履歴。UI の表示ログは
  `App` が別に持ち、フィルタ・折り返し・スクロールを担当する。
- `over = Just _` のとき、`step` は状態を変えず、メッセージも追加しない。
- `seed` は 64-bit。`rng` は 128-bit の `Rng`。どちらもセーブに含める。
- `nextMonsterId` / `nextItemId` はラン全体の ID 採番。既存の最大 ID より
  大きいことを不変条件とする。
- `visible` は各ターンの終わりに FOV から再計算する一時的なビットグリッド。
  `explored` は各 `Level` に残る。

## 8. メッセージとイベント

```idris
public export
data MessageKind = CombatMsg | ItemMsg | SystemMsg | WarningMsg | StoryMsg

public export
record Message where
  constructor MkMessage
  turn : Turn
  kind : MessageKind
  text : String

public export
data Event
  = PlayerMoved Coord
  | MonsterMoved MonsterId Coord
  | PlayerAttacked MonsterId Int32
  | MonsterAttacked MonsterId Int32
  | MonsterWoke MonsterId
  | MonsterDied MonsterId
  | ItemPicked ItemId
  | ItemUsed ItemId
  | ItemDropped ItemId
  | DoorOpened Coord
  | TrapTriggered TrapKind Coord
  | LevelChanged Depth
  | PlayerLevelUp Int32
  | PlayerDied
  | PlayerWon
```

- `Event` は UI の演出用。ゲーム結果・乱数・メッセージ順序に影響しない。
- アニメーションの有無で `Outcome` の `game` / `messages` が変わってはならない。
- `Event` は ID と座標だけを持ち、文字列や色を持たない。UI が表示を決める。

## 9. コマンド

```idris
public export
data Command
  = Move Dir
  | Wait
  | Search
  | PickUp
  | Quaff ItemId
  | Read ItemId
  | Eat ItemId
  | Wield ItemId
  | Wear ItemId
  | PutOnRing ItemId
  | TakeOff ItemId
  | Drop ItemId
  | Throw ItemId Dir
  | Zap ItemId Dir
  | Descend
  | Ascend
```

- `Command` はゲーム状態を変える操作だけ。インベントリを開く、ヘルプを見る、
  カーソルを動かす、ログをスクロールする、は `App` の `Msg` であり、
  Core には渡さない。
- `Move` は移動先にモンスターがいれば攻撃、アイテムがあっても自動では拾わない。
- `Throw` / `Zap` は方向を明示する。UI の方向選択は `App` が解決してから
  `Command` を作る。
- 不正なコマンド（存在しない ID、装備していない物を外す、壁へ移動など）は
  `turnConsumed = False`、警告メッセージ、乱数消費なしで返す。

## 10. step の契約

```idris
public export
record Outcome where
  constructor MkOutcome
  game : Game
  messages : List Message
  events : List Event
  turnConsumed : Bool

public export
step : Command -> Game -> Outcome
```

### 10.1 前条件

- `game.over = Nothing`。`Just _` のときは状態を変えずに返す（no-op）。
- `Command` の ID は `game` 内に存在する。
- `Game` の不変条件（12 節）が成り立っている。

### 10.2 解決順

1. `game.over = Just _` なら no-op で返す。
2. プレイヤーが `Sleeping` / `Paralyzed` なら、警告メッセージを出して
   ターンだけ消費する。それ以外は `Command` を検証してプレイヤー行動を解決する。
3. ターンを消費しないコマンド（不正、キャンセル、インベントリ表示など）は
   ここで終了する。
4. `turn` を 1 進める。
5. 移動が成立し、searching の指輪を装着していれば、装着数と同じ回数の
   無料探索を行う。探索は現在の階の未発見トラップを 1 体ずつ判定し、
   乱数を消費する。待機・攻撃・アイテム使用・階層移動では発動しない。
6. 階層移動がなく、加速によるスキップでなければ、モンスターを `MonsterId` の
   昇順で行動させる。各モンスターは状態異常を 1 減らし、再生なら HP を 1 回復し、
   行動する。`Fast` / `Hasted` は続けてもう 1 回行動する。
7. 死亡していなければ、状態異常の経過と毒ダメージ、自然回復、回復の指輪、
   空腹、slow digestion、テレポートの指輪を処理する。
8. 死亡判定を行い、`over` を確定する。
9. FOV と `explored` を更新し、`Outcome` を返す。

- `Search` は隣接 8 マスの未発見トラップを
  `uniform (2 + 盲目 2 + 幻覚 3)` の 0 で発見する。1 ターン消費し、
  移動しない。秘密のドアは生成しないため、対象はトラップだけである。
- 手順 4〜9 の順序はリプレイの同一性に直結する。変更する場合は
  `doc/rogue-reference.md` 16 章とテストを同時に更新する。
- モンスターの行動順はリストの添字ではなく `MonsterId` で固定する。
- 同じターンに複数のモンスターが死ぬ場合も、ID 昇順で処理する。
- FOV は最後に 1 回だけ計算する。UI の描画で FOV を再計算しない。
- 状態異常は付与したターンの終わりにも減るため、表示上の残りターンと
  実際にブロックできる行動数は 1 異なる。

### 10.3 ターンを消費しないもの

- インベントリ、ヘルプ、ログ、コマンドパレット、カーソル移動、方向選択。
- 不正なコマンド、キャンセル、確認ダイアログの開閉。
- セーブ、ロード、リプレイの一時停止。
- これらは Core に渡さないか、渡しても `turnConsumed = False` にする。

### 10.4 乱数の消費

- 乱数は Core の `step` の中だけで消費する。
- UI の描画、アニメーション、ログ、ツールチップ、ミニマップは乱数を消費しない。
- 乱数の消費順序は「プレイヤー行動 → searching の指輪の無料探索 →
  モンスター行動（ID 昇順）→ 状態異常 → 空腹/再生 → その他」の順で固定する。
- 乱数を使わない分岐（例: 壁への移動）では、乱数を引かない。
- `Outcome` に乱数状態を含める。`Game.rng` が唯一の正とする。

## 11. RNG ラッパー

`LambdaRogue/Core/Rng.idr` は xoroshiro128++ の状態とゲーム向け API を持つ。
rc2base の `Gen` は `export data` で状態を取り出せないため、状態は
`Rng` の値として持つ。アルゴリズムは rc2base と同じで、`fromSeed` / `next64`
が `mkGen` / `genNext` と一致することをテストで検証する。

```idris
public export
record Rng where
  constructor MkRng
  s0, s1 : Bits64

||| splitmix64 で 64-bit seed から初期化する。
public export
fromSeed : Bits64 -> Rng

public export
next64 : Rng -> (Bits64, Rng)

||| `next64` の下位 32 bit。
public export
next32 : Rng -> (Bits32, Rng)

||| 0 <= result < bound。bound = 0 のときは 0 を返し、乱数を消費しない。
public export
uniform : (bound : Bits64) -> Rng -> (Bits64, Rng)

||| n 個の sides 面ダイス。結果は n .. n * sides。
public export
roll : (n, sides : Int32) -> Rng -> (Int32, Rng)

||| percent / 100 の確率。0 は常に False、100 は常に True。
public export
chance : (percent : Int32) -> Rng -> (Bool, Rng)

public export
pick : List a -> Rng -> (Maybe a, Rng)

public export
shuffle : List a -> Rng -> (List a, Rng)

public export
stateHex : Rng -> String          -- 32 文字の小文字 hex

public export
stateFromHex : String -> Maybe Rng
```

- `uniform` は棄却サンプリングで偏りを避ける。`bound` が 2 の冪のときは
  棄却なしでマスクする。`bound = 0` または `1` は乱数を消費せず 0 を返す。
- `roll` は `uniform` を `n` 回呼ぶ。`n <= 0` または `sides <= 0` は 0 を返し、
  乱数を消費しない。
- `pick` は空リストで `Nothing` を返し、乱数を消費しない。
- `shuffle` は Fisher-Yates。末尾から `uniform (i+1)` で交換する。
  空リスト・1 要素では乱数を消費しない。
- `stateHex` は `s0` と `s1` を `toHex` で 16 文字ずつ並べる（合計 32 文字）。
- `stateFromHex` は長さ 32、`[0-9a-f]` のみを受け付ける。失敗は `Nothing`。
- ゲームの判定は整数で行い、`Double` の丸めに依存しない。`Double` が必要なのは
  UI の揺らぎやテストだけである。
- jump 系は提供しない。`genJump` は内部で `unsafePerformIO` を使うため、
  Core の通常経路では使わない。
- rc2base に `genState` / `genFromState` が入ったら、`Rng` の内部実装だけを
  `Gen` に差し替えられる。呼び出し側の API は変えない。

## 12. 不変条件

`step` の前後で次を満たす。テストとデバッグビルドで検証する。

1. `depth` は `1..26`。
2. `levels` の `depth` は重複しない。現在の `depth` の `Level` が存在する。
3. プレイヤーは現在の階層の歩行可能なタイル上にいる。モンスターと同じセルにいない。
4. `Game.items` の ID はラン全体で一意。全 `Level.monsters` の ID もラン全体で一意。
   `nextMonsterId` / `nextItemId` は既存の最大 ID より大きい。
5. `player.inventory` の ID は一意で、`Item.location = InPack` の全アイテムと
   正確に一致する（順序は所持順）。装備中の ID はすべて `inventory` に含まれる。
6. `inventory` の長さは 23 以下。a-z の表示スロット数（26）も超えない。
7. `explored` は単調増加。`visible` は `explored` の部分集合。
8. アミュレットは深度 26 に 1 つだけ存在する。取得後は `player` が持つ。
9. `over = Just _` のとき、それ以降の `step` は状態を変えない。
10. `turn` はターンを消費したときだけ増える。0 未満にならない。
11. `Item.location = OnFloor d _` の `d` は `levels` に存在する。
    `CarriedBy m` の `m` は全 `Level.monsters` のいずれかに存在する。
12. モンスターが死亡したとき、その `CarriedBy m` のアイテムは同じセルの
    `OnFloor` に移る。アイテムが消えることはない（使用・消費を除く）。

## 13. 状態ダイジェスト

リプレイ検証用に、`Game` の正規化表現から 16 文字の小文字 hex を作る。

```idris
public export
gameDigest : Game -> String
```

- 実装は `Core/Replay.idr` の FNV-1a 64-bit。初期案の `Core/Hash.idr` と
  `stateHash : Game -> Bits64` は現在持たない。
- 対象: `seed`, `rng`, `turn`, `depth`, `player`, `levels`, `items`,
  `nextMonsterId`, `nextItemId`, `knownKinds`, `appearances`, `over`,
  `visible`。正規化の詳細は `Core/Replay.idr` の `gameCode` を正とする。
- 対象外: `messages`（表示履歴であり、ログの切り詰めで変化するため）。
- リストは ID 昇順、`levels` は `depth` 昇順、マップは `y * 80 + x` 昇順で
  正規化する。
- ダイジェストは暗号学的ハッシュではない。改ざん検知ではなく、
  `replayMatches` による再現性確認に使う。衝突は許容する。
- 途中チェックポイントや `messagesHash` はまだない。

## 14. モジュール依存

```
Core.Types
  ├─ Core.Geometry
  ├─ Core.Rng
  ├─ Core.Bitset
  ├─ Core.Fov
  ├─ Core.Path
  ├─ Core.Combat
  ├─ Core.Survival
  ├─ Core.Item
  ├─ Core.Monster
  └─ Core.Dungeon
        └─ Core.Game
              ├─ Core.Replay
              └─ Core.Message
```

- `Core.Game` は `step` を公開し、プレイヤー行動・モンスター行動・生存処理を
  1 つの純粋な遷移にまとめる。
- `Core.Dungeon` は `Game` を知らない。`Depth`, ID の開始値, `Rng` から
  `Level` とその階層のアイテム列を返す。ID の確定は `Core.Game` が行う。
- `Core.Fov` は `Level` と `Coord` から `Bitset` を返す。`Game` を知らない。
- `Core.Combat` は `Player` と `Monster` の攻撃・経験値計算を担当する。
- `Core.Survival` は空腹・状態異常・飢餓のターン経過を担当する。
- `Core.Item` は生成・表示名・所持品ヘルパーを担当する。使用効果は `Core.Game`。
- `Core.Monster` は 5.4.4 のロスター、ステータス、生成、経験値ボーナスを持つ。
- `Core.Replay` は seed + 意味的コマンド列と `gameDigest` を持つ。

## 15. 未決事項

M4 の忠実性監査で確定した値と、意図的に残した差分は
`doc/rogue-reference.md` 17 章に集約した。Core API 上の残課題は次だけである。

- `Locked` ドアの開け方（鍵・壊す・魔法）。
- アミュレット取得後の上昇で、訪問済み階層のモンスターを再配置するか。
- スコア計算と死因別の表示。
- 巻物・杖の対象選択 UI と、Core 側の対象指定 API。
- searching（探索）コマンドと、searching の指輪の効果。
- 群れ生成、orc の強欲 AI、xeroc の物体擬態表示。
- 飢餓の失神・`-850` 死亡、自然回復の静穏ターン方式。
- モンスターの遠距離攻撃（弓・投擲）とドラゴンの火炎反射。

## 16. M1 実装ノート（2026-10-28）

M1 は `src/LambdaRogue/Core/*` と `src/LambdaRogue/UI/*` の垂直スライスとして
実装した。上の章の最終形と意図的に異なる部分をここに記録する。

### 16.1 型の差分

- `Game` は次のフィールドだけを持つ。

  ```idris
  record Game where
    constructor MkGame
    seed : Bits64
    rng : Rng
    turn : Turn
    depth : Depth
    player : Player
    level : Level
    items : List Item
    nextItemId : Bits32
    messages : List Message
    over : Maybe GameOver
    visible : Bitset
  ```

  最終形の `levels : SortedMap Depth Level`、`nextMonsterId`、`knowledge`、
  `run` はまだない。M1 は 1 階層だけなので `level` を直接持つ。

- `Level` は `depth`, `tiles`, `explored`, `rooms`, `monsters` を持つ。
  `Grid = Vect 22 (Vect 80 Tile)` は Idris 2 0.8 の base に不変 `Array` が
  ないための選択で、マップの論理形は 22 行 × 80 列のまま。
- `visible` は `Level` ではなく `Game` に置き、ターン解決のたびに
  `Fov.compute` で作り直す。`explored` だけを `Level` に残す。M1 では
  永続化しないが、セーブ対象になるのは `explored` だけの予定。
- `Monster` は `id`, `kind`, `pos`, `hp`, `maxHp`, `state`。
  `MonsterKind = GiantRat` のみ。`Held` / `Confused` などの状態異常は
  `Status` に置く予定で、M1 の `MonsterState` には含めない。
- `ItemKind = Food FoodKind | Potion | Gold`、`FoodKind = FoodRation`。
  M1 が実際に配置するのは food ration だけ。`ItemLocation` は
  `OnFloor Depth Coord | InPack` で、`CarriedBy MonsterId` は M2 以降。
- `Command` は `Move Dir | Wait | PickUp | Descend | Ascend` のみ。
  走る、投げる、使う、装備する、階段を上る/下りる実処理は未実装。
- `MessageKind` のコンストラクタは `CombatMsg`, `ItemMsg`, `SystemMsg`,
  `WarningMsg`, `StoryMsg`。`Item` 型などとの名前衝突を避けるため。
- `Bitset = Vect 28 Bits64`。ビット番号は `y * 80 + x`。28 × 64 = 1,792
  ビットのうち、マップ外の 32 ビットは常に 0 として扱う。

### 16.2 `step` の M1 での解決順

```text
over = Just _        -> 状態を変えずに終了
コマンド検証         -> 不正なら Warning を追加（ターンも RNG も消費しない）
プレイヤー行動       -> 移動 / 待機 / 拾得 / 階段メッセージ / 攻撃
ターン消費時のみ:
  turn += 1
  MonsterId 昇順にモンスター行動
  visible と explored を再計算
```

- 壁への移動、空の床での拾得、階段でない場所での階段コマンドは
  ターンを消費しない。M1 の階段は正しい階段上でもメッセージだけで、
  ターンを消費しない。
- プレイヤーの攻撃はモンスターのセルへの移動として解決する。ダメージは
  1d4。モンスターの攻撃は隣接時のみで、ダメージは 1d3。
- モンスターは `Asleep` のとき、Chebyshev 距離 12 以内かつ
  `Fov.canSee` が真なら `Chasing` に遷移してメッセージを出す。
  `Awake` / `Chasing` は貪欲に 1 歩近づき、隣接していれば攻撃する。
  `Fleeing` は M1 では行動しない。
- モンスターは壁、閉じたドア、プレイヤー、他のモンスターのセルへは
  移動しない。プレイヤーが死亡したら、そのターンの残りのモンスターは
  行動しない。
- `Outcome.messages` はその `step` で新しく出たメッセージを時系列順で返す。
  `Game.messages` は新しい順で最大 200 件。

### 16.3 FOV

- プレイヤーが `dark = False` の部屋の中にいる場合、その部屋の矩形と
  外側 1 セルの壁をすべて visible にする。
- それ以外は半径 12 の円内の候補に対して Bresenham の線を引き、
  途中のセルが透明なら visible にする。対象セル自身は壁や閉じたドアでも
   visible にできる。
- 岩、閉じたドア、隠しドア、施錠ドアは視線を遮る。開いたドア、床、
  通路、階段は透明。
- `visible` はターンを消費したときだけ再計算する。壁にぶつかった等で
  ターンを消費しない場合は、FOV も変えない。

### 16.4 モジュール構成の差分

M1 では最終形の `Core/Path`, `Core/Combat`, `Core/Monster`, `Core/Item`,
`Core/Effects`, `Core/Turn`, `Core/Message`, `Core/Hash` をまだ分割して
いない。移動、戦闘、AI、拾得、階段、FOV 更新は `Core/Game.idr` に、
固定レベルは `Core/Dungeon.idr` にある。M2 でダンジョン生成と戦闘表を
入れるときに、最終形のモジュールへ分割する。

### 16.5 テスト

- `tests/CoreTest.idr`: 移動、壁、ドア、FOV、モンスターの起床・追跡・攻撃、
  拾得、階段、死亡、同じ seed とコマンド列の決定論（41 チェック）。
- `tests/MapViewTest.idr`: プレイヤー、アイテム、モンスターの重ね描き、
  未探索セルの非表示、探索済みセルの暗色表示（9 チェック）。
- `tests/ViewTest.idr`: 80x24 と 120x40 の行数、メッセージ、マップ、
  ステータス、サイドバー、ログ、サイズ警告（10 チェック）。
- `tests/PerfTest.idr`: 初期 FOV と全 1,760 セルの描画、`Wait` の
  ターン解決、step+render の計測。
- `tests/latency_probe.py`: PTY 上のキー入力からフレーム完了までの計測。
- `verify.sh`: ビルド、上記 Idris テスト、PTY スモークテストを実行する。

計測値と環境は `doc/m1-measurements.md` に記録した。

## 17. M2 実装ノート（2026-10-29）

M2 では上の最終形のうち、複数階層・生成・モンスター表・戦闘・成長・死亡を
実装した。空腹・装備・識別・状態異常・アミュレット・セーブ・リプレイは
まだ入っていない。以下の型が現在の実装である。

### 17.1 型の差分

```idris
record Player where
  constructor MkPlayer
  pos : Coord
  hp, maxHp : Int32
  strength : Int32
  armor : Int32
  level : Int32
  exp : Int32
  gold : Int32
  inventory : List ItemId

record Level where
  constructor MkLevel
  depth : Depth
  tiles : Grid
  explored : Bitset
  rooms : List Room
  monsters : List Monster
  traps : List Trap
  upStairs, downStairs : Maybe Coord

record Game where
  constructor MkGame
  seed : Bits64
  rng : Rng
  turn : Turn
  depth : Depth
  player : Player
  levels : List Level        -- 現在の階層が先頭。以下は訪問順
  items : List Item
  nextMonsterId, nextItemId : Bits32
  messages : List Message
  over : Maybe GameOver
  visible : Bitset
```

- `Room` は `x, y, w, h, dark` のみ。`id` と `maze` はまだない。
- `MonsterKind` は 8 種: `GiantRat | Kobold | Jackal | Bat | Snake | Zombie |
  Orc | Hobgoblin`。`Monster` は `id, kind, pos, hp, maxHp, state`。
- `ItemKind` は `Food FoodRation | Potion | Gold`。`Item` は
  `id, kind, location, count`。`CarriedBy` はまだない。
- `Command` は `Move Dir | Wait | PickUp | Descend | Ascend` のみ。
- `Event` は `PlayerMoved | MonsterMoved | PlayerAttacked | MonsterAttacked |
  MonsterWoke | MonsterDied | ItemPicked | DoorOpened | TrapTriggered |
  LevelChanged | PlayerLevelUp | PlayerDied`。
- `GameOver = Dead DeathCause | Won` だが、M2 で `Won` になる経路はない。
- `currentLevel : Game -> Level` は `levels` の先頭を返す。
  `updateCurrentLevel : (Level -> Level) -> Game -> Game` は先頭だけを更新する。
  `levels` が空の場合のフォールバックは `emptyLevel`。

### 17.2 生成

`Core.Dungeon.generateLevel` は次の順で 1 階層を作る。

1. 3x3 のスロット（26x7）に 9 部屋を生成する。部屋は 4〜10 x 3〜5。
2. 部屋を L 字通路で結び、部屋の境界に閉じたドアを置く。
3. 最初の部屋に上り階段、最後の部屋に下り階段を置く。深度 26 は下りなし。
4. 部屋のセルからモンスター、アイテム、トラップの候補を作り、
   使用済みセルを除外しながら配置する。
5. `GeneratedLevel` として `Level`, 階層のアイテム列, 次の RNG 状態,
   次のモンスター/アイテム ID を返す。

- `newGame seed` は深度 1 を生成し、プレイヤーを上り階段に置く。
  `sampleGame` は M1 の固定フィクスチャで、UI テスト用に残している。
- 下降は `Game.levels` の先頭に新しい `Level` を追加する。古い階層は残る。
  到着直後はモンスターターンを省略する。
- トラップは `Level.traps` に置き、`revealed` で表示を制御する。
  M2 の効果はトラップドア・矢・ダーツ・熊挟み・テレポート。
  睡眠・錆・不思議はメッセージのみ。
- テレポート先は現在地とモンスターのいるセルを除外した歩行可能セルから選ぶ。

### 17.3 モンスターと戦闘

- 出現数は `2 + depth/2`（上限 12）。深度ごとの重み付きプールから選び、
  80% を `Asleep`、残りを `Awake` で置く。ID はラン全体で単調増加。
- 睡眠中は Chebyshev 距離 12 以内かつ `Fov.canSee` が真なら `Chasing` に遷移。
  `Awake` / `Chasing` は貪欲に 1 歩近づき、隣接時に攻撃する。
  閉じたドアはモンスターも開けて通過できる。逃走・群れ・特殊能力は未実装。
- プレイヤー攻撃: `d20 + level + strengthBonus` 対 `10 + monsterAC`。
  ダメージは `1d4 + strengthBonus`。最低 1。
- モンスター攻撃: `d20 + monsterLevel` 対 `10 + armor + playerLevel`。
  ダメージは種族ごとのダイス。
- `strengthBonus s = max 0 ((s - 10) / 3)`。
- 経験値閾値は `max 10 (10 * level)`。閾値を超えるたびに
  level +1、strength +1、最大/現在 HP +1d6。複数レベル分を一度に処理できる。
- 戦闘・出現値は暫定であり、Rogue 5.4.4 の観測値ではない。

### 17.4 step の M2 での解決順

```text
over = Just _        -> 状態を変えずに終了
プレイヤー行動       -> 移動 / 待機 / 拾得 / 下降 / 上昇メッセージ / 攻撃 / 扉 / 罠
ターン消費時のみ:
  turn += 1
  階層が変わっていなければ MonsterId 昇順にモンスター行動
  visible と explored を再計算
```

- 壁、施錠ドア、空の床での拾得、階段でない場所での階段コマンド、
  深度 26 での下降はターンを消費しない。
- 閉じたドアへの移動はドアを開くが、プレイヤーはその場に残る。
- モンスターのいるセルへの移動は攻撃。モンスターを倒すと経験値を得る。
- トラップは移動後に発動し、`revealed := True` にしてから効果を適用する。
- プレイヤーが死んだら `over = Just (Dead cause)`、HP 0。
  以降の `step` は no-op。
- `Outcome.messages` はその `step` の新規メッセージを時系列順、
  `Game.messages` は新しい順で最大 200 件。

### 17.5 テストと検証

- `tests/CoreTest.idr`: 固定フィクスチャでの移動、FOV、扉（開く・施錠・
  モンスターの扉開け）、起床・追跡・攻撃、拾得、所持上限、gold、
  下降、上昇メッセージ、深度 26、矢・トラップドア・テレポート、
  死亡、決定論。
- `tests/DungeonTest.idr`: 深度 1..26 の生成不変条件、部屋の非重複、
  階段の存在と到達性、モンスター/アイテム/トラップの妥当性、
  ID の連続性、同じ seed の決定論、`newGame` の開始位置。
- `tests/CombatTest.idr`: 強さボーナス、AC、命中・外れ・殺害、
  RNG 消費、経験値と複数レベルアップ。
- `tests/MapViewTest.idr`, `tests/ViewTest.idr`: M2 の `currentLevel` と
  新しいステータス表示に追従。
- `tests/PerfTest.idr`: M1 固定マップに加え、生成レベル、生存可能な
  生成レベルでの step、生成 100 回の計測を追加。
- `verify.sh` は `build/ttc` を消してからビルドする。この rc2 ビルドでは
  依存モジュールの変更をインクリメンタルビルドが取りこぼすことがあるため。

### 17.6 M2 の既知の制約

- 上昇・帰還・アミュレット・勝利は M3。
- 食料・ポーションの使用、装備、識別、空腹、状態異常は M3/M4。
- セーブ、自動保存、リプレイ、状態ハッシュは未実装。
- モンスターの逃走、群れ、遠距離攻撃、特殊能力は未実装。
- 部屋数は常に 9。迷路・部屋数の減少・隠しドア・鍵付きドアは未実装。
- 戦闘式、モンスター表、出現重み、経験値曲線、gold 量、トラップ確率は
  暫定値であり、M4 の忠実性監査で原本の観測値に置き換える。

## 18. M3 実装ノート（2026-10-29）

M3 ではアイテム使用、装備、識別、空腹、状態異常、アミュレット、上昇、
勝利を追加した。上の最終形と意図的に異なる現在の型と契約をここに記録する。

### 18.1 型の差分

```idris
public export
record Item where
  constructor MkItem
  id : ItemId
  kind : ItemKind
  location : ItemLocation
  count : Int32
  enchant : Int32
  cursed : Bool

public export
record Player where
  constructor MkPlayer
  pos : Coord
  hp, maxHp : Int32
  strength, maxStrength : Int32
  armor : Int32
  level : Int32
  exp : Int32
  gold : Int32
  hunger : Int32
  inventory : List ItemId
  wielded, worn : Maybe ItemId
  weaponDice, weaponSides, weaponBonus : Int32
  statuses : List Status

public export
record Status where
  constructor MkStatus
  statusKind : StatusKind
  remaining : Int32

public export
record Game where
  constructor MkGame
  seed : Bits64
  rng : Rng
  turn : Turn
  depth : Depth
  player : Player
  levels : List Level        -- 現在の階層が先頭。以下は訪問順
  items : List Item
  nextMonsterId, nextItemId : Bits32
  knownKinds : List ItemKind -- ラン内で正体が判明した種別
  messages : List Message
  over : Maybe GameOver
  visible : Bitset
```

- `ItemKind` は `Weapon WeaponKind | Armor ArmorKind | Food FoodRation |
  Potion PotionKind | Gold | Amulet`。巻物・杖・指輪はまだない。
- `WeaponKind = Dagger | Mace | Sword | TwoHandedSword`、
  `ArmorKind = Leather | RingMail | ChainMail | PlateMail`。
- `PotionKind` は 12 種。`StatusKind` の `Confused` / `Blinded` /
  `HasteSelf` などとの名前衝突を避けるため、`PotionHealing`,
  `PotionConfusion`, `PotionBlindness`, `PotionTeleport` のように接頭辞を付ける。
- `StatusKind = Confused | Blinded | Hasted | SeeInvisible |
  DetectMonsters | Poisoned`。麻痺・ホールド・減速・再生・ドレイン・浮遊はまだない。
- `Player.armor` は装備中の防具による合計 AC ボーナス。
  `weaponDice` / `weaponSides` / `weaponBonus` は装備中の武器から導出した
  攻撃プロファイルで、素手は `1d4 + 0`。
- `knownKinds` はラン全体の識別状態。ポーションは使用、武器・防具は装備で
  種別が加わる。`Gold` と `Amulet` は常に既知として扱う。
- `Monster` は引き続き `id, kind, pos, hp, maxHp, state` のみ。
  モンスターの状態異常と変身は M4。
- `Event` は M2 のものに `ItemUsed ItemId`, `ItemDropped ItemId`,
  `PlayerWon` を加えた。`PlayerDied` は死因を持たない。

### 18.2 アイテム API

`Core.Item` が出現表、強化値・呪い、表示名、所持品検索を持つ。

```idris
public export
makeItem : Depth -> ItemId -> ItemKind -> Coord -> Rng -> (Item, Rng)

public export
spawnItems : Depth -> List Coord -> ItemId -> Rng
          -> (List Item, ItemId, Rng)

public export
itemKnown : List ItemKind -> Item -> Bool

public export
itemDisplayName : List ItemKind -> Item -> String

public export
itemDetail : List ItemKind -> Item -> String

public export
packItems : Game -> List Item

public export
findPackItem : Game -> ItemId -> Maybe Item
```

- `makeItem` は武器・防具のときだけ強化値と呪いを引き、金のときだけ数量を引く。
- `itemDisplayName` は未識別ポーションに外見名を返し、未識別の武器・防具には
  強化値と呪いを付けない。`itemKnown` は金とアミュレットを常に `True` にする。
- `packItems` は `Player.inventory` の ID 順にアイテムを返す。
  `findPackItem` は `location = InPack` も確認する。

### 18.3 空腹と状態異常 API

`Core.Survival` がターン経過の規則をまとめる。

```idris
public export
hungerMax, hungryAt, weakAt, starvingAt : Int32

public export
data HungerState = Satiated | Normal | Hungry | Weak | Fainting

public export
hungerState : Int32 -> HungerState

public export
record SurvivalResult where
  constructor MkSurvivalResult
  player : Player
  messages : List String
  died : Maybe DeathCause

public export
tickSurvival : Player -> SurvivalResult
```

- 開始値は 1300。毎ターン -1。300 以下で hungry、0 以下で weak、
  -200 以下で starving。飢餓は毎ターン 1 ダメージ。
- `tickSurvival` は状態異常の残りターンを 1 減らし、毒の毎ターンダメージ、
  飢餓ダメージ、失効メッセージ、死亡判定をまとめて返す。
- 盲目の FOV は `Core.Fov.computeBlinded`（半径 1、部屋の明かりなし）を使う。
- 加速中は偶数ターンのモンスター行動を省略する。混乱中の移動は
  `Rng.pick` で 8 方向から選び直す。

### 18.4 step の M3 での解決順

```text
over = Just _        -> 状態を変えずに終了
プレイヤー行動       -> 移動 / 待機 / 拾得 / 使用 / 装備 / 落下 / 階段 / 攻撃
ターン消費時のみ:
  turn += 1
  階層が変わっていない、かつ加速の偶数ターンでなければ
    MonsterId 昇順にモンスター行動
  死亡していなければ状態異常・毒・空腹を進める
  visible と explored を再計算
```

- アイテム使用・装備・拾得・落下は 1 ターン。インベントリを開く、選択する、
  閉じるは `App` の状態だけで、Core の `step` を呼ばない。
- 不正な使用（持っていない ID、飲めない物、呪われた装備の交換など）は
  ターンを消費せず、警告メッセージだけを返す。
- 深度 1 の上り階段でアミュレットを持つと `Won`。アミュレットなしでは
  警告してターンを消費しない。深度 2 以上からの上昇は訪問済み階層を再利用する。
- 上昇時は現在の階層を `levels` の末尾へ回し、上昇先を先頭にする。
  下降時は同じ深度の訪問済み階層があれば再生成せず再利用する。
- 勝利・死亡が確定したターンは、それ以降のモンスター行動と生存時間を進めない。

### 18.5 テストと検証

- `tests/M3Test.idr`: ポーション 12 種の効果と識別、食料と空腹閾値、
  飢餓・毒のダメージと失効、武器・防具の装備と呪い、落下、
  アミュレット生成と取得、上昇・勝利、階層の保持と再利用、
  盲目 FOV、混乱の乱数消費、加速のモンスターターン省略。
- `tests/MapViewTest.idr`: アミュレットの `"` 表示、モンスター感知による
  記憶済みモンスターの表示。
- `tests/ViewTest.idr`: インベントリ画面のタイトル、一覧、23 スロットの
  2 列表示、ステータス行。
- `tests/SubsTest.idr`: インベントリの選択、動作キー、Enter、Esc/i。
- `tests/PerfTest.idr`: 10,000 ターンの step 計測用に、飢餓で死亡しない
  だけの栄養を与えたフィクスチャを追加。
- `verify.sh` は M3 時点では `m3-test` と `subs-test` を実行していた
  （現在は §19.7 の単一テストランナー）。

### 18.6 M3 の既知の制約

- 巻物、杖、指輪、投げる、充填数、識別の巻物は未実装。
- ポーションの外見は種別ごとに固定で、ランごとのランダム化は未実装。
- 装備は武器 1・防具 1 のみ。指輪 2 枠と両手持ちの制約は未実装。
- 状態異常は 6 種のみ。麻痺、ホールド、減速、再生、ドレイン、浮遊は未実装。
- 空腹・ポーション効果・強化値・呪い率・武器/防具の値は暫定値であり、
  Rogue 5.4.4 の忠実性監査は M4 で行う。
- セーブ、自動保存、戦績、状態ハッシュ、リプレイは未実装。

## 19. M4 実装ノート（2026-10-30、スライス 1）

M4 はスライスに分割する。ここではスライス 1（巻物・杖・指輪・投げる・
ランごとの外見）の現在の型と契約を記録する。§18 と同様、上の最終形と
意図的に異なる部分を含む。§19.1 の `Item` / `Player` / `Game` は §18.1 の
同じ型を置き換える。

### 19.1 型の差分

```idris
public export
record Item where
  constructor MkItem
  id : ItemId
  kind : ItemKind
  location : ItemLocation
  count : Int32
  enchant : Int32
  cursed : Bool
  charges : Int32      -- 杖の残り充填。それ以外は 0
  protected : Bool     -- 防具の錆び防止

public export
record Monster where
  constructor MkMonster
  id : MonsterId
  kind : MonsterKind
  pos : Coord
  hp, maxHp : Int32
  state : MonsterState
  statuses : List Status

public export
record Player where
  constructor MkPlayer
  pos : Coord
  hp, maxHp : Int32
  strength, maxStrength : Int32
  armor : Int32
  level : Int32
  exp : Int32
  gold : Int32
  hunger : Int32
  inventory : List ItemId
  wielded, worn : Maybe ItemId
  leftRing, rightRing : Maybe ItemId
  weaponDice, weaponSides, weaponBonus : Int32
  ringArmor, ringDamage, ringAccuracy, ringStrength : Int32
  statuses : List Status

public export
record Game where
  constructor MkGame
  seed : Bits64
  rng : Rng
  turn : Turn
  depth : Depth
  player : Player
  levels : List Level
  items : List Item
  nextMonsterId, nextItemId : Bits32
  knownKinds : List ItemKind
  appearances : List (ItemKind, String)
  messages : List Message
  over : Maybe GameOver
  visible : Bitset
```

`StatusKind` には M3 の 6 種に加えて `DetectFood`, `Invisible`, `Held`,
`Slowed`, `Paralyzed`, `Scared`, `Sleeping` を追加した。`Status` は
`MkStatus statusKind remaining` の 2 フィールドのままである。

### 19.2 アイテム API

- `itemPool depth` は深度で制限した全カテゴリの種別を返す。巻物・杖・指輪の
  最小深度は `Item.idr` の `scrollMinDepth` / `wandMinDepth` / `ringMinDepth`。
- `makeItem` は装備の強化値・呪い、金の量、杖の充填数を RNG から決める。
  杖の充填数は `1d5 + 2`（3–7）。それ以外の `charges` は 0。
- `rollAppearances` はポーション 12 種、巻物 18 種、杖 14 種、指輪 14 種の
  固定名リストをそれぞれシャッフルし、合計 58 個の `(ItemKind, String)` を返す。
  `newGame` はレベル生成後にこれを 1 回だけ呼び、`Game.appearances` に保存する。
  固定フィクスチャは `itemAppearance` の固定表にフォールバックする。
- `appearanceOf` はランの外見を返す。`itemDisplayNameIn` / `itemDetailIn` は
  ゲームと UI が使うラン対応の名前・詳細で、`itemDisplayName` / `itemDetail` は
  固定外見表を使うテスト・フィクスチャ用のヘルパーとして残している。
- 識別は種別単位で `Game.knownKinds` に保持する。未識別の武器・防具・指輪は
  強化値と呪いを表示せず、未識別の杖は充填数を表示しない。金とアミュレットは
  常に既知である。

### 19.3 コマンドと効果

```idris
public export
data Command
  = Move Dir
  | Wait
  | Search
  | PickUp
  | Quaff ItemId
  | Read ItemId
  | Eat ItemId
  | Wield ItemId
  | Wear ItemId
  | PutOnRing ItemId
  | TakeOff ItemId
  | Drop ItemId
  | Throw ItemId Dir
  | Zap ItemId Dir
  | Descend
  | Ascend
```

巻物 18 種の効果:

| 種別 | 効果 |
|---|---|
| `ScrollConfuseMonster` | 現在の階層の全モンスターに `Confused 12` |
| `ScrollMagicMapping` | 現在の階層を全探索済みにする |
| `ScrollHoldMonster` | 全モンスターに `Held 10` |
| `ScrollSleep` | 全モンスターを `Asleep` にし、`Sleeping 20` を付与 |
| `ScrollEnchantArmor` | 装備中の防具の `enchant` を +1 し、AC を再計算 |
| `ScrollIdentifyPotion` | 所持する最初の未識別ポーションを識別 |
| `ScrollIdentifyScroll` | 所持する最初の未識別巻物を識別 |
| `ScrollIdentifyWeapon` | 所持する最初の未識別武器を識別 |
| `ScrollIdentifyArmor` | 所持する最初の未識別防具を識別 |
| `ScrollIdentifyRingOrWand` | 所持する最初の未識別指輪/杖を識別 |
| `ScrollScareMonster` | 全モンスターを `Fleeing` にし、`Scared 12` を付与 |
| `ScrollFoodDetection` | プレイヤーに `DetectFood 30` |
| `ScrollTeleportation` | プレイヤーをランダムな歩行可能セルへ移動 |
| `ScrollEnchantWeapon` | 装備中の武器の `enchant` を +1 し、戦闘値を再計算 |
| `ScrollCreateMonster` | プレイヤー付近にモンスターを 1 体生成 |
| `ScrollRemoveCurse` | 所持品すべての `cursed` を False にする |
| `ScrollAggravateMonsters` | 全モンスターを `Chasing` にする |
| `ScrollProtectArmor` | 装備中の防具を `protected = True` にする |

装備中の防具/武器がない場合の強化・保護は警告を出し、ターンを消費しない。
識別系は対象がない場合も警告のみで、ターンを消費しない。

杖 14 種の効果:

| 種別 | 効果 |
|---|---|
| `WandLight` | 現在の階層を全探索済みにする |
| `WandInvisibility` | プレイヤーに `Invisible 20` |
| `WandLightning` / `WandFire` / `WandCold` | ビーム上の最初のモンスターに 6d6 |
| `WandMagicMissile` | 同 1d4 |
| `WandPolymorph` | 対象を深度の出現プールからランダムな種別に変え、HP を振り直す |
| `WandHasteMonster` | 対象に `Hasted 20` |
| `WandSlowMonster` | 対象に `Slowed 20` |
| `WandDrainLife` | 対象に 2d6、プレイヤーは同じ量だけ回復（最大 HP まで） |
| `WandNothing` | 「Nothing happens.」 |
| `WandTeleportAway` | 対象をランダムな歩行可能セルへ移動 |
| `WandTeleportTo` | プレイヤーをランダムな歩行可能セルへ移動 |
| `WandCancellation` | 対象の状態異常を消し、`Chasing` に戻す |

ビームは最大 8 セルで、壁・閉じたドアで止まり、最初のモンスターに当たる。
杖は 3–7 充填で始まり、振るたびに 1 充填を消費して種別を識別する。
充填 0 の杖は「The wand sputters.」で、ターンを消費せず識別もしない。

指輪 14 種の効果:

| 種別 | 効果 |
|---|---|
| `RingProtection` | AC に `1 + enchant` |
| `RingIncreaseDamage` | ダメージに `1 + enchant` |
| `RingIncreaseAccuracy` | 命中に `1 + enchant` |
| `RingDexterity` | 命中に +1（簡略化） |
| `RingAddStrength` | 実効筋力に +1 |
| `RingSustainStrength` | 列挙のみ。効果は未実装 |
| `RingSeeInvisible` | 透明なモンスターを見る |
| `RingStealth` | 眠っているモンスターの起床半径を半分にする |
| `RingRegeneration` | 3 ターンごとに HP を 1 回復（最大 HP 未満のとき） |
| `RingSlowDigestion` | 2 ターンごとに空腹を 1 回復 |
| `RingHunger` | 毎ターン空腹を追加で 1 減らす |
| `RingTeleportation` | 毎ターン 2% でランダムテレポート |
| `RingAggravateMonster` | 装備時に全モンスターを起こして追跡させる |
| `RingMaintainArmor` | 装備中の防具を錆びから守る |

指輪は左、右の順に装備する。両方埋まっている場合は「指が塞がっている」と
警告し、ターンを消費しない。呪われた指輪は外せない。装備すると種別を識別し、
AC・命中・ダメージ・筋力の派生値を再計算する。`RingDexterity` は原本の
筋力/敏捷の扱いを簡略化して命中 +1 にしている。

投げる:

- 装備中の武器・防具・指輪は投げられない（外すよう警告し、ターン消費なし）。
- 方向の先を最大 6 セルまで歩行可能セルでたどり、最初のモンスターで止まる。
- 武器は武器ダイス + `enchant` + 筋力ボーナス、それ以外は 1d2 のダメージ。
- ポーションは対象に当たると割れて消える。それ以外のアイテムは対象の手前、
  または経路の最後の歩行可能セルに落ちる。
- 投げると所持品から外れ、`ItemDropped` イベントを出す。1 ターンを消費する。

### 19.4 モンスターの状態異常

- `Monster.statuses` はプレイヤーと同じ `Status` を使う。
- モンスターターンの開始時に残りターンを 1 減らし、残り 1 以下になった状態は
  行動前に取り除く。
- `Held` / `Slowed` / `Paralyzed` / `Sleeping` は行動を飛ばす。
- `Confused` はランダムな隣接セルへ移動する。隣接していれば攻撃する。
- `Scared` はプレイヤーから最も遠い隣接セルへ逃げる。
- `Hasted` は 1 ターンに 2 回行動する。2 回目は更新後の位置と状態を再取得する。
- プレイヤーが `Invisible` のとき、隣接していないモンスターは追跡しない。
- 睡眠の巻物は `Asleep` と `Sleeping` を併用し、起床判定の直後に起きないようにする。

### 19.5 step の M4 での解決順

1. `Command` を検証し、プレイヤーの行動を解決する。
2. 巻物・杖・指輪・投げるの効果を適用する。杖は充填消費と識別を効果の前に、
   投げるはアイテムの移動をダメージの前に解決する。
3. モンスターの状態異常を 1 減らし、残っている状態に応じて行動または待機する。
4. 生存時間（状態異常の失効、毒、空腹、指輪の再生/消化/テレポート）を進める。
5. 死亡・勝利が確定していなければ FOV を再計算する。
6. レベル移動があったターンは、移動先のモンスターターンを省略する。

不正な操作（存在しない ID、装備中の物を投げる、空の杖、対象のいない強化巻物など）
は `turnConsumed = False` で返し、乱数を消費しない。

### 19.6 App / UI の追加

```idris
public export
data ItemAction
  = QuaffAction | ReadAction | EatAction | WieldAction | WearAction
  | PutOnAction | TakeOffAction | DropAction | ZapAction | ThrowAction

public export
data PendingDir
  = ZapDir ItemId
  | ThrowDir ItemId

public export
record Model where
  canvas : Canvas
  game : Game
  width, height : Len
  inventoryOpen : Bool
  selectedItem : Maybe ItemId
  inventoryIntent : Maybe ItemAction
  pendingDir : Maybe PendingDir
```

- `r/z/t/P/R/T` は所持品を開き、`inventoryIntent` に操作意図を保存する。
  アイテムを選ぶとその意図を即座に適用する。Enter はアイテムの既定動作。
- `ZapAction` / `ThrowAction` は所持品を閉じて `pendingDir` に移り、次の方向キーで
  `Zap` / `Throw` を発行する。Esc は `CancelDirection` で中止する。
- 再描画は `Ctrl-R` / `Ctrl-L`。`r` は巻物を読むキーになった。
- マップは巻物 `?`、杖 `/`、指輪 `=` を表示する。`DetectFood` 中は記憶済みの
  食料セルを暗いスタイルで表示する。
- インベントリは装備中の指輪に `*`、選択中のアイテムに `>` を付け、
  既知の杖は充填数、未識別品はランの外見名を表示する。ワイド画面のサイドバーは
  `Rings: 左 / 右` を表示する。
- 方向プロンプトは最新メッセージ行を置き換えて表示する。

### 19.7 テストと検証

- `tests/M4Test.idr`: 外見シャッフルの決定論、58 種の外見、深度プール、
  巻物 18 種の主要効果、杖 14 種の効果と充填、指輪の 2 枠と派生値、
  投げる、モンスター状態異常の行動規則。
- `tests/MapViewTest.idr`: `?` / `/` / `=` のグリフ、`DetectFood` による
  記憶済み食料の表示。
- `tests/SubsTest.idr`: `r/z/t/P` の所持品意図、方向キー、Esc キャンセル、
  `r` が巻物を読むキーであること。
- `tests/ViewTest.idr`: 指輪マーカー、既知の杖の充填数、未識別外見、
  ワイドサイドバーの指輪枠、方向プロンプト。
- `tests/PerfTest.idr`: 既存の Canvas / step 計測に加えて、
  `App.View` 全体（80x24、80x24 インベントリ、120x40）の描画を計測する。
- テストは `tests/TestRunner.idr` にまとめ、`lambda-rogue-tests.ipkg` で
  1 つの実行ファイルにビルドする。`tests/LambdaRogue` は
  `../src/LambdaRogue` へのシンボリックリンクで、テスト専用の
  `build/tests` に TTC を置く。`verify.sh` はメインパッケージと
  テストパッケージをビルドし、ランナーと PTY スモークテストを実行する。

### 19.8 M4 スライス 1 の既知の制約

- 巻物・杖・指輪の効果値、出現深度、充填数は暫定値であり、Rogue 5.4.4 の
  忠実性監査は M4 の残りで行う。
- `RingSustainStrength` は列挙のみで効果がない。`RingDexterity` は命中 +1 に
  簡略化している。
- 識別の巻物は指定カテゴリの最初の所持品を自動選択する。UI で対象を選ぶ
  ダイアログは未実装。
- モンスターはスライス 1 時点では 8 種だった。26 種、特殊能力、
  全トラップ効果はスライス 2 で追加した（§20）。
- 識別はアイテム個別ではなく種別単位。未識別フラグや「試した」履歴は持たない。
- 外見は `(ItemKind, String)` で保持する。セーブ・リプレイではこの対応表を
  そのまま保存する予定で、安定した `AppearanceId` はまだ導入していない。
- 杖の再充填、魔法の地図の永続化、ポーションの外見を含むセーブ、
  戦績、リプレイは未実装。

## 20. M4 実装ノート（2026-10-30、スライス 2）

M4 スライス 2 は A-Z 26 種のモンスター、特殊能力、プレイヤーの行動不能状態、
全トラップ効果を追加する。§19 の型を拡張し、モンスターがアイテムを所持できる
ようにした。数値と深度範囲は引き続き暫定値である。

### 20.1 型の差分

```idris
public export
data MonsterKind
  = Aquator | Bat | Centaur | Dragon | Emu | VenusFlytrap
  | Griffin | Hobgoblin | InvisibleStalker | Jackal | Kobold
  | Leprechaun | Medusa | Nymph | Orc | PurpleWorm | Quagga
  | Rattlesnake | Snake | Troll | UrVile | Vampire | Wraith
  | Xorn | Yeti | Zombie

public export
data MonsterAbility
  = PoisonBite | ConfusingGaze | HoldingAttack | FireBreath
  | RangedAttack | DrainLife | DrainExperience | RustArmor
  | StealGold | StealItem | Regenerate | Invisible
  | Erratic | Immobile

public export
record MonsterSpec where
  constructor MkMonsterSpec
  glyph : Char
  name : String
  level : Int32
  hpDice, hpSides : Int32
  damageDice, damageSides : Int32
  ac : Int32
  exp : Int32
  minDepth, maxDepth : Depth
  abilities : List MonsterAbility

public export
data ItemLocation
  = OnFloor Depth Coord
  | InPack
  | CarriedBy MonsterId
```

- `monsterSpec` は 26 種すべてを返す。`monsterName` / `monsterGlyph` と
  spec の名前・グリフは一致し、テストで一意性と A-Z の網羅を確認する。
- `hasAbility : MonsterAbility -> MonsterKind -> Bool` で能力を問い合わせる。
- `spawnPool` は深度範囲で絞り、該当がなければ `[Kobold]` を返す。
- `ItemLocation.CarriedBy` は窃取されたアイテムをモンスター個体に紐づける。

### 20.2 モンスター能力

- 毒・混乱・ホールド・ドレイン・装備錆・金/アイテム窃取は、命中ダメージの
  解決後に `monsterAbilityOnHit` が固定順で 1 つだけ適用する。
- 遠距離攻撃と炎は、`canSee` かつ距離 2–6 のときに `rangedStrike` を使う。
  隣接時は通常の `monsterStrike`。
- 再生はモンスターターンの開始時に最大 HP まで 1 回復する。
- 透明は `MapView` とサイドバーで、隣接するか `playerSeesInvisible` が真に
  なるまで隠す。`playerSeesInvisible` は `SeeInvisible` 状態または
  `RingSeeInvisible` で真になる。
- 不規則移動は隣接していなければランダムな空き隣接セルへ移動する。
- 不動は隣接時だけ攻撃し、移動しない。
- 盗まれたアイテムは `CarriedBy` になり、`dropCarriedBy` がモンスターの
  死亡時に最後の位置の床へ戻す。

### 20.3 プレイヤー状態とトラップ

- `Sleeping` / `Paralyzed`: `step` が全行動を消費し、
  `"You are asleep."` / `"You are paralyzed."` を出す。
- `Held`: `playerMove` は隣接モンスターへの攻撃だけ許可する。モンスターの
  いない方向へ移動を試みると `"You are held in place."` を出して 1 ターン消費する。
- トラップ効果:
  - `TrapDoor`: 深度 26 以外なら次階層へ落下。深度 26 では 1d6 ダメージ。
  - `Arrow`: 1d4、`Dart`: 1d3。
  - `Bear`: `Held 3` と 1d6 ダメージ。
  - `Sleep`: `Sleeping 10`。
  - `Teleport`: ランダムな歩行可能セルへ移動。
  - `Rust`: 装備中の防具の強化値を 1 下げる。保護または
    `RingMaintainArmor` があれば防ぐ。
  - `Mysterious`: 1d5 で睡眠・混乱・盲目・毒・テレポートのいずれか。
- 錆処理は `rustPlayerArmor` に集約し、トラップと Aquator の能力で共有する。

### 20.4 step の解決順

§19.5 と同じ。モンスターターンでは各モンスターの状態異常を 1 減らし、
再生を適用してから行動する。死亡したモンスターの所持品は、経験値付与より前に
床へ落とす。

### 20.5 テストと検証

- `tests/DungeonTest.idr`: 26 種、名前/グリフの一意性、A-Z 網羅、
  spec とヘルパーの一致、能力の重複なし、代表的な能力割当、深度プール。
- `tests/M4Test.idr`: 各能力（毒、混乱、ホールド、ドレイン、経験値ドレイン、
  錆、金/アイテム窃取、ドロップ、再生、遠距離、炎、不動）、
  プレイヤーの睡眠/麻痺/ホールド、睡眠/熊/ダーツ/錆/不思議トラップ。
- `tests/MapViewTest.idr`: 透明ストーカーの非表示、隣接、
  `SeeInvisible`、指輪による開示。
- `tests/CombatTest.idr` / `tests/CoreTest.idr`: フィクスチャを `Kobold` に更新。

### 20.6 M4 スライス 2 の既知の制約

- 26 種の HP・ダメージ・AC・経験値・深度範囲は暫定値。忠実性監査で置き換える。
- 毒は `Poisoned` 状態のターンダメージ、ドレインは最大 HP/経験値の減少として
  簡略化している。原本のレベルドレインや能力値ドレインは未実装。
- 透明は「隣接で見える」簡略化。原本の透明判定やサーチとの関係は監査対象。
- 群れ、睡眠確率、起床条件、逃走確率、深度ごとの出現重みは未実装または固定。
- トラップの作動確率・持続・深度別出現表は暫定。

## 21. M4 実装ノート（2026-10-31、スライス 3）

M4 スライス 3 は Core のゲーム規則を変えず、`App.Model`、`App.Update`、
`App.Subs`、`App.View`、`UI.MapView` にモダン UX を追加する。

### 21.1 App の状態

```idris
public export
data LogFilter
  = AllMessages | CombatMessages | ItemMessages
  | SystemMessages | WarningMessages

public export
record PaletteEntry where
  constructor MkPaletteEntry
  label : String
  hint : String
  action : Msg

public export
record Model where
  constructor MkModel
  canvas : Canvas
  game : Game
  width, height : Len
  inventoryOpen : Bool
  selectedItem : Maybe ItemId
  inventoryIntent : Maybe ItemAction
  pendingDir : Maybe PendingDir
  helpOpen : Bool
  paletteOpen : Bool
  paletteIndex : Nat
  logFilter : LogFilter
```

- `LogFilter` と `messageMatches` は表示専用である。`Game.messages` の内容や
  順序、ターン、乱数には触れない。
- `PaletteEntry.action` は通常の `Msg` である。`PaletteExecute` は
  `update entry.action` を呼ぶだけで、キーボードと同じ更新経路を通る。
- ヘルプ、パレット、インベントリは排他。開く操作は他のオーバーレイを閉じ、
  方向プロンプトも解除する。
- `initModel` の初期値は `helpOpen = False`, `paletteOpen = False`,
  `paletteIndex = 0`, `logFilter = AllMessages`。

### 21.2 入力

- 通常時: `?` / `F1` → ヘルプ、`Ctrl-P` → パレット、`F2` → ログフィルタ循環。
- ヘルプ表示中: Esc、`?`、F1、`q` で閉じる。他のキーは無視する。
- パレット表示中: Up/`k`、Down/`j` で移動、Enter で実行、Esc / `Ctrl-P` で閉じる。
  他のキーは無視する。
- `Ctrl-C` はオーバーレイ表示中でも終了する。
- 方向プロンプトとインベントリの既存ルーティングは、オーバーレイが
  開いていないときだけ評価する。

### 21.3 表示

- ワイド表示はヘッダ 1 行、メイン 30 行、ログ 8 行、ステータス 1 行。
  メイン左 80 列はマップ 80x22 と 36x8 ミニマップ、右 40 列はサイドバー。
- ミニマップは各ブロックの中心タイルを表示し、探索済みの階段とプレイヤーを
  座標から上書きする。未探索は空白、モンスター・アイテム・トラップは出さない。
- ワイドのログは `logFilter` に一致する直近 8 件を古い順に表示する。
  ヘッダにフィルタ名を出す。クラシックの最新行もフィルタに従い、
  all 以外では `[combat]` などの接頭辞を付ける。
- ワイドインベントリは左に一覧、右に詳細パネルを置く。詳細は表示名、
  スロット、カテゴリ、装備位置、強化値、呪い、既知の充填数、保護状態、
  装備中アイテムとの比較を出す。未識別の効果は表示しない。
- ヘルプは 80x24 では 18 行、120x40 では記号表と目標を加えた 24 行。
  パレットは 16 項目を選択マーカー付きで表示する。

### 21.4 テストと検証

- `tests/MapViewTest.idr`: ミニマップの行数・幅、プレイヤー、階段、
  未探索の非表示、モンスターの非表示、サイズ変更。
- `tests/SubsTest.idr`: `?`/F1/`Ctrl-P`/`F2`、ヘルプとパレットの閉じ方、
  オーバーレイ中の移動キー無視、パレットの移動・実行、フィルタ更新。
- `tests/ViewTest.idr`: ヘルプ（クラシック/ワイド）、パレット、
  ログフィルタ（クラシック/ワイド）、ミニマップ凡例、インベントリ詳細。
- `tests/PerfTest.idr`: 既存の 80x24 / 120x40 描画計測を継続する。

### 21.5 M4 スライス 3 の既知の制約

- パレットは固定 16 項目で、テキスト入力による絞り込みはまだない。
- ヘルプはキーマップ設定から生成せず、現行キーの静的リストである。
- オーバーレイの背景は暗くせず、中央にパネルを置くだけである。
- マウス、アニメーション、キーバインド変更は M4 の残り
  （テーマはスライス 5 で実装済み）。
- ログの折り返し・スクロールバック・同一メッセージの集約は未実装。
- インベントリのフィルタ・ソート・検索・数量指定は未実装。

## 22. M4 実装ノート（2026-10-31、スライス 4）

M4 スライス 4 は、ゲーム終了時の戦績、コマンド列からのリプレイ検証、
seed 共有を追加する。ゲーム規則と乱数消費順序は変えない。

### 22.1 `Core.Replay`

```idris
public export
record Replay where
  constructor MkReplay
  seed : Bits64
  commands : List Command   -- 新しい順

public export
emptyReplay : Bits64 -> Replay
public export
recordCommand : Command -> Replay -> Replay
public export
replayCommands : Replay -> List Command
public export
runReplay : Replay -> Game
public export
gameDigest : Game -> String
public export
replayMatches : Replay -> Game -> Bool
```

- `recordCommand` は先頭に追加する。`replayCommands` が `reverse` して
  実行順に戻す。
- `runReplay` は `newGame r.seed` から `step` を順に適用する。
  App が `newGame` 以外の状態（将来のセーブ復元）から始めた場合は、
  その状態を再現できないため `replayMatches` は不一致になる。
- `gameDigest` は `Game.messages` を除く状態の FNV-1a 64-bit。
  seed、RNG 状態、ターン、深度、プレイヤー、全訪問階層、アイテム、
  ID 採番、識別済み種別、外見表、終了状態、視界を含む。
  16 文字の小文字 hex を返す。
- `seedHex : Bits64 -> String` は `Core.Rng` にあり、16 文字に zero-pad
  した seed を返す。`stateHex` と同じ `Text.NumberFormat.toHex` を使う。
- `Core.Replay` は `IO`、`termui`、ファイル、時計を import しない。

### 22.2 App の状態と更新

```idris
public export
record Score where
  constructor MkScore
  seed : Bits64
  depth : Depth
  level : Int32
  exp : Int32
  gold : Int32
  turns : Turn
  result : GameOver

public export
scoreOf : Game -> Maybe Score
```

`Model` に `replay : Replay`、`scores : List Score`、`scoreOpen : Bool`、
`shareOpen : Bool`、`replayOk : Maybe Bool` を追加する。`initModel` は
`emptyReplay g.seed`、空の戦績、閉じたオーバーレイ、`Nothing` で始まる。

- `runCommand` は `step` の前にコマンドを記録する。ゲームが既に終了して
  いれば何もせず、記録もしない。
- `step` の結果が `over = Just _` になったら、`scoreOf` の値を戦績の先頭に
  追加し、`replayMatches` を一度だけ評価して `replayOk` に保存する。
  同時にスコア画面を自動で開く。
- `OpenScores` / `OpenShare` は他のオーバーレイと方向プロンプトを閉じる。
  `CloseScores` / `CloseShare` は対応するフラグだけを下ろす。
- `CopySeed` は `SetClipboard (seedHex m.game.seed)` を返す。

### 22.3 入力と表示

- 通常時: `S` → スコア、`Ctrl-S` → シード共有。
- スコア表示中: Esc、`S`、`q`、Enter で閉じる。他のキーは無視する。
- シード共有中: `c` / `C` / Enter でコピー、Esc / `Ctrl-S` / `q` で閉じる。
- `Ctrl-C` はどのオーバーレイでも終了する。
- パレットは 18 項目。`Scores`（`S`）と `Share seed`（`Ctrl-S`）を
  `Quit` の前に追加した。クラシック 80x24 ではタイトル 1 行 + 18 項目 +
  ヒント 1 行が枠内 20 行に収まる。
- スコア画面は新しい順に最大 8 件を表示し、seed と
  `Replay: verified` / `Replay: MISMATCH` / `Replay: not checked` を出す。
- シード共有画面は 16 文字の seed、深度、レベル、ターン、記録済み
  コマンド数、リプレイ検証結果、コピー方法を表示する。
- ヘッダとサイドバーの seed も `seedHex` の 16 文字表記に揃えた。

### 22.4 テストと検証

- `tests/ReplayTest.idr`: `seedHex` の長さと zero-pad、記録順、
  `newGame` との一致、手動実行との一致、余分なコマンドと別 seed の不一致、
  digest の決定性、`scoreOf` の未終了/勝利/死亡。
- `tests/SubsTest.idr`: `S` / `Ctrl-S`、スコア・共有の閉じ方、
  オーバーレイ中のキー無視、パレット 18 項目、終了時のスコア自動表示、
  終了後のコマンド無視。
- `tests/ViewTest.idr`: スコア画面の一覧・seed・検証結果・不一致表示、
  共有画面の seed・コマンド数・コピー説明。
- `tests/PerfTest.idr`: スコア画面と共有画面の描画時間を追加。

### 22.5 M4 スライス 4 の既知の制約

- スライス 4 時点では戦績はメモリ上だけだった。スライス 10 で
  `scores.jsonl` への追記と起動時の読み込みを追加した（§28）。
- スライス 4 の時点では可視リプレイ再生は未実装だった。スライス 8 で
  速度変更・一時停止・1 コマンド送り・再開・最初からの再生を追加した。
  途中チェックポイントとシークはまだない。
- スコアの並び替え、名前入力、殺害数、日時、死因の詳細表示は未実装。
- `gameDigest` は暗号学的ハッシュではない。改ざん検出ではなく、
  同一 seed とコマンド列の再現性確認に使う。
- メッセージ列の digest はまだ持たない。状態 digest のみを比較する。

## 23. UI テーマ（2026-11-01、スライス 5）

テーマは表示だけの関心事で、Core には存在しない。

### 23.1 型と変換

`LambdaRogue.UI.Theme` が `Theme` と `StyleRole` を公開する。

- `Theme = ClassicCga | ModernDark | Amber | GreenPhosphor | HighContrast | ColorblindSafe`
- `StyleRole` は背景、本文、タイトル、ヘッダ、警告、枠、ミニマップ、
  地形（岩・床・通路・ドア・階段）、モンスター、アイテム、トラップ、
  プレイヤー、メッセージ種別などの意味スロット。
- `styleFor : Theme -> StyleRole -> Style`
- `messageStyleFor : Theme -> MessageKind -> Style`
- `themes`, `nextTheme`

Classic CGA はスライス 4 までの ANSI 色と一致する。他テーマは
`Indexed` または `RGB` を使う。`MapView` は `cellForIn` / `mapCellsIn`、
`App.Canvas` は `drawMapIn` を提供し、既存の `cellFor` / `mapCells` /
`drawMap` は Classic CGA の別名として残す。

### 23.2 App の状態

`Model.theme : Theme` を末尾に追加する。`initModel` は `ClassicCga`。
`CycleTheme` は `nextTheme` で進め、`drawMapIn` で Canvas を再描画する。
`F3` はオーバーレイ表示中でも効く。スライス 5 の時点でパレットは
19 項目になり、`Scores` / `Share seed` の後、`Quit` の前に
`Cycle theme` を置いた。スライス 7 で `Toggle animation` を加えて 20 項目。

テーマ変更は `Command` ではないため、`Replay` に記録されず、
`gameDigest` にも含まれない。`F3` はターンを消費せず、乱数も消費しない。

### 23.3 テスト

- `tests/ThemeTest.idr`: 6 テーマの一意性、巡回、Classic の既存スタイルとの
  一致、テーマ別マップセル、メッセージスタイル、ヘッダの実描画スタイル、
  テーマ変更がゲーム状態を変えないこと。
- `tests/SubsTest.idr`: `F3`、オーバーレイ中の `F3`、パレット項目、
  `CycleTheme` の更新。
- `tests/ViewTest.idr`: ヘッダのテーマ名、ヘルプの `F3`、パレットの
  `Cycle theme`。
- `tests/PerfTest.idr`: Modern Dark の 120x40 描画。

### 23.4 既知の制約

- TrueColor 非対応端末の自動フォールバックと `--theme` は未実装。
  `settings.json` へのテーマ保存はスライス 9 で実装済み。
- テーマごとのグリフ変更（ASCII/Unicode）はまだない。色と属性だけを変える。

## 24. マウス（2026-11-02、スライス 6）

マウスは表示と入力の都合であり、Core には存在しない。`App.Mouse` が
端末の物理座標を画面レイアウト座標とゲーム座標へ変換し、キーボードと
同じ `Msg` に落とす。そのため Core の `Command`、乱数消費順、ターン、
リプレイ、`gameDigest` はマウスの有無で変わらない。

### 24.1 レイアウト座標

- `layoutSize : Model -> (Len, Len)` は `App.View.view` が選ぶ
  トップレベルレイアウトの寸法を返す。80x24 未満では画面全体、
  ヘルプは 100x30 / 80x24、パレット・スコア・シェアは 90x28 / 90x30 /
  78x24、通常とインベントリは 120x40 / 80x24。
- `layoutOrigin : Model -> (Len, Len)` は中央寄せの左上オフセット。
- `mapCellAt : Model -> Len -> Len -> Maybe Coord` は通常マップの
  セルを返す。マップはクラシックでは最新メッセージ行の下、ワイドでは
  ヘッダ行の下から始まるため、どちらもレイアウト上端 + 1 行を引く。
  オーバーレイ表示中や画面が 80x24 未満のときは `Nothing`。
- `isWideScreen` は `width >= 120 && height >= 40`。これは `View` の
  ワイド判定と同じ条件で、マウス側だけ判定がずれないようにしている。
- 端末座標は `MouseEvent.column` / `MouseEvent.row`（0 始まり、`Len`）。
  `Len` の引き算は負になり得るため、各判定で 0 以上を確認する。

### 24.2 メッセージ変換

`mouseMsg : Model -> MouseEvent -> Maybe Msg` が唯一の入口で、
`App.Subs` の `OnMouse` から呼ばれる。`Msg` を返さないイベントは
状態を変えない。

- 通常画面のマップ左クリック: クリック先が探索済みなら、プレイヤーから
  そのセルへの 1 歩の `Do (Move d)`。隣接モンスターなら Core が攻撃に
  解決する。自分のセルなら床のアイテムを `Do PickUp`、上下階段なら
  `Do Ascend` / `Do Descend`。未探索セルとマップ外は無視する。
- 方向プロンプト中（`pendingDir`）: 同じクリックが `Do (Zap iid d)` または
  `Do (Throw iid d)` になる。方向は `directionTo` の 8 方向。
- マップの移動/ドラッグ: `HoverCell (mapCellAt ...)`。マップ外は
  `HoverCell Nothing`。ホバーは `App.Model.hover` を更新するだけで、
  ターンも乱数も消費しない。
- ログ領域のホイール: クラシックは最新メッセージ行、ワイドは
  31〜38 行目。下回しで `CycleLogFilter`、上回しで
  `CycleLogFilterBack`。
- インベントリ: 行クリックで `SelectItem`、ダブルクリックで
  `ActOnItem (defaultAction i)`、`inventoryIntent` 付きなら 1 クリックで
  そのアクション。ホイールは前後の `SelectItem`、パネル外クリックと
  右クリックは `CloseInventory`。
- パレット: 行クリックで `PaletteSelect`、ダブルクリックで
  `PaletteRun`、ホイールで `PalettePrev` / `PaletteNext`、
  パネル外・ヒント行・右クリックで `ClosePalette`。
- ヘルプとスコア: 左/右クリックで閉じる。シェア: コピー行で
  `CopySeed`、閉じる行・パネル外・右クリックで `CloseShare`。

`inventorySlotAt` はクラシックの左右 2 列（左が 0〜19、右が 20〜39）と
ワイドの 1 列を扱う。`App.Model.defaultAction` は Enter キーと
ダブルクリックで共有し、両者が同じ既定動作になるようにしている。

### 24.3 表示

`UI.MapView.describeCell : Game -> Coord -> Maybe String` は、未探索なら
`Nothing`、探索済みなら地形名と、そのセルに見えているモンスター・
アイテム・発見済みトラップを返す。`MapView.highlightCell` はホバー中の
セルに `Inverse` を足し、`App.Canvas.drawMapWith` がテーマとホバーを
受け取って描く。ホバー中は最新メッセージ行の代わりにツールチップを
出すが、ログ本体とゲーム状態は変えない。

### 24.4 テスト

- `tests/MouseTest.idr`: 80x24 / 100x30 / 120x40 の座標変換、
  マップクリック、方向プロンプト、自分のセルの拾い上げと階段、
  インベントリの 2 列・意図付きクリック・ホイール、
  パレット・ヘルプ・スコア・シェア、ログホイール、ホバー強調と
  ツールチップ、ホバーがターンとリプレイを変えないこと。
- `tests/SubsTest.idr`: `OnMouse` の常時購読と `CycleLogFilterBack`。
- `tests/ViewTest.idr`: ホバー時のツールチップとヘルプのマウス説明。
- `tests/PerfTest.idr`: 通常・インベントリ・ワイド・テーマ・
  オーバーレイの描画時間。マウス経路は描画を追加しない。

### 24.5 既知の制約

- termui はボタン/ドラッグ追跡（1002）を使うため、通常のホバーを
  送らない端末では、移動やドラッグをしないとツールチップが更新されない。
- 右クリックはオーバーレイを閉じるだけ。コンテキストメニュー、
  長押し、ドラッグによる連続移動は未実装。
- 階段クリックの確認、`MouseFocus` によるウィジェットフォーカス、
  マウス設定の保存は未実装。キーボードだけで全操作できる状態を保つ。

## 25. アニメーション（2026-11-02、スライス 7）

アニメーションは表示だけの関心事で、Core の `Game` も `step` も変更しない。
`Outcome.events` を入力に、`UI.Animation` が短命の `Effect` を作り、
`App.Model.animations` に保持する。

### 25.1 型

`LambdaRogue.UI.Animation` が公開するもの:

- `EffectKind = Trail | Impact | Damage Int32 | Death | Pickup |
  DoorMark | TrapMark | LevelUpMark | Victory`
- `Effect`（`kind`, `pos`, `age`, `life`）
- `mkEffect : EffectKind -> Coord -> Effect`
- `effectsFor : Game -> Game -> List Event -> List Effect`
- `advanceAnimations : List Effect -> List Effect`
- `mergeAnimations : List Effect -> List Effect -> List Effect`
- `effectCells : List Effect -> List (Int32, Int32, Char, StyleRole)`

`life` は 16ms ティック数。移動・攻撃・拾い上げ・ドアは 4、
ダメージ数字とトラップは 12/8、死亡は 8、レベルアップは 10、勝利は 16。
`effectsFor` はステップ前の `Game` から残像・倒したモンスターの位置を、
ステップ後の `Game` から落下アイテムや死亡位置を取る。

### 25.2 App の状態と更新

`Model` の末尾に `animations : List Effect` と
`animationsEnabled : Bool`（初期値 `True`）を追加する。

- `runCommand` は `step` の `events` から効果を作り、
  `mergeAnimations` で最大 24 個まで保持する。無効時は作らない。
- `AnimationTick` は `advanceAnimations` で 1 ティック進め、
  マップ表示中なら Canvas を再描画する。すべて消えたらタイマーは止まる。
- `subs` は `animations` が空でないときだけ
  `Every "animation" 16 AnimationTick` を追加する。
- `ToggleAnimations` は `F4` とパレットの `Toggle animation` から届く。
  無効にすると現在の効果も消す。
- `App.Canvas.drawMapAnimated` がマップの後に効果を描く。既存の
  `drawMapWith` / `drawMapIn` / `drawMap` は効果なしの別名として残す。
- `effectCells` は効果を古い順に返し、同じセルでは新しい効果が勝つ。
  ダメージ数字は複数桁を横に並べ、80x22 の外へは描かない。

### 25.3 テスト

- `tests/AnimationTest.idr`: イベント別の位置と種類、複数桁ダメージ、
  右端クリップ、ティックによる加齢と消滅、24 個の上限、新しい効果の
  優先、無効時の効果なし、アニメーション有無でターンとリプレイが
  一致すること。
- `tests/SubsTest.idr`: `F4`、オーバーレイ中の `F4`、アニメーション中だけ
  `Every` が購読されること。
- `tests/ViewTest.idr`: ヘルプの `F4` とパレットの `Toggle animation`。

### 25.4 既知の制約

- 移動の補間、投射物の飛翔、視界のフェードは未実装。現在はセル単位の
  残像・記号・数字だけ。
- 速度設定は 16ms 固定。`prefers-reduced-motion` や環境変数の自動検出は
  未実装。無効化は `F4` / パレットに加え、`settings.json` の `animation`
  （スライス 9 で実装）でも行える。
- アニメーションは 1 ターン分のイベントをまとめて出す。イベント間の
  順序再生や、複数ターンのキューイングはまだない。

## 26. 可視リプレイ再生（2026-11-02、スライス 8）

可視再生は App の表示状態だけで、Core のリプレイ形式や検証結果を変えない。
`App.Model.playback` が再生を所有し、表示中だけ `Model.game` を再生用の
ゲームに差し替える。元のゲームは `Playback.original` に保持する。

### 26.1 型

`LambdaRogue.App.Model` が公開するもの:

- `PlaybackSpeed = SlowPlayback | NormalPlayback | FastPlayback`
- `playbackDelay : PlaybackSpeed -> Nat`（400 / 200 / 80 ms）
- `fasterPlayback`, `slowerPlayback`
- `Playback`（`original`, `replay`, `remaining`, `played`,
  `commandCount`, `playing`, `speed`, `done`, `verified`）
- `playbackOpen : Model -> Bool`

`remaining` は `replayCommands` の順（古いコマンドが先頭）。`replay` は
記録済みの `Replay` をそのまま参照し、再生中に `recordCommand` しない。

### 26.2 開始と更新

- スコア画面で `P` を押すと `StartReplay`。`scoreOpen` を閉じ、
  `game := newGame replay.seed`、`remaining := replayCommands replay` にする。
  `verified` は `replayOk == Just True`。
- `ReplayTick` は 1 コマンドだけ `step` し、`played` を進める。
  `remaining` が空になるか `game.over` になったら `done := True`,
  `playing := False`。
- `ReplayStep` は一時停止中でも 1 コマンド進める。
- `ReplayToggle` は Space の一時停止/再開。`ReplaySpeedUp` /
  `ReplaySpeedDown` は速度を上下限付きで変える。
- `ReplayRestart` は `newGame replay.seed` に戻して最初から再生する。
- `CloseReplay` は `Playback.original` を `game` に戻し、スコア画面を開く。
- `subs` は再生中かつ `playing` かつ残りがあるときだけ
  `Every "replay" (playbackDelay speed) ReplayTick` を追加する。
- `runCommand` と `mouseMsg` は `playbackOpen` の間は入力を処理しない。
  `F3` テーマと `F4` アニメーションだけは共通の先頭節で引き続き使える。

再生中の `step` は `Replay` に記録しないため、`replay.commands` と
`gameDigest` は開始前のまま不変である。

### 26.3 表示

通常の 80x24 / 120x40 レイアウトを使い、`Model.game` が再生用ゲームなので
マップ、サイドバー、ログ、ステータスはそのまま追従する。最上段は
`REPLAY n/N speed state verified` に置き換える。`state` は
`playing` / `paused` / `complete`。スコア画面には
`P replays from the start.` の案内を出す。

### 26.4 テスト

- `tests/PlaybackTest.idr`: 初期状態、1 コマンド進行、カウンタ、
  一時停止中のティック無視、再開、速度変更、再スタート、完走時の
  記録状態との一致、終了時の元ゲーム復元、空リプレイ。
- `tests/SubsTest.idr`: スコア画面の `P`、再生中のタイマー、Space、
  Esc、再生中の通常キー抑止、一時停止時のタイマー停止。
- `tests/MouseTest.idr`: 再生中のクリック無視。
- `tests/ViewTest.idr`: スコア画面の再生案内と `REPLAY` 表示。

### 26.5 既知の制約

- 途中チェックポイント、状態スナップショット、任意位置へのシークは未実装。
  現在は最初から 1 コマンドずつ進めるだけ。
- 再生速度は 3 段階の固定値。フレーム単位の補間や可変速度はない。
- 再生中のログスクロール、マウス操作、アイテム詳細表示は無効。
  キーボードの再生操作だけを提供する。

## 27. キーマップと設定（2026-11-02、スライス 9）

設定は表示と入力のためだけに存在する。Core は `Keymap` も `Settings` も
import せず、キー変更が `Command`、ターン、RNG、`Replay`、`gameDigest` に
影響することはない。

### 27.1 型

`LambdaRogue.App.Keymap`:

- `KeyChord`（`key : Key`, `mods : Mods`）。文字キーは大文字小文字を区別し、
  `Ctrl-` / `Alt-` 付きの文字は端末差を吸収するため小文字に正規化する。
  Shift は文字そのもの（`Q`）で表し、修飾子としては保持しない。
- `CommandId`: `MoveNorth` ... `Quit` の安定した識別子。
  `Show` はデバッグ用、`commandName` / `commandFromName` は
  `settings.json` 用の文字列（`move-north`, `pick-up`, `put-on-ring` など）。
- `Binding`（`id`, `label`, `keys`）と `Keymap = List Binding`。
- `defaultKeymap`、`bindingFor`、`keysFor`、`setBindingKeys`、
  `commandForChord`、`hasDuplicateChords`、`chordText`、`formatKeys`、
  `formatPrimary`、`parseKeyChord`、`anyArrowKeys`。

`LambdaRogue.App.Settings`:

```idris
public export
record Settings where
  constructor MkSettings
  theme : Theme
  animationsEnabled : Bool
  keymap : Keymap

public export
defaultSettings : Settings
settingsSchema : String
settingsSchema = "lambda-rogue.settings.v1"
```

`settingsFromJSON` / `settingsFromText` は純粋で、`settingsToJSON` /
`settingsToText` が書き込み用の値を返す。

### 27.2 `settings.json`

```json
{
  "schema": "lambda-rogue.settings.v1",
  "theme": "modern-dark",
  "animation": true,
  "keys": {
    "move-north": ["k", "Up"],
    "inventory": ["i"],
    "help": ["?", "F1"],
    "quit": ["Q", "Ctrl-C"]
  }
}
```

- `schema` は必須。未知のスキーマはファイル全体を拒否する。
- `theme` / `animation` は省略可能で、既定は `classic-cga` / `true`。
- `keys` の値は 1 つのコード文字列、またはコード文字列の配列。
  空配列はそのコマンドを未割り当てにする。
- 未知のコマンド ID は無視する。既知の ID の値が壊れている場合、
  または同じコードが 2 つのコマンドに割り当てられた場合はファイル全体を
  拒否し、既定値にフォールバックする。
- コードは 1 文字（`k`, `Q`, `>`）、`Ctrl-S`、`Alt-X`、`F1`〜`F12`、
  `Up` / `Down` / `Left` / `Right`、`Home` / `End` / `PageUp` / `PageDown`、
  `Insert` / `Delete`、`Enter` / `Tab` / `Backspace` / `Esc`、`Space` を
  受け付ける。
- ファイルは `$XDG_DATA_HOME/lambda-rogue/settings.json`、環境変数が
  なければ `$HOME/.local/share/lambda-rogue/settings.json`。
  `Persist.Settings` の `loadSettings` / `saveSettings` が IO を担当する。
  保存は現在、同一ディレクトリの一時ファイル + rename ではなく直接書き込み
  である（base に rename がないため）。失敗時は `IO Bool` で false を返す。
- テーマ巡回とアニメーション切替は設定を自動保存する。キーマップは
  パレットの `Save settings` で保存し、`Reload settings` で読み直す。

### 27.3 入力ルーティング

- 通常プレイ、インベントリ、方向プロンプトは `Model.keymap` の
  `commandForChord` で `CommandId` を求め、既存の `Msg` に変換する。
  したがってキー変更は UI の入力経路だけを変え、Core のコマンド列は
  同じ意味のままである。
- ヘルプ、パレット、スコア、シェア、再生画面の閉じるキーなどは、
  それぞれの画面が持つ小さな固定キー集合を使う。これは画面内の
  ナビゲーションであり、ゲームコマンドではない。
- `F3`（テーマ）と `F4`（アニメーション）はオーバーレイ中も共通の先頭で
  処理する。`Ctrl-C` は再生中も含めて緊急終了として最優先で扱う。
- 既定キーは `q` = ポーション、`Q` / `Ctrl-C` = 終了、`i` = インベントリ、
  `?` / `F1` = ヘルプ、`Ctrl-P` = パレット。通常プレイの Esc は終了しない。

### 27.4 表示

- ヘルプの移動・アイテム・UI 行は `helpLines : Keymap -> List String` が
  有効なキーマップから生成する。移動キーは 8 方向の主キーを並べ、
  矢印が 1 つでも割り当てられていれば `/ arrows` を添える。
- パレットの `hint` は `paletteEntriesFor : Keymap -> List PaletteEntry` が
  `formatPrimary` で生成する。固定のヒント文字列は持たない。
- パレットは 25 項目。`Save settings` / `Reload settings` / `Save and quit` /
  `Load game` はキーを持たない項目として 19 / 20 / 21 / 22 番目に置き、
  `Search for traps` が 23 番目、`Quit` が 24 番目である。
- 狭い 80x24 では 25 項目を 13 行 2 列に分け、広い 120x40 では 1 列に並べる。
- 設定は `App.Model` の `theme` / `animationsEnabled` / `keymap` にだけ
  存在し、`Game` には保存されない。

### 27.5 テスト

- `tests/SettingsTest.idr`: 既定キー、コード解析・表示、再割り当て、
  重複検出、JSON の往復、未知 ID の無視、空配列の未割り当て、
  不正値・重複・未知テーマの拒否、モデルの入力ルーティング、
  設定適用がゲームとリプレイを変えないこと、ファイル往復。
- `tests/SubsTest.idr`: キーマップ経由の移動・アイテム・方向、
  25 項目のパレット、設定・セーブ・ロード項目、グローバルキー。
- `tests/ViewTest.idr`: ヘルプとパレットのヒントが再割り当てに追従すること、
  ワイドヘルプが設定ファイルを示すこと。

### 27.6 既知の制約

- キー割り当てを対話的に編集する設定画面はない。ファイル編集と
  `Reload settings` で変更する。
- 設定の書き込みは直接 `writeFile` で、クラッシュ時の部分書き込みを防ぐ
  atomic rename は未実装。セーブ/オートセーブは `Persist.Save` の
  アトミック書き込みを使う。
- 不正な設定ファイルは既定値にフォールバックするため、どの行が悪いかを
  UI には表示しない。修正はファイルを直接確認する。
- マウス操作、テキスト入力、再生画面の操作はキーマップの対象外である。

## 28. ファイル永続化（2026-11-04、スライス 10-11）

戦績、リプレイ、セーブ/オートセーブ、セッションロックを追加した。
Core は JSON もファイル API も知らず、`Persist.*` が純粋な値と IO の境界を持つ。
詳細なスキーマと検証項目は `doc/persistence.md` を参照する。

### 28.1 モジュール

| モジュール | 役割 |
| --- | --- |
| `Persist.Paths` | `$XDG_DATA_HOME/lambda-rogue` または `$HOME/.local/share/lambda-rogue` の解決、`settings.json` / `scores.jsonl` / `replays/` / `save.json` / `autosave.json` / `session.lock` のパス、ディレクトリ作成、`joinPath`。 |
| `Persist.Json` | `Language.JSON` の型検証: `asString`, `asBool`, `asInt32`, `asBits32`, `field`, `asArray`, `arrayOf`, `hex64`。 |
| `Persist.Codec` | 座標、方向、状態、モンスター状態/種別、全アイテム種別、トラップ、メッセージ種別、タイル、死因、`GameOver` の安定 codec。 |
| `Persist.Score` | `lambda-rogue.score.v1` の JSON、JSON Lines の追記・読み込み。 |
| `Persist.Replay` | `lambda-rogue.replay.v1` のコマンド/replay JSON、保存・読み込み、ファイル名、一覧。 |
| `Persist.Save` | `lambda-rogue.save.v1` の `Game` 全体 codec、検証、アトミック書き込み、オートセーブ、削除、`session.lock`。 |
| `Persist.Settings` | 既存の `settings.json` IO。パス解決を `Persist.Paths` に委譲する。 |

Core 側の追加は `Core.Rng.seedFromHex`、`Core.Bitset.fromHex`、
`Core.Replay` の既存 API (`runReplay`, `gameDigest`, `replayMatches`,
`seedHex`) だけである。`Persist` は `Core` を import するが、逆方向の
依存はない。

### 28.2 戦績 `scores.jsonl`

```json
{"schema":"lambda-rogue.score.v1","seed":"0123456789abcdef","depth":7,"level":5,"exp":123,"gold":87,"turns":1240,"result":{"result":"dead","cause":{"kind":"monster","monster":"dragon"}}}
```

- 1 行 1 レコード。ファイルは古い順、`loadScores` は反転して新しい順を返す。
- `Score` の全フィールド（seed, depth, level, exp, gold, turns, result）を保存する。
- `result` は `gameOverToJSON` と同じ入れ子表現。死因は `monster` / `trap` /
  `starved` / `drained` / `other`。
- 空行、壊れた JSON、スキーマ不一致の行はスキップする。
- 追記は `appendScoreAt`、全体読み込みは `loadScoresAt`。パスを明示する
  `At` 版はテスト用でもある。

### 28.3 セーブ `lambda-rogue.save.v1`

トップレベルは `schema`, `kind`, `gameVersion`, `savedAt`, `game`。
`game` は `Core.Types.Game` の全フィールドを持つ。

```idris
record SaveFile where
  kind : SaveKind          -- Manual | Autosave
  savedAt : String
  game : Game

saveToJSON : SaveKind -> String -> Game -> JSON
saveFromJSON : JSON -> Maybe SaveFile
saveToText : SaveKind -> String -> Game -> String
saveFromText : String -> Maybe SaveFile
```

- `Save.SaveKind` は `Manual` / `Autosave`。`show` がそのまま `kind` になる。
- `Game` の seed は 16 文字、RNG 状態は 32 文字、`explored` / `visible` は
  448 文字の小文字 hex。
- `levels[].tiles` は 22 行 x 80 文字。タイルコードは
  `Persist.Codec.tileText` / `tileFromText` の 9 文字。
- アイテムの `location` は `pack` / `floor` / `monster`。識別知識は
  アイテムではなく `knownKinds` と `appearances` が持つ。
- `saveFromJSON` はスキーマ、`gameVersion`、`savedAt`、`Game` 全体を検証し、
  1 つでも不正なら `Nothing`。`loadSaveAt` は構文エラーも `Nothing` にする。
- `saveGameAt` / `saveGame` / `autoSave` は一時ファイル + `fsync` +
  `.bak` rename + `rename` + ディレクトリ `fsync` を使う。
- `loadSave` / `loadAutosave` / `deleteSave` / `deleteAutosave` が
  本番パスを解決する。`At` 版はテスト用。

### 28.4 セッションロック

```idris
acquireLockAt : String -> IO Bool
releaseLockAt : String -> IO ()
acquireSessionLock : IO Bool
releaseSessionLock : IO ()
```

- `session.lock` は `{ "pid": Int, "startedAt": String }`。
- 生存中の PID（`kill(pid, 0)` が成功、または `EPERM`）があれば `False`。
- `ESRCH` または壊れた JSON は stale とみなし、ロックを置き換えて `True`。
- `releaseLockAt` は自分が持つロックだけを削除する。
- `Main` はロック取得前にセーブを読まない。取得できなければメッセージを
  出して終了する。

### 28.5 App との接続

- `App.Update.persistRun` はゲーム終了へ遷移した瞬間に `appendScore` と
  `saveReplay` を `Perform` で実行し、`save.json` / `autosave.json` を削除する。
  失敗してもスコア画面とゲーム終了処理は継続する。
- 前進ターンが 10 の倍数になるたびに `autoSave` を `Perform` で実行する。
  表示専用コマンドはターンを進めないため、オートセーブも走らない。
- パレットの `Save and quit` は `saveGame Manual` の成功時だけ終了する。
  失敗時はゲームに留まる。
- パレットの `Load game` は `loadSave` を実行し、成功したら `game` を
  置き換え、リプレイを新しい seed で初期化し、`save.json` と
  `autosave.json` を削除する。読み込み失敗時は現在のランを維持する。
- `Main` は起動時に `settings` と `scores` を読み、`save.json`、
  `autosave.json` の順に再開する。読み込んだファイルは削除し、
  `"Resumed from save."` / `"Recovered from autosave."` を `SystemMsg`
  としてログ先頭に追加する。メッセージは `gameDigest` の対象外。
- `Main` はコマンドラインの `--seed <16 桁小文字 hex>` を
  `App.Startup.parseStartSeed` で解釈する。指定時はセーブを読まず、
  `save.json` / `autosave.json` を削除して `newGame seed` を開始する。
  未指定でセーブもない場合は、`System.Clock` の UTC ナノ秒と PID を
  `combineSeed` で混ぜた 64-bit seed を生成する。
- `App.Startup` は IO を持たない純粋な引数解析と seed 混合だけを担当し、
  `tests/StartupTest.idr` で `--seed` の受理・拒否を検証する。
- 正常終了時は `autosave.json` を削除し、最後に `releaseSessionLock` を呼ぶ。

### 28.6 テスト

`tests/PersistTest.idr` が次を検証する。

- `seedFromHex`、`Bitset.fromHex` の往復と不正入力。
- `Persist.Json` の型検証と `Persist.Codec` の全列挙・タイル・死因の往復。
- 勝利/死亡スコアの JSON 往復、JSON Lines の追記順、壊れた行のスキップ、
  欠損ファイル、未知スキーマ。
- 全コマンド種別のリプレイ JSON/テキスト往復、未知スキーマ、バージョン
  不一致、未知コマンド、不正方向、ファイル往復、壊れたファイルの拒否。
- セーブのスキーマ・種別・バージョン・`savedAt`、JSON/テキスト往復、
  不正な ID カウンタ、存在しない所持品、ファイル往復、`.bak`、
  壊れたファイル、欠損ファイル。
- セッションロックの取得、生存 PID の拒否、解放、死んだ PID と
  壊れたファイルの再利用。
- `verify.sh` はクリーンビルド、814 件のテスト、PTY スモークを実行する。

### 28.7 既知の制約

- 手動セーブはパレットの `Save and quit` だけで、任意地点のセーブはない。
- 専用のロード画面はなく、起動時の自動再開とパレットの `Load game` だけ。
- 復旧確認ダイアログはない。`save.json` がなければ `autosave.json` を
  自動で採用する。
- `session.lock` は `hostname` / `bootId` を持たず、PID 再利用を厳密に
  判定しない。生存 PID は安全側で実行中とみなす。
- `settings.json`、`scores.jsonl`、リプレイファイルの書き込みは
  `writeFile` / `appendFile` で、atomic rename と `fsync` は未実装。
- リプレイの一覧・選択 UI、チェックポイント、シークは未実装。
- 戦績の名前、殺害数、プレイ日時、並び替え UI は未実装。
- `gameDigest` は暗号学的ハッシュではない。改ざん検知ではなく再現性確認用。
- Clang 19 は rc2 の生成する `if ((a == b))` を
  `-Wparentheses-equality` として警告する。rc2 が `-Werror` を付けるため、
  `verify.sh` は Clang 検出時に `IDRIS2_CFLAGS` へ
  `-Wno-parentheses-equality` を追加する。

## 29. Rogue 5.4.4 忠実性監査（2026-11-07、スライス 12）

M4 の最後に、`Core` のデータ表・式・生成確率を 5.4.4 の公開データと照合した。
最終的な数値表は `doc/rogue-reference.md` を正とし、ここでは API との対応と
実装上の式だけをまとめる。

### 29.1 モンスター

- `MonsterSpec` は `glyph`, `name`, `level`, `attacks`, `ac`, `exp`,
  `minDepth`, `maxDepth`, `abilities` を持つ。
- `monsterSpec` の 26 種は 5.4.4 の公開モンスター表と一致する。
  `level` は表のレベル、`attacks` は `(個数, 面数)` のリスト、`ac` は表の AC、
  `exp` は HP ボーナスを除いた基礎経験値。
- `rollMonsterHp` は `roll level 8`。生成時とポリモーフ時の両方で使う。
- `monsterExpGain spec hp` は 5.4.4 の `exp_add` と同じ式:

  ```
  divisor = if level == 1 then 8 else 6
  multiplier = if level >= 10 then 20 else if level > 6 then 4 else 1
  exp + (hp / divisor) * multiplier
  ```

- `spawnPool depth` は深度帯に入る種類を返す。`spawnMonsters` は
  `monsterCount depth = min 12 (2 + depth/2)` 体を生成し、各種類を等確率で選ぶ。
- 睡眠確率は 80%、`UsuallyAsleep` は 92%。
- `hasAbility` は能力の有無を返す。`Fast` は `monsterTurn` で 2 回行動、
  `Regenerate` は各モンスターの手番で HP +1。

### 29.2 戦闘と成長

- `playerArmorClass p = p.armor - p.ringArmor`。`p.armor` は防具の AC で、
  素手は 10。低いほど良い。
- `playerAttack p m g` の命中率:

  ```
  clamp 0 100 (5 + 5 * p.level + 5 * (monsterSpec m.kind).ac + p.ringAccuracy)
  ```

  1d100 を振り、出目が命中率以下なら命中。
- `strengthDamageBonus s` は 5.4.4 の筋力表:

  ```
  s <= 6       => s - 7
  7..15        => 0
  16..17       => 1
  18           => 2
  19..20       => 3
  21           => 4
  22..30       => 5
  31 以上      => 6
  ```

- プレイヤーのダメージは
  `max 1 (武器ダイス + strengthDamageBonus (effectiveStrength p)
          + p.weaponBonus + p.ringDamage)`。
- `monsterChance p m = clamp 0 100 (20 + 5 * (monsterSpec m.kind).level
  + 5 * playerArmorClass p)`。
- `monsterAttack` は `attacks` の各要素を独立に振り、合計ダメージを返す。
  `0d0` でも命中すれば特殊能力の契機になる。
- `expForNext` は 10, 20, 40, ..., 8,000,000 の累積表。`gainExperience` は
  経験値を消費せず、`level < 21` の間、必要経験値を満たすたびに
  `1d10` の最大 HP を得る。筋力は増えない。

### 29.3 アイテム生成

- `randomItemKind` の種別重み:

  | 種別 | 重み |
  | --- | --- |
  | potion | 26 |
  | scroll | 36 |
  | food | 16 |
  | weapon | 7 |
  | armor | 7 |
  | ring | 4 |
  | stick | 4 |

- `itemCount depth = min 8 (2 + depth/3)`、`goldPileCount depth =
  min 5 (1 + depth/5)` は M4 の密度値。公開表の値ではない。
- `enchantRoll kind`:
  - 武器: 1d100 が 0–9 で呪い、10–14 で祝福、それ以外は +0。
  - 防具: 0–19 で呪い、20–27 で祝福、それ以外は +0。
  - 呪いは `-(rnd(3)+1)`、祝福は `+(rnd(3)+1)`。範囲は -3..+3。
- `ringEnchantRoll`:
  - protection / add strength / dexterity / increase damage は
    `uniform 3` を 1 回振り、0 なら -1 かつ呪い、1 なら +1、2 なら +2。
  - aggravate monster / teleportation は +0 で常に呪い。
  - それ以外は +0、呪いなし、乱数消費なし。
- `wandCharges`:
  - `Wand WandLight` は `uniform 10` で 10–19。
  - それ以外の杖は `roll 1 5` で 3–7。
- `makeItem` は装備品のときだけ強化値・呪いを振り、指輪のときだけ
  `ringEnchantRoll` を振る。Gold の `count` は `1d10 * depth`（最低 1）。

### 29.4 アイテム効果

- 防具の AC は `armorValue a - enchant`。`recomputeArmor` が `p.armor` に入れる。
- 武器のダメージは `weaponDamage` のダイス + `enchant`。投擲は
  `weaponThrowDamage` を使う。
- 指輪の常時補正は `recomputeRings` が `ringArmor`, `ringDamage`,
  `ringAccuracy`, `ringStrength` に展開する。dexterity は `ringAccuracy` のみ。
- 回復の指輪は `survivalTurn` で 1 個につき HP +1。
- slow digestion は 1 個で空腹減少を 2 ターンに 1 回、2 個で 0 にする。
- テレポートの指輪は毎ターン `chance 2`（1/2）。
- ステルスの指輪は眠っているモンスターの起床半径を半分にする。
- sustain strength は毒・筋力ドライン・dart トラップを無効化する。
- maintain armor は錆を無効化する。`protected` の防具も錆びない。
- ポーション、巻物、杖、トラップの個別効果は
  `doc/rogue-reference.md` 10〜14 章の表を正とする。

### 29.5 既知の簡略化

次の項目は 5.4.4 と意図的に異なる。詳細と全リストは
`doc/rogue-reference.md` 17 章を参照する。

- 武器の命中・ダメージ強化値を単一の `enchant` で表す。
- 出現選択は深度帯の等確率で、原本の `level + rnd(10) - 6` ではない。
- 群れ生成、モンスターの所持率表、弓・投擲の遠距離攻撃は未実装。
- 巻物の sleep / scare / hold、remove curse、confuse monster の対象・範囲が違う。
- 杖の light / drain life / cancellation の効果が違う。
- ポーションの幻覚・盲目・透明などの効果時間は短い固定式で、一部の効果は簡略化している。
- 飢餓は 0 以下で毎ターン 1 HP、失神と `-850` 死亡は未実装。
- 自然回復は静穏ターンではなくターン番号の剰余で近似する。
- トラップの命中判定・セーヴ・矢の落下、浮遊のトラップ無効は未実装。
- 秘密のドアを生成しないため、探索はトラップだけを発見する。
- orc の強欲 AI、xeroc の物体擬態、ドラゴンの火炎反射は未実装。

### 29.6 テスト

- `tests/M4Test.idr` にモンスター表、装備の呪い・祝福、指輪の強化値、
  光の杖の充填数、dexterity の命中のみ反映、トラップ、ドラゴンの火炎、
  巻物・杖・ポーションの主要効果の回帰テストがある。
- `tests/CombatTest.idr` に命中式、筋力ダメージ、複数攻撃、経験値曲線、
  レベルアップのテストがある。
- `tests/CoreTest.idr` に生成の決定論、深度帯、モンスターの能力、
  アイテムの不変条件のテストがある。
- 正確なチェック数は `verify.sh` の実行結果と
  `doc/m1-measurements.md` を参照する。

## 30. M5 実装ノート（2026-11-09、スライス 1）

探索、searching の指輪、healing / extra healing、magic missile を
5.4.4 の式に合わせた。既存のリプレイ形式には `Search` を 1 種類追加しただけで、
他のコマンドの意味と乱数消費順は変えていない。

### 30.1 探索

```idris
public export
data Command
  = ...
  | Search
  | ...
```

- `Search` は 1 ターン消費し、プレイヤーは移動しない。
- 隣接 8 マスの未発見トラップを、現在の階の `traps` の順に判定する。
- 各トラップで `uniform (2 + 盲目 2 + 幻覚 3)` を振り、0 なら `revealed`
  を立てる。通常 1/2、盲目 1/4、幻覚 1/5、盲目 + 幻覚 1/7。
- 発見時は種別ごとのメッセージ、幻覚中は「You found a trap.」を出す。
  何も見つからなければ「You search but find nothing.」を出す。
- 秘密のドアは生成しないため、探索対象はトラップだけである。
- `searchTraps : Step -> (Step, Bool)` は探索の乱数消費と発見をまとめた
  内部関数で、`Search` と searching の指輪の両方が使う。

### 30.2 searching の指輪

- 移動が成立したターンだけ、`countRing RingSearching` の回数だけ
  `searchTraps` を無料で実行する。
- 待機、攻撃（移動先にモンスターがいる場合）、アイテム使用、階層移動では
  発動しない。
- 無料探索は追加のターンを消費せず、「何も見つからない」メッセージも出さない。
- 実行位置は `advanceTurn` の後、モンスター行動の前である。

### 30.3 回復ポーション

- healing: `roll p.level 4`。`hp + n > maxHp` なら `maxHp + 1` を新しい
  最大 HP とし、HP もその値にする。
- extra healing: `roll p.level 8`。`hp + n > maxHp` なら、まず
  `hp + n > maxHp + level + 1` のとき `maxHp + 2`、そうでなければ
  `maxHp + 1` を新しい最大 HP とし、HP をその値にする。
- どちらも超過しなければ HP だけを `min maxHp (hp + n)` まで回復する。

### 30.4 杖 of magic missile

- `WandMagicMissile` のダメージを 1d4 に変更した。ビームは最初に当たった
  モンスター 1 体だけに効く。

### 30.5 App と永続化

- `CommandId.Search`、既定キー `s`、パレット `Search for traps`
  （23 番目、全 25 項目）、ヘルプの wait / search / pick up 行を追加した。
- `Persist.Replay` は `{ "type": "Search" }` を読み書きする。
  `tests/PersistTest.idr` の往復対象コマンドに `Search` を加えた。

### 30.6 テスト

- `tests/M5Test.idr`（15 チェック）: 探索のターン消費、隣接トラップの発見、
  遠距離トラップの非発見、空探索のメッセージ、searching の指輪の移動時発動、
  待機時の非発動、healing / extra healing のダイスと最大 HP 増加、
  magic missile の 1d4。
- `tests/M3Test.idr` の extra healing は、固定の全回復ではなく
  「HP が増え、最大 HP を超えない」ことを検証する形に更新した。
- `tests/SettingsTest.idr`、`tests/SubsTest.idr`、`tests/ViewTest.idr` に
  `s` キー、パレット 25 項目、ヘルプの search 表示を追加した。
- 全体は 795 チェックから 814 チェックへ増えた。
