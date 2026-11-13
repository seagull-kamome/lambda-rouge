# lambda-rogue 永続化・リプレイ設計

- Status: Draft 0.13（M5 スライス 7 の Xeroc の物体擬態を反映。永続化形式の変更なし）
- Date: 2026-11-13
- 対象: `LambdaRogue.Persist.*`, `LambdaRogue.Core.Replay`
- 前提: `doc/design.md` Draft 1.17, `doc/core-api.md` Draft 1.12

## 1. 方針

- Core は JSON を知らない。`Game` の純粋な値を `Persist` が読み書きする。
- セーブは「ゲーム状態の完全なスナップショット」、リプレイは
  「seed + 意味的コマンド列」とする。どちらも実装済み。
- 数値の 64-bit は JSON の `Double` で正確に表せないため、16 進文字列にする。
  seed は 16 文字、RNG 状態は 32 文字、`explored` / `visible` は 448 文字。
- 列挙値は序数ではなく安定した文字列で保存する。実装の並び替えで壊れない。
- 壊れたレコードの扱いは形式ごとに異なる。
  - セーブ: 全フィールドを検証し、1 つでも不正ならファイル全体を拒否する。
  - 戦績: 壊れた行だけをスキップし、残りの履歴を失わない。
  - リプレイ: スキーマ、バージョン、seed、コマンド列を検証し、
    1 つでも不正ならファイル全体を拒否する。
- `settings.json`、`scores.jsonl`、リプレイファイルは現在 `writeFile` /
  `appendFile` で直接書き込む。セーブとオートセーブだけは一時ファイル +
  `fsync` + `rename` のアトミック更新を使う。

## 2. ファイル配置

```
$XDG_DATA_HOME/lambda-rogue/       # なければ ~/.local/share/lambda-rogue/
  save.json                        # 手動セーブ。読み込み後に削除
  save.json.bak                    # 直前の手動セーブ
  autosave.json                    # 10 ターンごとと終了時のクラッシュ復旧用
  autosave.json.bak                # 直前のオートセーブ
  session.lock                     # 実行中プロセスの PID と起動時刻
  scores.jsonl                     # 戦績（追記）
  replays/
    <seedHex>-<utcSeconds>.replay.json
  settings.json                    # UI 設定
```

- `--data-dir` によるルート上書きは未実装。
- `save.json` と `autosave.json` は同じスキーマを使い、`kind` で区別する。
- 起動時は `session.lock` を取得してから、`save.json`、なければ
  `autosave.json` の順に探す。読み込んだファイルはその場で削除し、
  二重復元を防ぐ。復旧確認のダイアログはなく、自動で再開する。
- `settings.json` はテーマ、アニメーション、言語、キーバインドを持つ。
  セーブ/リプレイの再現性には影響しない。
- 戦績とリプレイはゲーム終了時に `App.Update.persistRun` が書き込む。
  戦績は起動時に `Main` が読み込む。リプレイの一覧・選択 UI は `F5` の
  `Replay browser` で実装済み。
- 手動セーブはパレットの `Save and quit`（保存して終了）だけ。
  `Load game` はパレットから `save.json` を読み直す。起動時の自動再開とは別経路。

### 2.1 `settings.json` スキーマ `lambda-rogue.settings.v1`

```json
{
  "schema": "lambda-rogue.settings.v1",
  "theme": "classic-cga",
  "animation": true,
  "animationSpeed": "normal",
  "language": "en",
  "keys": {
    "move-north": ["k", "Up"],
    "inventory": ["i"],
    "help": ["?", "F1"],
    "quit": ["Q", "Ctrl-C"]
  }
}
```

- `schema` は必須。一致しないファイルは読み込まない。
- `theme` は `classic-cga`, `modern-dark`, `amber`, `green-phosphor`,
  `high-contrast`, `colorblind-safe`, `monochrome` の安定 ID。
  省略時は `classic-cga`。`--theme <id>` はこの値をその起動だけ上書きする。
- `animation` は Boolean。省略時は `true`。`--no-animation` と
  環境変数 `NO_MOTION` はこの値より優先して、その起動だけ無効にする。
- `animationSpeed` は `slow`, `normal`, `fast` のいずれか。省略時は
  `normal`。ティック間隔はそれぞれ 32 / 16 / 8 ms。未知の ID は
  ファイル全体の拒否につながる（既知の値の綴り間違いを黙って
  既定値にしないため）。
