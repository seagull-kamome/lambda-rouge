# lambda-rogue

[English](README.md) | **日本語**

Rogue 5.4.4 のゲームプレイを、Idris 2 と rc2 でクリーンルーム実装した
ターミナルローグライクです。ゲームの真実は純粋な Core に置き、表示・入力・
演出だけを [termui](https://github.com/stefan-hoeck/idris2-termui) で現代化しています。

- 古典的な 26 階層、アミュレット取得と帰還、パーマデス。
- Rogue 5.4.4 の公開データ表に基づくモンスター・アイテム・確率。
- 決定論的 RNG とリプレイ。同じ seed と同じコマンド列は同じ結果になります。
- 80x24 のクラシック表示と、120x40 以上のワイド表示。
- マウス、コマンドパレット、テーマ、ヘルプ、戦績、セーブ/オートセーブ。
- 英語・日本語のメッセージカタログ。`--lang`、`settings.json`、`Ctrl-P` の
  パレットから切り替えられます。全角文字を含む列も端末セル幅で揃えます。
- 戦績には死因を記録し、スコア画面に表示します。
- TrueColor 非対応端末では自動で ANSI テーマへ、`NO_COLOR` では
  モノクロテーマへフォールバックします。
- アニメーション速度の設定と、`NO_MOTION` / `--no-animation` による自動無効化。
- キーボードだけで全操作が完結します。

> 本プロジェクトは Rogue 5.4.4 のソースコードをコピーしていません。
> 公開仕様・データ表・観測した挙動から再実装しています。詳細は
> [`doc/rogue-reference.md`](doc/rogue-reference.md) を参照してください。

## 必要環境

- Idris 2 0.8.0 系と rc2 バックエンド（`idris2-rc2`）
- `rc2base` 0.1.0 と `termui` 0.1.0 が Idris 2 にインストール済みであること
- C コンパイラ（gcc または clang）
- PTY スモークテストを使う場合は `script(1)`

`idris2-rc2` が `PATH` にない場合は、次のように指定できます。

```sh
export IDRIS2="$HOME/.idris2/bin/idris2-rc2"
```

## ビルドと実行

```sh
# 本体をビルド
idris2-rc2 --codegen rc2 --build lambda-rogue.ipkg
./build/exec/lambda-rogue
```

Clang 19 でビルドする場合は、rc2 が生成する比較式への警告を抑えるため
次を設定してください（`verify.sh` は自動で設定します）。

```sh
export IDRIS2_CFLAGS="-Wno-parentheses-equality"
```

## 検証

```sh
./verify.sh
```

クリーンビルド、全テスト（1003 チェック）、PTY 上での起動・描画・終了を
順に実行します。テストデータは `build/verify-data` に隔離され、
実際のセーブ・戦績・設定には触れません。

## 起動オプション

```sh
./build/exec/lambda-rogue --seed 0123456789abcdef --lang ja --theme amber
```

- `--seed <16 桁小文字 hex>`: 指定した seed で新しいランを開始します。
  既存の `save.json` / `autosave.json` は削除されます。
- `--lang en|ja`: この起動の表示言語を指定します。`settings.json` の
  `language` より優先されます。指定しない場合は設定値、設定がなければ
  英語を使います。起動中は `Ctrl-P` の `Switch language` / `言語を切り替え`
  でも切り替えられ、選択は `settings.json` に保存されます。
- `--theme <id>`: この起動のテーマを指定します。`settings.json` の
  `theme` より優先されます。ID は `classic-cga`, `modern-dark`, `amber`,
  `green-phosphor`, `high-contrast`, `colorblind-safe`, `monochrome` です。
- `--no-color`: 色を無効にし、モノクロテーマで起動します。
  環境変数 `NO_COLOR` でも同じ動作になります。
- `--no-animation`: アニメーションを無効にします。環境変数 `NO_MOTION`
  でも同じ動作になります。設定で有効でも、この起動だけ無効になります。
- 指定しない場合は起動時刻（UTC ナノ秒）と PID から seed を生成します。
  前回のセーブがあれば、その続きから再開します。
- seed は `Ctrl-S` のシード共有画面で確認・コピーできます。
- 表示言語・テーマ・アニメーションはゲーム状態・RNG・リプレイ・
  `gameDigest` に影響しません。

`settings.json` の例:

```json
{
  "schema": "lambda-rogue.settings.v1",
  "theme": "classic-cga",
  "animation": true,
  "animationSpeed": "normal",
  "language": "ja",
  "keys": {}
}
```

## 主なキー

| キー | 操作 |
| --- | --- |
| `h` `j` `k` `l` / 矢印 | 西・南・北・東へ移動（モンスターへは攻撃） |
| `y` `u` `b` `n` | 斜め移動 |
| `.` / `5` | 1 ターン待機 |
| `s` | 周囲を探索してトラップと隠し扉を探す |
| `,` | 足元のアイテムを拾う |
| `>` / `<` | 階段を下りる / 上りる |
| `i` | インベントリ |
| `q` / `r` / `e` | ポーションを飲む / 巻物を読む / 食料を食べる |
| `w` / `W` | 武器を装備 / 防具を着る |
| `P` / `R` / `T` | 指輪をはめる / 外す |
| `d` / `t` / `z` | 落とす / 投げる / 杖を振る |
| `?` / `F1` | ヘルプ |
| `Ctrl-P` | コマンドパレット |
| `F2` / `F3` / `F4` | ログフィルタ / テーマ / アニメーション |
| `F5` | リプレイ一覧 |
| `S` / `Ctrl-S` | 戦績 / シード共有 |
| `Q` / `Ctrl-C` | 終了 |

- 移動先にモンスターがいれば攻撃になります。
- インベントリでは行を選んで Enter、マウスのクリックやダブルクリックも使えます。
- リプレイ一覧は `F5` またはパレットから開き、上下キーで選んで Enter で再生します。
- 再生中は Space で一時停止、`.`/Enter で 1 コマンド、`+`/`-` で速度、
  `Left`/`Right` で 10 コマンドずつシーク、`Home`/`End` で先頭/末尾へ移動、
  `R` で最初から、Esc/q で閉じます。
- キー割り当ては `settings.json` で変更できます。設定画面は未実装です。
- 通常プレイ中の Esc は終了しません。終了は `Q` または `Ctrl-C` です。

## セーブとデータ

データは `$XDG_DATA_HOME/lambda-rogue`、未設定時は
`$HOME/.local/share/lambda-rogue` に保存されます。

| ファイル | 内容 |
| --- | --- |
| `save.json` | パレットの「Save and quit」で保存した手動セーブ |
| `autosave.json` | 10 前進ターンごとのオートセーブ |
| `scores.jsonl` | 終了したランの戦績（死因を含む） |
| `replays/*.json` | 終了したランのリプレイ（seed + コマンド列） |
| `settings.json` | テーマ、アニメーション、言語、キー割り当て |
| `session.lock` | 二重起動を防ぐセッションロック |

- 起動時は `save.json` → `autosave.json` の順に自動再開し、読んだファイルを
  削除します。
- 死亡・勝利時はセーブを削除し、戦績とリプレイを保存します。
- セーブの復元で死亡を回避することはできません。

## アクセシビリティ

- `monochrome` テーマは色を使わず、太字・下線・反転だけで情報を区別します。
- `NO_COLOR` / `--no-color` で色を完全に無効化できます。
- `NO_MOTION` / `--no-animation` でアニメーションを無効化できます。
- 高コントラストと色覚多様性テーマは、色以外の手掛かり（下線・記号）も
  併用します。
- ゲームのグリフは ASCII のみで、キーボードだけで全機能に到達できます。

## 忠実性と既知の相違

Rogue 5.4.4 との差分は [`doc/rogue-reference.md`](doc/rogue-reference.md)
17 章にまとめています。主なものは次の通りです。

- 武器の命中・ダメージ強化値は単一の `enchant` で表します。
- モンスターの出現は深度帯からの等確率で、原本の表引きとは異なります。
- 群れ、モンスターの所持率表、弓・投擲の遠距離攻撃、orc の強欲 AI、
  xeroc の物体擬態、ドラゴンの火炎反射は未実装です。
- 隠し扉は閉じたドアの一部から生成し、探索すると閉じたドアとして現れます。
  原本の正確な生成確率は未確認です。
- 一部のポーション効果時間、巻物の対象範囲、杖の副効果は簡略化しています。
- 飢餓の失神・`-850` 死亡、浮遊のトラップ無効は未実装です。

M5 スライス 1 で、探索、searching の指輪、healing / extra healing の
ダイスと最大 HP 増加、magic missile の 1d4 を 5.4.4 に合わせました。
M5 スライス 2 では、ゲームログ・ヘルプ・パレット・ステータス・プロンプト・
戦績・エラー文言を英語・日本語のカタログ経由に統一しました。旧セーブの
メッセージは保存済みの英語テキストへフォールバックします。パレットの
言語切替、全角文字を含む列の端末セル幅調整、スコアの死因列も追加しました。
M5 スライス 3 では、テーマの自動フォールバックと `--theme`、
アニメーション速度と低減モード、リプレイ一覧・シーク、アクセシビリティ
向上を追加しました。M5 スライス 4 では隠し扉を追加しました。閉じたドアの
一部が壁に見える隠し扉になり、探索すると閉じたドアとして見つかります。
searching の指輪の無料探索でも発見できます。

## 今後の優先度

1. **残りの忠実性**: 群れ、遠距離攻撃、AI、巻物・杖・トラップの
   細部を `doc/rogue-reference.md` 17 章に沿って解消します。
2. **リリース**: ファズ、性能、パッケージングを仕上げます。

## ドキュメント

| ファイル | 内容 |
| --- | --- |
| [`doc/design.md`](doc/design.md) | 全体設計、M1〜M5 のロードマップ、決定事項ログ |
| [`doc/core-api.md`](doc/core-api.md) | Core の型、`step` 契約、不変条件、実装ノート |
| [`doc/rogue-reference.md`](doc/rogue-reference.md) | Rogue 5.4.4 のデータ表と既知の相違 |
| [`doc/persistence.md`](doc/persistence.md) | セーブ、リプレイ、戦績、設定のスキーマ |
| [`doc/m1-measurements.md`](doc/m1-measurements.md) | 描画・step・生成の計測記録 |

## ライセンス

lambda-rogue 自体は **BSD 3-Clause License** です。全文は
[`LICENSE`](LICENSE) を参照してください。

Rogue 5.4.4 は BSD 3-clause 系のライセンスで公開されています
（Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold, Glenn Wichman）。
モンスター名、アイテム名、古典的メッセージなど原本由来の素材の再配布条件は、
`doc/rogue-reference.md` 18 章に記載した原本のライセンスに従います。