- 実行環境の色能力は設定ファイルに保存しない。`NO_COLOR` / `TERM=dumb`
  は `monochrome`、TrueColor 非対応端末は ANSI の
  `classic-cga` / `high-contrast` へ実行時にフォールバックする。
  `--no-color` は `NO_COLOR` と同じ扱いで、この起動だけモノクロにする。
- `language` は `en` または `ja`。省略時は `en`。未知の ID は `en` に
  フォールバックする。`--lang en|ja` はこの値をその起動だけ上書きする。
  言語は表示専用で、`Game`, `Replay`, `gameDigest` には入らない。
- `keys` はコマンド ID をキーとする object。値は 1 つのコード文字列または
  配列。空配列は「未割り当て」を意味する。
- コマンド ID は `move-north`, `move-south`, `pick-up`, `put-on-ring`,
  `quit` などの安定文字列で、配列の位置や `Show` の出力ではない。
- 未知のコマンド ID は無視する。既知の ID の値が不正、または同じコードが
  複数のコマンドに割り当てられている場合は、ファイル全体を拒否して
  既定値にフォールバックする。
- 設定は `App.Settings` の純粋な JSON 変換と、`Persist.Settings` の
  パス解決・IO に分かれる。設定は `Game`, `Replay`, `gameDigest` の
  どれにも含めない。
- パスは `$XDG_DATA_HOME/lambda-rogue/settings.json`。環境変数がなければ
  `$HOME/.local/share/lambda-rogue/settings.json`。ディレクトリがなければ
  作成する。
- 保存は現状 `writeFile` による直接書き込みで、戻り値は `IO Bool`。
  失敗してもゲームは継続する。テーマ巡回・アニメーション切替は自動保存し、
  キーマップはパレットの `Save settings` で保存、`Reload settings` で
  読み直す。

## 3. セーブスキーマ `lambda-rogue.save.v1`（実装済み）

セーブは JSON 1 ファイルで、トップレベルにメタデータ、`game` に
`Game` の完全なスナップショットを持つ。ゲーム状態の各値は
`Persist.Codec` の安定した列挙名・タイルコードで書く。

### 3.1 例

```json
{
  "schema": "lambda-rogue.save.v1",
  "kind": "manual",
  "gameVersion": "0.1.0",
  "savedAt": "2026-11-04T12:34:56Z",
  "game": {
    "seed": "0123456789abcdef",
    "rng": "c6a145a7a1e13311c902e7a0ec0096a9",
    "turn": 1240,
    "depth": 7,
    "player": {
      "pos": { "x": 12, "y": 7 },
      "hp": 12, "maxHp": 20,
      "strength": 16, "maxStrength": 16,
      "armor": 4, "level": 5, "exp": 123, "gold": 87, "hunger": 1200,
      "inventory": [1, 2, 4],
      "wielded": 2, "worn": 4,
      "leftRing": null, "rightRing": null,
      "weaponDice": 1, "weaponSides": 4, "weaponBonus": 0,
      "ringArmor": 0, "ringDamage": 0,
      "ringAccuracy": 0, "ringStrength": 0,
      "statuses": [
        { "kind": "Poisoned", "remaining": 12 }
      ]
    },
    "levels": [
      {
        "depth": 1,
        "tiles": ["################################################################################", "..."],
        "explored": "0000000000000000...",
        "rooms": [
          { "x": 3, "y": 2, "w": 12, "h": 6, "dark": false }
        ],
        "monsters": [
          {
            "id": 11, "kind": "kobold", "pos": { "x": 20, "y": 5 },
            "hp": 4, "maxHp": 4, "state": "asleep",
            "statuses": []
          }
        ],
        "traps": [
          { "pos": { "x": 30, "y": 8 }, "kind": "arrow", "revealed": false }
        ],
        "upStairs": null,
        "downStairs": { "x": 40, "y": 18 }
      }
    ],
    "items": [
      {
        "id": 1, "kind": "food ration",
        "location": { "kind": "pack" },
        "count": 1, "enchant": 0, "cursed": false,
        "charges": 0, "protected": false
      },
      {
        "id": 3, "kind": "potion of healing",
        "location": { "kind": "floor", "depth": 3, "x": 12, "y": 7 },
        "count": 1, "enchant": 0, "cursed": false,
        "charges": 0, "protected": false
      },
      {
        "id": 4, "kind": "ring mail",
        "location": { "kind": "monster", "monster": 11 },
        "count": 1, "enchant": 0, "cursed": false,
        "charges": 0, "protected": false
      }
    ],
    "nextMonsterId": 42,
    "nextItemId": 100,
    "knownKinds": ["food ration", "potion of healing"],
    "appearances": [
      { "kind": "potion of healing", "name": "murky potion" }
    ],
    "messages": [
      {
        "turn": 1240,
        "kind": "combat",
        "key": "hit-monster",
        "args": ["kobold", "4", "no"],
        "text": "You hit the kobold for 4 damage."
      }
    ],
    "over": null,
    "visible": "0000000000000000..."
  }
}
```

### 3.2 トップレベル

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `schema` | string | 常に `lambda-rogue.save.v1`。一致しなければ拒否 |
| `kind` | string | `manual` または `autosave` |
| `gameVersion` | string | `LambdaRogue.Version.version` と完全一致。不一致は拒否 |
| `savedAt` | string | ISO 8601 UTC。空文字は拒否。ゲーム状態には影響しない |
| `game` | object | 3.3 以降 |

### 3.3 `game`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `seed` | string | 16 文字の小文字 hex |
| `rng` | string | 32 文字の小文字 hex（`Rng` の `s0` + `s1`） |
| `turn` | integer | `Game.turn`。0 以上 |
| `depth` | integer | 現在の階層。1..26 |
| `player` | object | 3.4 |
| `levels` | array | 訪問済みの階層。3.6 |
| `items` | array | ラン全体のアイテム。3.7 |
| `nextMonsterId` | integer | 次のモンスター ID。既存の最大 ID より大きい |
| `nextItemId` | integer | 次のアイテム ID。既存の最大 ID より大きい |
| `knownKinds` | array[string] | 判明済みのアイテム種別（安定名） |
| `appearances` | array | `{ "kind": 安定名, "name": 表示名 }` のラン内の外見表 |
| `messages` | array | 新しい順で最大 200 件。3.8 |
| `over` | object/null | 勝利または死亡。3.8 |
| `visible` | string | 448 文字の小文字 hex（現在の視界ビットセット） |

- `depth` は `levels` に含まれなければならない。
- `knownKinds` と `appearances` はランごとの知識・外見で、`settings.json`
  とは独立している。
- `messages` は `gameDigest` の対象外。リプレイ検証では状態だけを比較する。
- 現在の検証は `appearances` の重複や全種別の網羅性までは見ない。

### 3.4 `player`

- `pos`: `{ "x": 0..79, "y": 0..21 }`。
- `hp`, `maxHp`, `strength`, `maxStrength`, `armor`, `level`, `exp`,
  `gold`, `hunger`: 整数。`0 <= hp <= maxHp`、`0 <= strength <= maxStrength`、
  `level >= 1`、`exp >= 0`、`gold >= 0`、`hunger >= 0`。
- `inventory`: `ItemId` の配列。所持順で、長さは 23 以下。重複禁止。
  各 ID は `items` に存在し、`location.kind = "pack"` でなければならない。
- `wielded`, `worn`, `leftRing`, `rightRing`: `ItemId` または `null`。
  指定した ID は `inventory` に含まれ、`location.kind = "pack"` でなければならない。
- `weaponDice`, `weaponSides`, `weaponBonus`: 装備武器の展開値。
- `ringArmor`, `ringDamage`, `ringAccuracy`, `ringStrength`: 指輪の常時補正。
- `statuses`: `{ "kind": StatusKind, "remaining": Int }`。
  `kind` は `show StatusKind` の安定文字列（`confused`, `poisoned`,
  `sleeping`, `mimicking an object` など）。
  同じ `kind` を重複させず、`remaining >= 0`。

### 3.5 タイル文字コード

セーブ内の `tiles` は表示グリフではなく、状態を一意に表す固定コードを使う。

| 文字 | `Tile` |
| --- | --- |
| `#` | `Rock` |
| `.` | `Floor` |
| `:` | `Corridor` |
| `+` | `Door Closed` |
| `'` | `Door Open` |
| `s` | `Door Secret` |
| `l` | `Door Locked` |
| `<` | `Stairs Up` |
| `>` | `Stairs Down` |

- 表示グリフは `UI/Glyph.idr` が別に決める。セーブの文字を画面に直結しない。
- 未知の文字はロードエラー。将来タイルを追加するときは `save.v2` にする。

### 3.6 `levels[]`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `depth` | integer | 1..26。重複禁止 |
| `tiles` | array[string] | 22 行 x 80 文字。3.5 の文字コード |
| `explored` | string | 448 文字の小文字 hex（28 x 64 bit） |
| `rooms` | array | `{ "x", "y", "w", "h", "dark" }` |
| `monsters` | array | 3.6.1 |
| `traps` | array | `{ "pos", "kind", "revealed" }` |
| `upStairs` | object/null | `{ "x", "y" }` |
| `downStairs` | object/null | `{ "x", "y" }` |

- `explored` のビット位置は `i = y * 80 + x`。ワードは `i div 64`、
  ビットは `i mod 64` の最下位ビットから。余った 32 bit は 0。
- `tiles` の行数・各行の長さが 22x80 でない場合はロードエラー。
- `levels` は空でなく、現在の階層を含む。
- 同じ ID のモンスターをラン全体で重複させない。

#### 3.6.1 `monsters[]`

- `id`: ラン全体で一意。
- `kind`: モンスター名の安定文字列（例 `"kobold"`, `"venus flytrap"`）。
- `pos`: 現在の座標。
- `hp`, `maxHp`: `hp <= maxHp`。
- `state`: `"asleep"`, `"awake"`, `"chasing"`, `"fleeing"` のいずれか。
- `statuses`: `player.statuses` と同じ形式。同じ `kind` を重複させない。
- `mimicking an object` は `MimicObject` を持つ Xeroc だけが持てる。
  古いセーブにこの状態がなければ、擬態なしとして復元する。

### 3.7 `items[]`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `id` | integer | ラン全体で一意 |
| `kind` | string | アイテム種別の安定名（例 `"food ration"`, `"ring mail"`） |
| `location` | object | `floor`, `pack`, `monster` のいずれか |
| `count` | integer | 1 以上 |
| `enchant` | integer | 強化値 |
| `cursed` | boolean | 呪い |
| `charges` | integer | 0 以上 |
| `protected` | boolean | 劣化耐性 |

- `location` は次のいずれか。
  - `{ "kind": "pack" }`
  - `{ "kind": "floor", "depth": 1..26, "x": 0..79, "y": 0..21 }`
  - `{ "kind": "monster", "monster": MonsterId }`
- `floor` の `depth` は `levels` に存在し、`monster` の ID は
  `levels[].monsters[].id` に存在しなければならない。
- 識別状態はアイテムごとではなく `game.knownKinds` が持つ。
  アイテムごとの `identified` / `appearance` フィールドは v1 にはない。
- `player.inventory` は `location.kind = "pack"` のアイテムだけを参照する。

### 3.8 `over` と `messages`

```json
{ "result": "dead", "cause": { "kind": "monster", "monster": "kobold" } }
{ "result": "dead", "cause": { "kind": "trap", "trap": "arrow" } }
{ "result": "dead", "cause": { "kind": "starved" } }
{ "result": "dead", "cause": { "kind": "drained" } }
{ "result": "dead", "cause": { "kind": "other", "text": "..." } }
{ "result": "won" }
```

- `over` が `null` 以外なら、それ以降の `step` は no-op。
- 死亡・勝利時は `App.Update.persistRun` が `save.json` と
  `autosave.json` を削除する。死亡後の復活には使えない。

```json
{ "turn": 1240, "kind": "combat", "text": "You hit the kobold." }
```

- `kind`: `combat`, `item`, `system`, `warning`, `story`。
- `key` と `args` は M5 スライス 2 で追加した安定したメッセージ識別子と
  引数。`key` は `damage`, `hit-monster`, `descend-level` などの文字列で、
  `args` は同じ順序の文字列配列。英語の `text` は常に保存する。
- `key` / `args` のない旧セーブは `key = ""`, `args = []` として読み込み、
  保存済みの英語 `text` をそのまま表示する。未知の `key` も同じ経路で
  `text` にフォールバックする。
- 最大 200 件。`Game.messages` は新しいものが先頭なので、ファイル上も新しい順。
- メッセージは `gameDigest` の対象外。`text` は言語切替の影響を受けない。

## 4. リプレイスキーマ `lambda-rogue.replay.v1`

### 4.1 例

```json
{
  "schema": "lambda-rogue.replay.v1",
  "gameVersion": "0.1.0",
  "seed": "0123456789abcdef",
  "commands": [
    { "type": "Move", "dir": "N" },
    { "type": "PickUp" },
    { "type": "Quaff", "item": 3 }
  ]
}
```

ファイル上の `commands` はプレイ順である。`Core.Replay` の内部表現は
記録を O(1) にするため新しい順なので、`Persist.Replay` が書き込み時に
`replayCommands` で反転し、読み込み時に再び反転する。

現在の v1 は `seq`、実行前ターン、開始位置、チェックポイント、最終結果を
持たない。これらは将来の v2 で追加する。

### 4.2 コマンド

`type` は `Core.Command` の構築子名。引数は次の通り。

| `type` | 追加フィールド |
| --- | --- |
| `Move` | `dir`: `N`, `NE`, `E`, `SE`, `S`, `SW`, `W`, `NW` |
| `Wait`, `Search`, `PickUp`, `Descend`, `Ascend` | なし |
| `Quaff`, `Read`, `Eat`, `Wield`, `Wear`, `PutOnRing`, `TakeOff`, `Drop` | `item`: `ItemId` |
| `Throw`, `Zap` | `item`: `ItemId`, `dir`: 方向 |

- `ItemId` は整数の JSON 数値。現在の ID は小さく、読み込み側は
  整数として正確に表せる 32-bit 値だけを受け付ける。
- キー入力ではなく `Command` を記録する。キーバインド変更でリプレイが壊れない。
- 表示言語はリプレイに保存しない。`--lang` や `settings.json` を変えても
  コマンド列と `gameDigest` は同じで、再生時のログ表示だけが変わる。
- UI のモーダル、ログスクロール、ヘルプ閲覧は記録しない。
- 不成立だったコマンドも記録する。警告メッセージの再現に必要。
- 未知の `type`、必須フィールドの欠落、不正な方向、文字列の item ID は
  ファイル全体の拒否につながる。

### 4.3 検証とバージョン

- `schema` は `lambda-rogue.replay.v1` と完全一致しなければならない。
- `gameVersion` は実行中の `LambdaRogue.Version.version` と完全一致しなければ
  ならない。欠落・不一致のファイルは `Nothing` として拒否する。
- `seed` は 16 文字の小文字 hex。`Persist.Codec` の `seedFromHex` で解析する。
- `commands` は配列で、各要素が 4.2 のいずれかに一致しなければならない。
- `replayFromText` は JSON 自体の構文エラーも `Nothing` にする。
- 将来の `replay.v2` は変換ツールを別に用意する。v1 の読み込みを壊さない。

### 4.4 ファイル名と一覧

- 保存名は `<seedHex>-<utcSeconds>.replay.json`。
  例: `0123456789abcdef-1700000000.replay.json`。
- `utcSeconds` は表示・一覧用のメタデータで、リプレイの内容や
  `gameDigest` には含めない。
- `Persist.Replay.listReplayFiles` は `replays/` 内の
  `.replay.json` だけを辞書順で返す。`F5` のリプレイ一覧はこの結果を
  新しい順に表示し、選択したファイルを `loadReplayFile` で読み込む。
  壊れたファイルは一覧にエラーを表示し、ゲームは継続する。
- 再生位置のシークは保存形式ではなくメモリ内の操作で、`Replay` の
  `seed` と `commands` から prefix を再実行して状態を作る。
  ファイルの書き換えや `gameDigest` の変更は行わない。
- 保存前に `replays/` を作成する。失敗してもゲーム終了処理は継続する。

### 4.5 メモリ内リプレイと検証

```idris
record Replay where
  seed : Bits64
  commands : List Command   -- 新しい順

runReplay : Replay -> Game
gameDigest : Game -> String
replayMatches : Replay -> Game -> Bool
seedHex : Bits64 -> String
```

- App は `step` に渡した `Command` を `recordCommand` で記録する。
  終了後のコマンドは記録しない。
- ゲーム終了時に一度だけ `runReplay` を実行し、`gameDigest` を比較する。
  結果は `replayOk : Maybe Bool` としてスコア画面に出す。
- `gameDigest` は `Game.messages` を除く状態の FNV-1a 64-bit で、
  16 文字 hex。チェックポイント列や `messagesHash` はまだ持たない。
- ゲーム終了へ遷移した瞬間、`App.Update.persistRun` が戦績の追記と
  リプレイの保存を `Perform` で行う。書き込み失敗はゲーム終了処理を
  止めない。
- `seed` の JSON 表現は 16 文字 hex とし、`seedHex` を
  その唯一の整形関数にする。

## 5. セッションロックと復旧（実装済み）

`session.lock` は実行中プロセスの PID と起動時刻を JSON で持つ。

```json
{
  "pid": 12345,
  "startedAt": "2026-11-04T12:00:00Z"
}
```

- 起動時、セーブを読む前に `Persist.Save.acquireSessionLock` が
  `session.lock` を取得する。
- 既存ロックの PID が生きていれば（`kill(pid, 0)` が成功、または `EPERM`）、
  別インスタンスとみなして起動を拒否する。メッセージを出して終了する。
- PID が存在しない（`ESRCH`）、または JSON が壊れている場合は stale とみなし、
  ロックを置き換えて続行する。
- 正常終了時に `releaseSessionLock` が自分が持つロックだけを削除する。
  クラッシュ時は残るが、次回起動時に stale 判定される。
- `hostname` と `bootId` は持たない。PID 再利用の厳密な判定はせず、
  生存している PID は安全側で「実行中」とみなす。
- 読み込みの優先順位:
  1. `--seed` が指定されていれば、`save.json` / `autosave.json` を削除し、
     その seed で新しいランを開始する。
  2. `save.json` があれば読み込んで削除する。
  3. なければ `autosave.json` を読み込んで削除する。
  4. どちらもなければ、起動時刻（UTC ナノ秒）と PID から seed を生成して
     `newGame` を開始する。
- 復旧確認のダイアログはなく、起動時に自動で再開する。復旧したことは
  `SystemMsg` としてログの先頭に追加する。メッセージは `gameDigest` の
  対象外なので検証結果を変えない。
- 死亡・勝利時は `save.json` と `autosave.json` を削除する。
  ロックはプロセスが終了するまで保持する。

## 6. アトミック書き込み（セーブのみ実装済み）

1. 同じディレクトリに `<path>.tmp.<pid>` を作る。
2. JSON を書き、`fsync` する。
3. 既存ファイルを `.bak` に rename する（あれば）。
4. 一時ファイルを本体に rename する。
5. ディレクトリを `fsync` する。
6. 失敗時は一時ファイルを削除し、元のファイルを残す。

- 実装は `Persist.Save.atomicWrite`。手動セーブとオートセーブが使う。
- `settings.json`、`scores.jsonl`、リプレイファイルはこの手順を使わず、
  `writeFile` / `appendFile` で直接書き込む。
- セーブはターン境界（`step` の後、メッセージ確定後）にだけ行う。
- `autosave.json` は 10 ターンごと（`Game.turn mod 10 == 0` になる
  前進ターン）と終了時に書く。クラッシュで失うのは最大 9 ターン。
- セーブ中にクラッシュしても、`.bak` と rename の順序で旧ファイルが残る。
- 書き込みに失敗してもゲームは継続する。

## 7. 戦績 `scores.jsonl`

1 行 1 レコードの JSON Lines。ファイル上は古い順で、`appendFile` で追記する。
`loadScores` は読み込み後に反転し、`App.Model.scores` には新しい順で入れる。

```json
{"schema":"lambda-rogue.score.v1","seed":"0123456789abcdef","depth":7,"level":5,"exp":123,"gold":87,"turns":1240,"result":{"result":"dead","cause":{"kind":"monster","monster":"dragon"}}}
{"schema":"lambda-rogue.score.v1","seed":"fedcba9876543210","depth":1,"level":1,"exp":0,"gold":0,"turns":12,"result":{"result":"won"}}
```

- `schema` は `lambda-rogue.score.v1`。一致しない行は読み飛ばす。
- `seed` は 16 文字の小文字 hex。
- `depth`, `level`, `exp`, `gold`, `turns` は整数。
- `result` は `gameOverToJSON` と同じ形。
  - 勝利: `{"result":"won"}`
  - 死亡: `{"result":"dead","cause":...}`。`cause` は
    `{"kind":"monster","monster":"dragon"}`、`{"kind":"trap","trap":"bear"}`、
    `{"kind":"starved"}`、`{"kind":"drained"}`、
    `{"kind":"other","text":"..."}` のいずれか。
- 死因は `result.cause` に保存し、スコア画面の `Cause` / `死因` 列に表示する。
  勝利の行は死因を持たないため、その列は空になる。
- 書き込みは `appendScoreAt`（`appendFile`）。`fsync` とロックは未実装。
  同時書き込みは単一プロセス前提とする。
- 空行・空白だけの行・JSON として壊れた行・スキーマ不一致の行はスキップする。
  ファイル全体を失わない。警告 UI はまだない。
- `Score` は seed、深度、レベル、経験値、金、ターン、結果（勝利/死亡と
  死因）を持つ。名前、殺害数、プレイ日時、ゲームバージョンはまだ保存しない。
- スコア画面は `App.Model.scores` の新しい順に最大 8 件を表示する。
  並び替え UI は未実装。
- 起動時に `Main` が `loadScores` を呼ぶ。ゲーム終了時は
  `App.Update.persistRun` が `appendScore` と `saveReplay` をまとめて実行する。

## 8. 検証

### 8.1 セーブ（実装済み）

- `schema` / `gameVersion` / `kind` が既知。`gameVersion` は実行中の版と一致。
- `savedAt` が空でない。
- `seed` 16 文字、`rng` 32 文字、`explored` / `visible` 448 文字の
  小文字 hex。
- `turn >= 0`、`1 <= depth <= 26`。
- `levels` の `depth` が一意で、現在の `depth` を含む。
- `tiles` が 22x80、文字コードが既知。
- モンスター ID がラン全体で一意。`hp <= maxHp`、状態が既知、
  状態異常が重複せず `remaining >= 0`。
- アイテム ID が一意で、`count > 0`、`charges >= 0`。
- `inventory` の長さ <= 23、ID が重複せず、`items` に存在し、
  `location.kind = "pack"`。
- 装備中の ID が `inventory` に含まれる。
- `nextMonsterId` / `nextItemId` が既存の最大 ID より大きい。
- 床アイテムの `depth` が `levels` に存在し、モンスター所持の ID が
  実在する。
- `over` が `null` か、既知の結果・死因。
- `messages` が 200 件以下。
- `PersistTest` がスキーマ・種別・バージョン・`savedAt` の検証、
  JSON/テキスト往復、不正な ID カウンタ、存在しない所持品、
  ファイル往復、`.bak`、壊れたファイル、欠損ファイルを検証する。
- `appearances` の重複・網羅性はまだ検証しない。

### 8.2 リプレイ（実装済み）

- `schema` が `lambda-rogue.replay.v1` と一致する。
- `gameVersion` が実行中の版と一致する。
- `seed` が 16 文字の小文字 hex。
- `commands` が配列で、各要素の `type` と引数が 4.2 の表に一致する。
- 実行時に各コマンドの ID がその時点の `Game` に存在するか検証する。
  存在しなければ `step` は警告メッセージを出し、ゲーム状態を進めない。
- `PersistTest` が JSON/テキストの往復、全コマンド種別、未知スキーマ、
  バージョン不一致、未知コマンド、不正方向、ファイル往復、
  壊れたファイルの拒否を検証する。
- チェックポイントと `messagesHash` はまだない。

### 8.3 戦績（実装済み）

- `schema` が `lambda-rogue.score.v1` と一致する。
- `seed` が 16 文字の小文字 hex。
- 数値フィールドが整数で、`result` が 7 節の形に一致する。
- 壊れた行はスキップし、前後の有効な行を残す。
- `PersistTest` が勝利/死亡の往復、JSON Lines の追記と読み込み順、
  壊れた行のスキップ、欠損ファイル、未知スキーマを検証する。

## 9. 未決事項

- `messages` の保持件数は 200 件で固定した。セーブに含める範囲も同じ。
- `messagesHash` は未実装。リプレイ検証は `gameDigest` の状態比較だけ。
- リプレイの一覧・選択 UI、チェックポイント、シーク。
- スコアの名前・殺害数・日時・並び替え UI。
- スコアの同時書き込みが必要になったときのロック方式。
- `settings.json` のアトミック書き込み。
- `appearances` / `knownKinds` の重複・網羅性検証。
- PID 再利用を厳密に扱うための `bootId` / プロセス開始時刻の記録。
- セーブの暗号化・改ざん検知は非目標。ローカルゲームの利便性を優先する。
