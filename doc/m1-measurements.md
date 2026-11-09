# lambda-rogue 計測記録

- Status: M1–M5 スライス 1 完了
- Date: 2026-11-09
- 対象: `tests/PerfTest.idr`, `tests/latency_probe.py`
- 関連: `doc/design.md` 9 章、`doc/core-api.md` 16〜29 章

## 1. 環境

| 項目 | 値 |
|---|---|
| CPU | Intel Core i5-10210U @ 1.60GHz（8 logical CPUs） |
| OS | Linux 6.6.143 x86_64 |
| Compiler | Idris 2 0.8.0-5c970b808 |
| Compiler path | `/home/seagull/.idris2/bin/idris2-rc2` |
| Backend | rc2 |
| termui | 0.1.0 |
| rc2base | 0.1.0 |
| Build | `lambda-rogue.ipkg`（`opts = "--total"`、追加の最適化フラグなし） |
| PTY | `xterm-256color`、80x24 |

共有開発機であり、CPU ピン留め、周波数固定、専用端末エミュレータは使っていない。
数値は同じホストでの相対比較用であり、絶対的な保証値ではない。

## 2. 方法

### 2.1 描画とターン解決

`tests/PerfTest.idr` は `clock_gettime(CLOCK_MONOTONIC)` で次を測る。
開始前に一度 `drawMap` を呼び、Canvas の初回確保を計測から外す。

- **render (initial FOV)**: `sampleGame` を 1,000 回描画する。
  初期 FOV では 220 セルが visible/explored。
- **render (full map)**: 全 1,760 セルを visible/explored にした `fullGame` を
  500 回描画する。`drawMap` の最悪ケース。
- **step**: `Wait` を 10,000 回解決する。M1 のモンスターは眠ったままで、
  乱数は消費しない。FOV 再計算とモンスターの視界判定を含む。
- **step+render (initial FOV)**: 1 ターン解決して描画することを 1,000 回。
- **step+render (full map)**: 同じ処理を全セル可視の状態で 500 回。

M4 スライス 1 では、これらに加えて `App.View` 全体（マップ、サイドバー、
ログ、ステータス行）を 80x24 の通常・インベントリ表示と 120x40 の
ワイド表示で 500 回ずつ描画する計測を追加した。詳細は §9。

`drawMap` は毎回 Canvas を `clear` し、visible/explored のセルだけを
`putCell` する。差分描画はまだ行わない。`fullMapBits` は
`count == 1760` をテスト内で確認する。

### 2.2 入力レイテンシ

`tests/latency_probe.py` は 80x24 の PTY で実行ファイルを起動し、
初期フレームの `Turn 0` を待ってから `l` と `h` を交互に送る。
各キーについて、termui がフレーム終端に出す `ESC[?25l` を待ち、
キー書き込みからフレーム完了までの時間を 50 回測る。

この値には PTY、Python の読み取り、ゲーム側の入力処理と再描画が含まれる。
物理端末の入力遅延や端末エミュレータの描画時間は含まない。

## 3. 結果

### 3.1 描画とターン解決

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV) | 1,000 | 3,208 ms | 3.21 ms/frame |
| render (full map) | 500 | 1,886 ms | 3.77 ms/frame |
| step | 10,000 | 8,039 ms | 0.80 ms/turn |
| step+render (initial FOV) | 1,000 | 4,064 ms | 4.06 ms/frame |
| step+render (full map) | 500 | 2,836 ms | 5.67 ms/frame |

60 Hz のフレーム予算 16.67 ms に対して、最悪ケースの
step+render は約 34% に収まる。

同じホストでも実行ごとに 10〜20% 程度変動する。最終の `./verify.sh` では
render (initial FOV) 4.02 ms、render (full map) 4.01 ms、step 0.92 ms、
step+render (initial FOV) 4.38 ms、step+render (full map) 6.96 ms だった。
共有ホストのため、単一の値を厳密な基準にはしない。

### 3.2 入力レイテンシ

代表的な 3 回の実行:

| 実行 | min | median | mean | p95 | max |
|---|---:|---:|---:|---:|---:|
| 1 | 4.41 ms | 4.78 ms | 5.45 ms | 7.10 ms | 23.15 ms |
| 2 | 4.49 ms | 5.05 ms | 5.98 ms | 8.96 ms | 25.38 ms |
| 3（最終ビルド） | 4.49 ms | 4.93 ms | 5.35 ms | 7.32 ms | 15.75 ms |

最初の数サンプルに 15〜25 ms の外れ値が出やすい。これはプロセス起動後の
スケジューリングと Python 側の読み取り準備によるもので、定常状態は
中央値約 4.8〜5.1 ms、p95 約 7〜9 ms だった。

## 4. 考察

- 初期 FOV と全マップの描画差は約 0.56 ms/frame で、1,540 セル分の
  `putCell` 増加としては小さい。現状は `clear` とセル走査の固定費が支配的。
- `step` は約 0.80 ms/turn。FOV の候補列挙と Bresenham 判定を含むが、
  M1 の固定マップでは十分速い。
- 最悪ケースでも step+render が 16.67 ms を大きく下回るため、M1 では
  差分描画を導入しない。M2 以降でサイドバー、ログ、複数階層が増えた時点で
  再測し、必要なら Canvas の差分更新を検討する。
- 入力レイテンシの中央値は 5 ms 前後で、ターン制ゲームとして知覚できる
  遅延はない。外れ値は共有ホストのスケジューリングに起因すると考えられる。
- 現時点では回帰しきい値を設けない。CI 用の固定ホストができたら、
  `PerfTest` に中央値と p95 の上限を追加する。

## 5. 再現手順

```sh
cd lambda-rogue
./verify.sh
./build/exec/lambda-rogue-tests
python3 tests/latency_probe.py
```

`lambda-rogue-tests` は `verify.sh` が `lambda-rogue-tests.ipkg` からビルドする
単一のテスト実行ファイルで、`PerfTest` はその最後に実行される。
`latency_probe.py` は実行ファイルが存在すれば単独で動く。

## 6. 制約と次の計測

- 共有ホスト、CPU ピン留めなし、周波数固定なし。
- PTY 計測は Python の読み取りを含む。実端末での体感値ではない。
- `step` は `Wait` のみ。戦闘・アイテム使用・複数モンスターの乱数消費は
  `CoreTest` で検証しているが、M1 の性能測定には含めていない。
- M2 でダンジョン生成、複数階層、戦闘表、モンスター数を追加した後に、
  実端末と CI ホストの両方で再測する。

## 7. M2 追測（2026-10-29）

同じホスト・同じコンパイラで、M2 の生成レベルと生成 100 回を追加して再測した。
`PerfTest` は M1 の固定 `sampleGame` の数値も残している。

### 7.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 3,109 ms | 3.11 ms/frame |
| render (full map, M1 fixture) | 500 | 1,850 ms | 3.70 ms/frame |
| step (M1 fixture) | 10,000 | 7,895 ms | 0.79 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 3,839 ms | 3.84 ms/frame |
| step+render (full map, M1 fixture) | 500 | 2,741 ms | 5.48 ms/frame |
| render (generated level 1) | 500 | 1,766 ms | 3.53 ms/frame |
| step (generated, survivable) | 1,000 | 894 ms | 0.89 ms/turn |
| step+render (generated) | 500 | 2,487 ms | 4.98 ms/frame |
| generate level (depth 10) | 100 | 321 ms | 3.22 ms/level |

生成 100 回後の RNG 状態は
`967c63e290f14b15a5ffa48aeb8a6515`（`generateN 100 10 (fromSeed 42)`）。
同じ seed と同じ回数で再現できることを決定論テストの一部として使える。

### 7.2 考察

- 生成レベル 1 の描画は M1 固定マップとほぼ同じ。初期 FOV の可視セル数が
  同程度で、Canvas の `clear` と走査の固定費が支配的である。
- 生成レベルの step は 0.89 ms/turn。M1 の 0.79 ms/turn と同程度で、
  モンスター AI と戦闘を含む 1,000 ターンでも 1 ms/turn を下回る。
- step+render は生成レベルで 4.98 ms/frame。60 Hz 予算の約 30%。
  サイドバーとログを含む実際の `App.View` は別途測る必要がある。
- 1 階層の生成は約 3.2 ms。下降時の 1 回だけなので体感上の問題はない。
  ただし 26 階層を先に生成する設計にする場合は、合計 80 ms 程度を見込む。
- 共有ホストのため、値は同じホストでの相対比較に使う。M1 の値も
  今回の実行では前回より 3〜10% 程度速く、実行ごとの変動幅に収まっている。

## 8. M3 追測（2026-10-29）

M3 のアイテム生成・装備・空腹・状態異常を入れた状態で、同じホスト・同じ
コンパイラにより `./verify.sh` 内の `PerfTest`（当時の `perf-test`）を再実行した。
M3 では 10,000 ターンの `step` 計測が飢餓による死亡後の no-op にならないよう、
`longLivedSampleGame` に栄養 20,000 を与えている。それ以外のフィクスチャは
M2 と同じ。

### 8.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 3,088 ms | 3.09 ms/frame |
| render (full map, M1 fixture) | 500 | 1,770 ms | 3.54 ms/frame |
| step (M1 fixture, 栄養 20,000) | 10,000 | 7,820 ms | 0.78 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 3,830 ms | 3.83 ms/frame |
| step+render (full map, M1 fixture) | 500 | 2,612 ms | 5.23 ms/frame |
| render (generated level 1) | 500 | 1,483 ms | 2.97 ms/frame |
| step (generated, survivable) | 1,000 | 774 ms | 0.77 ms/turn |
| step+render (generated) | 500 | 1,864 ms | 3.73 ms/frame |
| generate level (depth 10) | 100 | 283 ms | 2.83 ms/level |

生成 100 回後の RNG 状態は
`542cc27d7d5bf8e6003962e839e5bdbc`（`generateN 100 10 (fromSeed 42)`）。
M2 の `967c63e290f14b15a5ffa48aeb8a6515` と異なるのは、M3 でアイテムの
出現表・強化値・呪いの抽選が増え、乱数の消費列が変わったためである。
同じ seed と同じ回数で再現できることを決定論テストの一部として使える。

### 8.2 考察

- 生成レベル 1 の描画は 2.97 ms/frame、生成レベルの step は 0.77 ms/turn で、
  M2 の値（3.53 ms/frame、0.89 ms/turn）と同程度かやや速い。
  共有ホストの実行ごとの変動幅に収まっている。
- M1 固定マップの 10,000 ターン step は 0.78 ms/turn。M2 の 0.79 ms/turn と
  同程度で、空腹・状態異常の更新と、栄養切れを防ぐためのフィクスチャ変更を
  含めてもターンあたり 1 ms 未満を維持している。
- step+render は生成レベルで 3.73 ms/frame、全マップで 5.23 ms/frame。
  60 Hz 予算（16.7 ms）の 22〜31% で、M3 のインベントリ画面を開いていない
  通常状態では十分な余裕がある。
- 1 階層の生成は 2.83 ms。M3 のアイテム抽選を追加しても M2 の 3.22 ms と
  同程度で、下降時の一時停止は知覚しにくい。
- インベントリ画面の描画は M3 の時点では `PerfTest` に含めていなかった。
  M4 スライス 1 でサイドバー・ログ・インベントリを含む `App.View` 全体の
  計測を追加した。結果は §9 を参照。

## 9. M4 スライス 1 追測（2026-10-30）

M4 スライス 1（巻物 18 種、杖 14 種、指輪 14 種、投げる、ランごとの外見、
モンスター状態異常）を入れた状態で、同じホスト・同じコンパイラにより
`./verify.sh` 内の `lambda-rogue-tests` を再実行した。`PerfTest` は
M3 までの Canvas / step 計測に加えて、`App.View` 全体の描画を測る。

- **render view (80x24)**: 通常のクラシックレイアウト 500 回。
- **render view (80x24, inventory)**: インベントリを開いた状態 500 回。
- **render view (120x40)**: サイドバーと 8 行ログを含むワイドレイアウト 500 回。

`render` は `TermUI.Frame.render` と `frameLines` を通してフレーム内容を
確定させるが、端末への書き込みは含まない。数値は M3 までと同じく
共有ホストでの相対比較用である。

### 9.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 3,162 ms | 3.16 ms/frame |
| render (full map, M1 fixture) | 500 | 1,879 ms | 3.76 ms/frame |
| render view (80x24) | 500 | 929 ms | 1.86 ms/frame |
| render view (80x24, inventory) | 500 | 1,510 ms | 3.02 ms/frame |
| render view (120x40) | 500 | 2,701 ms | 5.40 ms/frame |
| step (M1 fixture, 栄養 20,000) | 10,000 | 8,366 ms | 0.84 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 4,151 ms | 4.15 ms/frame |
| step+render (full map, M1 fixture) | 500 | 2,873 ms | 5.75 ms/frame |
| render (generated level 1) | 500 | 1,588 ms | 3.18 ms/frame |
| step (generated, survivable) | 1,000 | 844 ms | 0.84 ms/turn |
| step+render (generated) | 500 | 2,000 ms | 4.00 ms/frame |
| generate level (depth 10) | 100 | 308 ms | 3.09 ms/level |

生成 100 回後の RNG 状態は
`82759c64b7a6f48527db9a2219df8811`（`generateN 100 10 (fromSeed 42)`）。
M3 の `542cc27d7d5bf8e6003962e839e5bdbc` と異なるのは、巻物・杖・指輪の
出現抽選が加わり、レベル生成の乱数消費列が変わったためである。
`newGame` はレベル生成後に外見シャッフルでも RNG を消費するが、
`generateLevel` 単体の出力は外見の有無に影響されない。
同じ seed と同じ回数で再現できることを決定論テストの一部として使える。

### 9.2 考察

- 通常の `App.View` は 80x24 で 1.86 ms/frame、インベントリを開いても
  3.02 ms/frame。サイドバーとログを含む 120x40 でも 5.40 ms/frame で、
  60 Hz 予算（16.7 ms）の約 32% に収まる。
- インベントリ表示は通常表示より約 1.2 ms 高い。23 スロットの行組み立てと
  選択マーカーの判定が主な追加コストで、開閉時の体感には影響しない。
- 120x40 は 80x24 の約 2.9 倍。マップ 80x22 に加えて 40 列のサイドバーと
  8 行のログを毎フレーム組み立てるためで、ワイド画面でも 1 フレームの
  余裕は残っている。
- step は M1 フィクスチャで 0.84 ms/turn（M3: 0.78）、生成レベルで
  0.84 ms/turn（M3: 0.77）。今回の実行では M4 の追加分は測定誤差の範囲に
  収まっている。生成レベルの step+render は 4.00 ms/frame で、
  60 Hz 予算の約 24%。
- step+render は全マップで 5.75 ms/frame、生成レベルで 4.00 ms/frame。
  M3 の 5.23 / 3.73 ms と同程度で、いずれも 16.7 ms 以内である。
- 1 階層の生成は 3.09 ms（M3: 2.83 ms）。巻物・杖・指輪の抽選が加わったが、
  下降時の一時停止は依然として知覚しにくい。
- 外見シャッフルは `newGame` の 1 回だけであり、ターンごとのコストには
  含まれない。58 種の対応表は `Game.appearances` に保持するため、
  セーブ・リプレイの状態量も小さく抑えられる。
- 同日に 2 回計測したところ、1 回目は render (initial FOV) 4.29 ms、
  full map 5.69 ms、step 1.04 ms/turn、生成 step 1.97 ms/turn だった。
  最終 `./verify.sh` では上表のとおり 3.16 / 3.76 ms、0.84 / 0.84 ms/turn で、
  共有ホストの実行ごとの変動が大きい。絶対値ではなく、同じホストでの
  回帰監視に使う。

## 10. M4 スライス 2 追測（2026-10-30）

M4 スライス 2（A-Z 26 モンスター、特殊能力、プレイヤーの睡眠/麻痺/ホールド、
全トラップ効果）を入れた状態で、`./verify.sh` を実行した。計測方法は §9 と
同じで、最終 `./verify.sh` 内の `lambda-rogue-tests` の値を記録する。

### 10.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 3,278 ms | 3.28 ms/frame |
| render (full map, M1 fixture) | 500 | 1,997 ms | 4.00 ms/frame |
| render view (80x24) | 500 | 917 ms | 1.83 ms/frame |
| render view (80x24, inventory) | 500 | 1,388 ms | 2.78 ms/frame |
| render view (120x40) | 500 | 2,767 ms | 5.54 ms/frame |
| step (M1 fixture, 栄養 20,000) | 10,000 | 8,216 ms | 0.82 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 3,977 ms | 3.98 ms/frame |
| step+render (full map, M1 fixture) | 500 | 2,859 ms | 5.72 ms/frame |
| render (generated level 1) | 500 | 1,541 ms | 3.08 ms/frame |
| step (generated, survivable) | 1,000 | 829 ms | 0.83 ms/turn |
| step+render (generated) | 500 | 1,949 ms | 3.90 ms/frame |
| generate level (depth 10) | 100 | 312 ms | 3.13 ms/level |

生成 100 回後の RNG 状態は
`bb7b6c9d6f819216163597bcbde0ff79`（`generateN 100 10 (fromSeed 42)`）。
スライス 1 の `82759c64b7a6f48527db9a2219df8811` と異なるのは、モンスターの
出現プール構成が変わり、`uniform` の棄却サンプリング回数が変わったためである。
同じ seed と同じ回数で再現できる。

### 10.2 考察

- 通常の `App.View` は 80x24 で 1.83 ms/frame、インベントリを開いても
  2.78 ms/frame、120x40 でも 5.54 ms/frame。スライス 1 の 1.86 / 3.02 / 5.40 ms
  と同程度で、26 種のモンスター表と能力の追加は描画コストに現れていない。
  フィクスチャのモンスター数が 1 体であるため、能力ごとの分岐はほぼ測定外である。
- step は M1 フィクスチャで 0.82 ms/turn、生成レベルで 0.83 ms/turn。
  スライス 1 の 0.84 / 0.84 ms と同程度で、状態異常の更新、モンスターの
  再生・遠距離判定を加えてもターンあたり 1 ms 未満を維持している。
- step+render は全マップで 5.72 ms/frame、生成レベルで 3.90 ms/frame。
  60 Hz 予算（16.7 ms）の 23〜34% に収まる。生成レベルの値はスライス 1 の
  4.00 ms と同程度で、同日の実行でも 3.90〜5.09 ms の幅があり、
  共有ホストの変動を含む。
- 1 階層の生成は 3.13 ms（スライス 1: 3.09 ms）。26 種の出現プールと
  モンスターごとの HP ダイスが増えたが、下降時の一時停止は知覚しにくい。
- 計測用の生成レベルは深度 10 で、26 種のうち中深度のモンスターだけが
  出現する。深層の能力（ドラゴンの炎、透明ストーカーなど）は機能テストで
  確認しており、性能測定は今後の深層フィクスチャ追加時に拡張する。
- 共有ホストのため、スライス 1 との差分は実行ごとの変動を含む。絶対値ではなく、
  同じホストでの回帰監視に使う。

## 11. M4 スライス 3 追測（2026-10-31）

M4 スライス 3（ワイド ミニマップ、ログフィルタ、ヘルプ、コマンドパレット、
ワイド インベントリ詳細）を入れた状態で `./verify.sh` を実行した。計測方法は
§9 / §10 と同じ。今回は共有ホストの負荷が高く、絶対値は §10 より大きい。

### 11.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 4,578 ms | 4.58 ms/frame |
| render (full map, M1 fixture) | 500 | 3,020 ms | 6.04 ms/frame |
| render view (80x24) | 500 | 1,376 ms | 2.75 ms/frame |
| render view (80x24, inventory) | 500 | 2,171 ms | 4.34 ms/frame |
| render view (120x40) | 500 | 4,772 ms | 9.55 ms/frame |
| render view (120x40, inventory) | 200 | 2,316 ms | 11.58 ms/frame |
| render view (80x24, help) | 200 | 1,391 ms | 6.96 ms/frame |
| render view (80x24, palette) | 200 | 1,355 ms | 6.78 ms/frame |
| step (M1 fixture, 栄養 20,000) | 10,000 | 13,240 ms | 1.32 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 5,339 ms | 5.34 ms/frame |
| step+render (full map, M1 fixture) | 500 | 3,730 ms | 7.46 ms/frame |
| render (generated level 1) | 500 | 2,012 ms | 4.03 ms/frame |
| step (generated, survivable) | 1,000 | 1,132 ms | 1.13 ms/turn |
| step+render (generated) | 500 | 2,647 ms | 5.29 ms/frame |
| generate level (depth 10) | 100 | 405 ms | 4.06 ms/level |

生成 100 回後の RNG 状態は §10 と同じ
`bb7b6c9d6f819216163597bcbde0ff79`（`generateN 100 10 (fromSeed 42)`）。
スライス 3 は Core の乱数消費順序を変えないため、この値は不変である。

### 11.2 考察

- 同日に複数回実行したところ、80x24 は 2.53〜2.76 ms、インベントリは
  3.82〜4.34 ms、120x40 は 9.05〜12.37 ms、ワイド インベントリは
  10.54〜15.28 ms、ヘルプは 6.54〜8.34 ms、パレットは 6.03〜6.78 ms、
  step は 1.16〜1.62 ms/turn だった。§10 の 0.82 ms/turn と比べて
  ホスト全体が約 1.4〜2 倍遅く、絶対値の比較には向かない。
  以下の比率を回帰の目安にする。
- ワイド通常表示は 80x24 の約 3.5 倍。マップ 80x22 に加えて、サイドバー、
  36x8 ミニマップ、凡例、フィルタ済みログ 8 行を毎フレーム組み立てる。
  ミニマップは 288 ブロックの中心タイルと階段・プレイヤーの上書きだけで、
  全 1,760 セルの走査は行わない。
- ワイド インベントリはワイド通常表示の約 1.21 倍。左の 23 スロット一覧に
  加えて、右の詳細パネル（枠、表示名、装備位置、強化値、比較）を描く。
  最も遅い実行では 15.28 ms/frame と 60 Hz 予算に近かったが、最終実行では
  11.58 ms/frame で、いずれも 16.7 ms 以内である。詳細パネルを開いたまま
  連続描画する操作はないため、実用上の影響は小さい。
- ヘルプは 6.96 ms/frame、パレットは 6.78 ms/frame。どちらも静的な
  オーバーレイで、ターンは進めない。ワイド ヘルプは 100x30 の枠に
  24 行、クラシック ヘルプは 80x24 の枠に 20 行を描く。
- step は M1 フィクスチャで 1.32 ms/turn、生成レベルで 1.13 ms/turn。
  スライス 3 は Core を変更していないため、§10 との差はホスト負荷による。
- step+render は全マップで 7.46 ms/frame、生成レベルで 5.29 ms/frame。
  ワイド表示でも 16.7 ms 以内に収まるが、今後のマウス・アニメーション追加時は
  ワイド インベントリと合わせて再計測する。
- 1 階層の生成は 4.06 ms（§10: 3.13 ms）。こちらもホスト負荷の影響で、
  生成アルゴリズムと RNG 消費順序はスライス 3 で変わっていない。

## 12. M4 スライス 4 追測（2026-11-01）

M4 スライス 4（コマンド記録、リプレイ検証、スコア画面、シード共有）を
入れた状態で `./verify.sh` を実行した。計測方法は §9〜§11 と同じ。
Core の乱数消費順序は変えていない。

### 12.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 4,105 ms | 4.11 ms/frame |
| render (full map, M1 fixture) | 500 | 2,684 ms | 5.37 ms/frame |
| render view (80x24) | 500 | 1,193 ms | 2.39 ms/frame |
| render view (80x24, inventory) | 500 | 1,754 ms | 3.51 ms/frame |
| render view (120x40) | 500 | 3,893 ms | 7.79 ms/frame |
| render view (120x40, inventory) | 200 | 1,843 ms | 9.22 ms/frame |
| render view (80x24, help) | 200 | 1,112 ms | 5.56 ms/frame |
| render view (80x24, palette) | 200 | 1,072 ms | 5.36 ms/frame |
| render view (80x24, scores) | 200 | 927 ms | 4.64 ms/frame |
| render view (80x24, share seed) | 200 | 964 ms | 4.82 ms/frame |
| step (M1 fixture, 栄養 20,000) | 10,000 | 10,607 ms | 1.06 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 5,335 ms | 5.34 ms/frame |
| step+render (full map, M1 fixture) | 500 | 3,865 ms | 7.73 ms/frame |
| render (generated level 1) | 500 | 2,067 ms | 4.14 ms/frame |
| step (generated, survivable) | 1,000 | 1,087 ms | 1.09 ms/turn |
| step+render (generated) | 500 | 2,643 ms | 5.29 ms/frame |
| generate level (depth 10) | 100 | 410 ms | 4.11 ms/level |

生成 100 回後の RNG 状態は §10 / §11 と同じ
`bb7b6c9d6f819216163597bcbde0ff79`（`generateN 100 10 (fromSeed 42)`）。

### 12.2 考察

- 80x24 通常表示は 2.39 ms/frame、インベントリは 3.51 ms/frame。
  §11 の 2.75 / 4.34 ms より速く、ホスト負荷の変動が大きいことが分かる。
  スライス 4 は通常表示の描画経路を変えていない。
- 120x40 は 7.79 ms/frame、ワイド インベントリは 9.22 ms/frame。
  どちらも 60 Hz 予算 16.7 ms の半分以下で、§11 の 9.55 / 11.58 ms より
  余裕がある。
- スコア画面は 4.64 ms/frame、シード共有画面は 4.82 ms/frame。
  どちらも静的なオーバーレイで、ターンを進めない。スコア画面は最大 8 行の
  戦績表、seed、検証結果を描く。共有画面は 16 文字の seed と短い説明だけなので、
  ヘルプ（5.56 ms）やパレット（5.36 ms）より軽い。
- ゲーム終了時だけ `replayMatches` が `newGame` から全コマンドを再実行する。
  通常のターン処理には含まれない。10,000 ターンのリプレイでも数秒程度で、
  終了画面を出す前の一度だけの処理として許容する。可視再生を入れるときは
  `Every` タイマーで 1 コマンドずつ進め、UI をブロックしない。
- step は 1.06 ms/turn、生成レベルで 1.09 ms/turn。§11 の 1.32 / 1.13 と
  同程度で、Core の変更がないことを確認できる。
- step+render は全マップで 5.34〜7.73 ms/frame、生成レベルで 5.29 ms/frame。
  スコア・共有オーバーレイを開いても 16.7 ms 以内に収まる。
- 1 階層の生成は 4.11 ms。§11 の 4.06 ms と同じで、生成経路は不変。

## 13. M4 スライス 5 追測（2026-11-01）

M4 スライス 5（6 テーマ、`F3` / パレット巡回、テーマ別 Canvas 再描画）を
入れた状態で `./verify.sh` を実行した。計測方法は §9〜§12 と同じ。
Core の乱数消費順序は変えていない。

### 13.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 5,760 ms | 5.76 ms/frame |
| render (full map, M1 fixture) | 500 | 2,815 ms | 5.63 ms/frame |
| render view (80x24) | 500 | 1,243 ms | 2.49 ms/frame |
| render view (80x24, inventory) | 500 | 1,874 ms | 3.75 ms/frame |
| render view (120x40) | 500 | 3,983 ms | 7.97 ms/frame |
| render view (120x40, modern dark) | 500 | 4,701 ms | 9.40 ms/frame |
| render view (120x40, inventory) | 200 | 1,907 ms | 9.54 ms/frame |
| render view (80x24, help) | 200 | 1,377 ms | 6.89 ms/frame |
| render view (80x24, palette) | 200 | 1,380 ms | 6.90 ms/frame |
| render view (80x24, scores) | 200 | 983 ms | 4.92 ms/frame |
| render view (80x24, share seed) | 200 | 927 ms | 4.64 ms/frame |
| step (M1 fixture, 栄養 20,000) | 10,000 | 11,560 ms | 1.16 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 8,916 ms | 8.92 ms/frame |
| step+render (full map, M1 fixture) | 500 | 4,773 ms | 9.55 ms/frame |
| render (generated level 1) | 500 | 1,988 ms | 3.98 ms/frame |
| step (generated, survivable) | 1,000 | 1,120 ms | 1.12 ms/turn |
| step+render (generated) | 500 | 2,616 ms | 5.23 ms/frame |
| generate level (depth 10) | 100 | 415 ms | 4.16 ms/level |

生成 100 回後の RNG 状態は §10〜§12 と同じ
`bb7b6c9d6f819216163597bcbde0ff79`（`generateN 100 10 (fromSeed 42)`）。

### 13.2 考察

- 同日に 2 回実行したところ、80x24 は 2.49〜2.89 ms、インベントリは
  3.75〜4.10 ms、120x40 は 7.97〜9.24 ms、Modern Dark は 9.08〜9.40 ms、
  ワイド インベントリは 9.54〜11.22 ms、ヘルプは 6.89〜6.95 ms、
  パレットは 6.20〜6.90 ms、step は 1.16〜1.24 ms/turn だった。
  §12 と同じくホスト負荷の変動が大きく、絶対値より比率を見る。
- Modern Dark は同じ 120x40 の Classic CGA とほぼ同じか、実行によっては
  わずかに速い。テーマは `Style` の色値を差し替えるだけで、ノード数・
  レイアウト・Canvas のセル数は変えないため、テーマ別の追加コストは
  計測誤差の範囲に収まっている。
- パレットは 18 項目から 19 項目に増えたが、クラシックでは枠内の
  上下パディングを 0 にして 21 行（タイトル + 19 項目 + ヒント）を
  22 行に収めた。描画時間は §12 の 5.36 ms から 6.90 ms に増えたが、
  同日の別実行では 6.20 ms で、項目追加そのものよりホスト負荷の影響が大きい。
- テーマ変更は `F3` のたびに 80x22 の Canvas を 1 回描き直すだけで、
  ターン処理を含まない。ゲーム中の通常描画と同じ経路であり、追加の
  乱数消費もない。
- step は 1.16 ms/turn、生成レベルで 1.12 ms/turn。§12 の 1.06 / 1.09 と
  同程度で、Core を変更していないことを確認できる。
- 1 階層の生成は 4.16 ms。§12 の 4.11 ms と同じで、生成経路は不変。

## 14. M4 スライス 6 追測（2026-11-02）

M4 スライス 6（マウス座標変換、クリック、ホイール、ホバー）を入れた
状態で `./verify.sh` を実行した。クリーンビルド、596 件のテスト、
PTY スモーク（起動・描画・終了）がすべて成功している。
計測方法は §9〜§13 と同じ。Core と乱数消費順序は変えていない。

### 14.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 3,620 ms | 3.62 ms/frame |
| render (full map, M1 fixture) | 500 | 2,279 ms | 4.56 ms/frame |
| render view (80x24) | 500 | 1,036 ms | 2.07 ms/frame |
| render view (80x24, inventory) | 500 | 1,598 ms | 3.20 ms/frame |
| render view (120x40) | 500 | 3,862 ms | 7.72 ms/frame |
| render view (120x40, modern dark) | 500 | 3,585 ms | 7.17 ms/frame |
| render view (120x40, inventory) | 200 | 1,649 ms | 8.25 ms/frame |
| render view (80x24, help) | 200 | 1,023 ms | 5.12 ms/frame |
| render view (80x24, palette) | 200 | 992 ms | 4.96 ms/frame |
| render view (80x24, scores) | 200 | 848 ms | 4.24 ms/frame |
| render view (80x24, share seed) | 200 | 865 ms | 4.33 ms/frame |
| step (M1 fixture, 栄養 20,000) | 10,000 | 12,085 ms | 1.21 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 4,767 ms | 4.77 ms/frame |
| step+render (full map, M1 fixture) | 500 | 3,572 ms | 7.14 ms/frame |
| render (generated level 1) | 500 | 1,828 ms | 3.66 ms/frame |
| step (generated, survivable) | 1,000 | 1,001 ms | 1.00 ms/turn |
| step+render (generated) | 500 | 2,328 ms | 4.66 ms/frame |
| generate level (depth 10) | 100 | 358 ms | 3.59 ms/level |

生成 100 回後の RNG 状態は §10〜§13 と同じ
`bb7b6c9d6f819216163597bcbde0ff79`（`generateN 100 10 (fromSeed 42)`）。

### 14.2 考察

- 80x24 は 2.07 ms、インベントリは 3.20 ms、120x40 は 7.72 ms、
  Modern Dark は 7.17 ms、ワイド インベントリは 8.25 ms、
  ヘルプは 5.12 ms、パレットは 4.96 ms、スコアは 4.24 ms、
  シェアは 4.33 ms。§13 より全体的に速いが、これは同日の
  ホスト負荷の差が大きく、描画ノードを増やしたわけではない。
- step は 1.21 ms/turn、生成レベルで 1.00 ms/turn。§13 の
  1.16 / 1.12 と同じ範囲で、Core を変更していない。
- step+render は 4.66〜7.14 ms/frame。マウス対応で追加されたのは
  ホバー時の Canvas 再描画 1 回だけで、クリックや移動そのものは
  既存の `Do` コマンド経路を通る。通常の 60 fps 予算 16.7 ms に収まる。
- ホバーは `HoverCell` で `App.Model.hover` を変え、`describeCell` が
  探索済みセルの文字列を作るだけ。ターン、乱数、リプレイには触れない。
- 1 階層の生成は 3.59 ms。§13 の 4.16 ms と同じ経路で、生成器は不変。
- 端末のマウス報告は入力イベントであり、描画ループの計測には含まれない。
  実端末での体感は、ホストの PTY と termui のイベント配送に依存する。

## 15. M4 スライス 7 追測（2026-11-02）

M4 スライス 7（イベント由来のアニメーション、16ms ティック、`F4` 無効化）を
入れた状態で `./verify.sh` を実行した。クリーンビルド、620 件のテスト、
PTY スモークがすべて成功している。計測方法は §9〜§14 と同じ。
Core と乱数消費順序は変えていない。

### 15.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 5,619 ms | 5.62 ms/frame |
| render (full map, M1 fixture) | 500 | 3,262 ms | 6.52 ms/frame |
| render view (80x24) | 500 | 1,305 ms | 2.61 ms/frame |
| render view (80x24, inventory) | 500 | 2,223 ms | 4.45 ms/frame |
| render view (120x40) | 500 | 6,545 ms | 13.09 ms/frame |
| render view (120x40, modern dark) | 500 | 7,670 ms | 15.34 ms/frame |
| render view (120x40, inventory) | 200 | 4,344 ms | 21.72 ms/frame |
| render view (80x24, help) | 200 | 1,892 ms | 9.46 ms/frame |
| render view (80x24, palette) | 200 | 1,554 ms | 7.77 ms/frame |
| render view (80x24, scores) | 200 | 1,320 ms | 6.60 ms/frame |
| render view (80x24, share seed) | 200 | 1,284 ms | 6.42 ms/frame |
| step (M1 fixture, 栄養 20,000) | 10,000 | 14,968 ms | 1.50 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 6,504 ms | 6.50 ms/frame |
| step+render (full map, M1 fixture) | 500 | 5,256 ms | 10.51 ms/frame |
| render (generated level 1) | 500 | 3,048 ms | 6.10 ms/frame |
| step (generated, survivable) | 1,000 | 2,466 ms | 2.47 ms/turn |
| step+render (generated) | 500 | 3,762 ms | 7.52 ms/frame |
| generate level (depth 10) | 100 | 519 ms | 5.20 ms/level |

生成 100 回後の RNG 状態は §10〜§14 と同じ
`bb7b6c9d6f819216163597bcbde0ff79`（`generateN 100 10 (fromSeed 42)`）。

### 15.2 考察

- 同日にもう一度テストを実行したところ、80x24 は 2.05 ms、インベントリは
  3.58 ms、120x40 は 9.75 ms、Modern Dark は 12.45 ms、ワイド
  インベントリは 15.19 ms、ヘルプは 7.15 ms、パレットは 6.51 ms、
  スコアは 5.63 ms、シェアは 5.62 ms、step は 1.30 ms/turn、
  生成 step は 1.68 ms/turn だった。実行間の差が大きく、ホスト負荷の
  影響を受けている。絶対値より同一実行内の比率を見る。
- アニメーションの追加コストは、効果があるフレームで `effectCells` の
  最大 24 個を描く分だけである。通常フレームは `drawMapAnimated` に
  空リストを渡す経路で、スライス 6 と同じセル数・同じ描画順になる。
- ダメージ数字は 1 文字ずつ横に並べ、80x22 の外は捨てる。移動残像や
  ドア・トラップの記号は 1 セルだけで、マップのセル数を増やさない。
- アニメーションのティックは `Every "animation" 16 AnimationTick`。
  効果が消えると `subs` からタイマーが外れ、アイドル時の再描画はない。
  時計・乱数・ターン処理には触れない。
- step は 1.30〜1.50 ms/turn、生成レベルで 1.68〜2.47 ms/turn。
  §14 の 1.21 / 1.00 より遅いが、同日の負荷上昇によるもので、Core の
  コードは変更していない。RNG 状態も §14 と一致する。
- 1 階層の生成は 5.20〜9.25 ms。§14 の 3.59 ms より遅いが、生成経路は
  不変で、これもホスト負荷の影響と見られる。

## 16. M4 スライス 8 追測（2026-11-02）

M4 スライス 8（スコア画面からの可視リプレイ、1 コマンドずつの再生、
速度変更・一時停止・再開）を入れた状態で `./verify.sh` を実行した。
クリーンビルド、647 件のテスト、PTY スモークがすべて成功している。
計測方法は §9〜§15 と同じ。Core と乱数消費順序は変えていない。

### 16.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 5,030 ms | 5.03 ms/frame |
| render (full map, M1 fixture) | 500 | 2,072 ms | 4.15 ms/frame |
| render view (80x24) | 500 | 961 ms | 1.92 ms/frame |
| render view (80x24, inventory) | 500 | 1,459 ms | 2.92 ms/frame |
| render view (120x40) | 500 | 3,297 ms | 6.59 ms/frame |
| render view (120x40, modern dark) | 500 | 3,444 ms | 6.89 ms/frame |
| render view (120x40, inventory) | 200 | 1,652 ms | 8.26 ms/frame |
| render view (80x24, help) | 200 | 940 ms | 4.70 ms/frame |
| render view (80x24, palette) | 200 | 903 ms | 4.52 ms/frame |
| render view (80x24, scores) | 200 | 780 ms | 3.90 ms/frame |
| render view (80x24, share seed) | 200 | 809 ms | 4.05 ms/frame |
| step (M1 fixture, 栄養 20,000) | 10,000 | 9,351 ms | 0.94 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 5,617 ms | 5.62 ms/frame |
| step+render (full map, M1 fixture) | 500 | 3,381 ms | 6.76 ms/frame |
| render (generated level 1) | 500 | 1,796 ms | 3.59 ms/frame |
| step (generated, survivable) | 1,000 | 952 ms | 0.95 ms/turn |
| step+render (generated) | 500 | 2,406 ms | 4.81 ms/frame |
| generate level (depth 10) | 100 | 448 ms | 4.48 ms/level |

生成 100 回後の RNG 状態は §10〜§15 と同じ
`bb7b6c9d6f819216163597bcbde0ff79`（`generateN 100 10 (fromSeed 42)`）。

### 16.2 考察

- 80x24 は 1.92 ms、インベントリは 2.92 ms、120x40 は 6.59 ms、
  Modern Dark は 6.89 ms、ワイド インベントリは 8.26 ms、
  ヘルプは 4.70 ms、パレットは 4.52 ms、スコアは 3.90 ms、
  シェアは 4.05 ms。§14 と同程度か、やや速い。スライス 8 は
  通常レイアウトの描画ノードを増やしていない。
- step は 0.94 ms/turn、生成レベルで 0.95 ms/turn。§14 の
  1.21 / 1.00、§15 の 1.30〜1.50 / 1.68〜2.47 より速く、
  ホスト負荷が下がったタイミングの値と見られる。Core は不変。
- step+render は 4.81〜6.76 ms/frame。可視リプレイの 1 ティックも
  同じ `step` + `drawMapAnimated` 経路で、追加の全体再構築はない。
- 可視リプレイは slow 400ms / normal 200ms / fast 80ms の間隔で
  1 コマンドずつ進む。描画 1 回は上の step+render の範囲に収まり、
  80ms 間隔でも 16.7ms 予算を超えない。
- 再生中は `Every "replay"` だけを追加し、停止・完走・終了で
  `subs` から外れる。アイドル時のタイマーや再描画は増えない。
- 1 階層の生成は 4.48 ms。§13 の 4.16 ms、§14 の 3.59 ms と同程度で、
  生成経路は不変。

## 17. M4 スライス 9 追測（2026-11-02）

M4 スライス 9（キーマップ、`settings.json`、ヘルプ/パレットの動的生成、
22 項目パレット）を入れた状態で `./verify.sh` を実行した。
クリーンビルド、697 件のテスト、PTY スモークがすべて成功している。
計測方法は §9〜§16 と同じ。Core と乱数消費順序は変えていない。

### 17.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 4,602 ms | 4.60 ms/frame |
| render (full map, M1 fixture) | 500 | 2,478 ms | 4.96 ms/frame |
| render view (80x24) | 500 | 1,167 ms | 2.33 ms/frame |
| render view (80x24, inventory) | 500 | 1,765 ms | 3.53 ms/frame |
| render view (120x40) | 500 | 3,975 ms | 7.95 ms/frame |
| render view (120x40, modern dark) | 500 | 4,042 ms | 8.08 ms/frame |
| render view (120x40, inventory) | 200 | 1,871 ms | 9.36 ms/frame |
| render view (80x24, help) | 200 | 1,129 ms | 5.65 ms/frame |
| render view (80x24, palette) | 200 | 1,131 ms | 5.66 ms/frame |
| render view (80x24, scores) | 200 | 916 ms | 4.58 ms/frame |
| render view (80x24, share seed) | 200 | 983 ms | 4.92 ms/frame |
| step (M1 fixture, 栄養 10,000) | 10,000 | 10,758 ms | 1.08 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 5,135 ms | 5.14 ms/frame |
| step+render (full map, M1 fixture) | 500 | 3,836 ms | 7.67 ms/frame |
| render (generated level 1) | 500 | 1,961 ms | 3.92 ms/frame |
| step (generated, survivable) | 1,000 | 1,071 ms | 1.07 ms/turn |
| step+render (generated) | 500 | 2,578 ms | 5.16 ms/frame |
| generate level (depth 10) | 100 | 419 ms | 4.20 ms/level |

生成 100 回後の RNG 状態は §10〜§16 と同じ
`bb7b6c9d6f819216163597bcbde0ff79`（`generateN 100 10 (fromSeed 42)`）。

### 17.2 考察

- 80x24 は 2.33 ms、インベントリは 3.53 ms、120x40 は 7.95 ms、
  Modern Dark は 8.08 ms、ワイド インベントリは 9.36 ms、
  ヘルプは 5.65 ms、パレットは 5.66 ms、スコアは 4.58 ms、
  シェアは 4.92 ms。§16 の 1.92 / 2.92 / 6.59 / 6.89 / 8.26 /
  4.70 / 4.52 / 3.90 / 4.05 ms より少し遅いが、ホスト負荷の変動範囲で、
  通常レイアウトのノード構成は変えていない。
- パレットは 22 項目になったため、80x24 では 11 行 2 列に分けた。
  行数は 22 行から 11 行に減り、1 画面に収まる。ワイドは 1 列のまま。
  パレット描画は 4.52 → 5.66 ms とやや増えたが、1 フレームの予算内である。
- ヘルプとパレットのヒントは描画時にキーマップから生成する。要素数は
  固定（ヘルプ十数行、パレット 22 項目）で、キー入力ごとに別の文字列を
  組み立てる経路はない。
- step は 1.08 ms/turn、生成レベルで 1.07 ms/turn。§16 の
  0.94 / 0.95 と同程度で、Core のコードは変更していない。
- step+render は 5.14〜7.67 ms/frame。スライス 8 の可視リプレイと同じ
  `step` + `drawMapAnimated` 経路で、キーマップ解決は入力時に 1 回だけ行う。
- 1 階層の生成は 4.20 ms。§16 の 4.48 ms と同程度で、生成経路は不変。

## 18. M4 スライス 10 追測（2026-11-03）

M4 スライス 10（戦績 `scores.jsonl`、リプレイ `lambda-rogue.replay.v1`、
`Persist.Paths` / `Json` / `Codec` / `Score` / `Replay`、ゲーム終了時の
保存と起動時の戦績読み込み、`PersistTest`）を入れた状態で
`./verify.sh` を実行した。クリーンビルド、760 件のテスト、
PTY スモークがすべて成功している。計測方法は §9〜§17 と同じ。
Core の step 経路と乱数消費順序は変えていない。

### 18.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 4,559 ms | 4.56 ms/frame |
| render (full map, M1 fixture) | 500 | 3,572 ms | 7.14 ms/frame |
| render view (80x24) | 500 | 1,900 ms | 3.80 ms/frame |
| render view (80x24, inventory) | 500 | 2,244 ms | 4.49 ms/frame |
| render view (120x40) | 500 | 4,245 ms | 8.49 ms/frame |
| render view (120x40, modern dark) | 500 | 4,477 ms | 8.96 ms/frame |
| render view (120x40, inventory) | 200 | 2,660 ms | 13.30 ms/frame |
| render view (80x24, help) | 200 | 1,164 ms | 5.82 ms/frame |
| render view (80x24, palette) | 200 | 1,227 ms | 6.14 ms/frame |
| render view (80x24, scores) | 200 | 913 ms | 4.57 ms/frame |
| render view (80x24, share seed) | 200 | 938 ms | 4.69 ms/frame |
| step (M1 fixture, 栄養 10,000) | 10,000 | 11,747 ms | 1.17 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 6,225 ms | 6.23 ms/frame |
| step+render (full map, M1 fixture) | 500 | 4,553 ms | 9.11 ms/frame |
| render (generated level 1) | 500 | 2,312 ms | 4.62 ms/frame |
| step (generated, survivable) | 1,000 | 1,280 ms | 1.28 ms/turn |
| step+render (generated) | 500 | 2,980 ms | 5.96 ms/frame |
| generate level (depth 10) | 100 | 494 ms | 4.95 ms/level |

生成 100 回後の RNG 状態は §10〜§17 と同じ
`bb7b6c9d6f819216163597bcbde0ff79`（`generateN 100 10 (fromSeed 42)`）。

### 18.2 考察

- 80x24 は 3.80 ms、インベントリは 4.49 ms、120x40 は 8.49 ms、
  Modern Dark は 8.96 ms、ワイドインベントリは 13.30 ms。§17 の
  2.33 / 3.53 / 7.95 / 8.08 / 9.36 ms より遅いが、ホスト負荷の
  変動が大きく、描画ノード構成は変えていない。パレットは 6.14 ms で
  §17 の 5.66 ms と同程度、スコアは 4.57 ms で 4.58 ms とほぼ同じ。
- step は 1.17 ms/turn、生成レベルで 1.28 ms/turn。§17 の
  1.08 / 1.07 と同程度で、永続化は `step` の外側（ゲーム終了時と起動時）
  にだけ存在する。
- step+render は 5.96〜9.11 ms/frame。可視リプレイと通常プレイは
  従来どおり同じ `step` + `drawMapAnimated` 経路で、保存処理は
  ゲーム終了時に 1 回だけ `Perform` で走る。
- 戦績の読み込みは起動時に 1 回、`scores.jsonl` の行数に比例する。
  現在の履歴は小さく、描画ループには入らない。リプレイ保存は
  終了時に 1 ファイルを書くだけで、ターンごとの I/O はない。
- 1 階層の生成は 4.95 ms。§17 の 4.20 ms と同程度で、生成経路は不変。
- `verify.sh` は Clang 19 の `-Wparentheses-equality` を避けるため、
  Clang 検出時に `IDRIS2_CFLAGS="-Wno-parentheses-equality"` を付ける。
  これはビルド時だけで、実行時の性能には影響しない。

## 19. M4 スライス 11 追測（2026-11-04）

M4 スライス 11（`lambda-rogue.save.v1`、手動セーブ/オートセーブ、
`session.lock`、起動時の自動再開、パレットの `Save and quit` /
`Load game`、24 項目パレット）を入れた状態で `./verify.sh` を実行した。
クリーンビルド、当時 780 件のテスト、PTY スモークがすべて成功している。
計測方法は §9〜§18 と同じ。Core の step 経路と乱数消費順序は変えていない。
`verify.sh` はスモークを `$PWD/build/verify-data` に隔離し、実際の
セーブ・戦績・設定を触らない。

### 19.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 3,407 ms | 3.41 ms/frame |
| render (full map, M1 fixture) | 500 | 2,049 ms | 4.10 ms/frame |
| render view (80x24) | 500 | 902 ms | 1.81 ms/frame |
| render view (80x24, inventory) | 500 | 1,336 ms | 2.67 ms/frame |
| render view (120x40) | 500 | 3,316 ms | 6.63 ms/frame |
| render view (120x40, modern dark) | 500 | 2,980 ms | 5.96 ms/frame |
| render view (120x40, inventory) | 200 | 1,371 ms | 6.86 ms/frame |
| render view (80x24, help) | 200 | 838 ms | 4.19 ms/frame |
| render view (80x24, palette) | 200 | 886 ms | 4.43 ms/frame |
| render view (80x24, scores) | 200 | 695 ms | 3.48 ms/frame |
| render view (80x24, share seed) | 200 | 698 ms | 3.49 ms/frame |
| step (M1 fixture, 栄養 10,000) | 10,000 | 8,994 ms | 0.90 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 4,042 ms | 4.04 ms/frame |
| step+render (full map, M1 fixture) | 500 | 3,260 ms | 6.52 ms/frame |
| render (generated level 1) | 500 | 1,537 ms | 3.08 ms/frame |
| step (generated, survivable) | 1,000 | 937 ms | 0.94 ms/turn |
| step+render (generated) | 500 | 2,004 ms | 4.01 ms/frame |
| generate level (depth 10) | 100 | 327 ms | 3.27 ms/level |

生成 100 回後の RNG 状態は §10〜§18 と同じ
`bb7b6c9d6f819216163597bcbde0ff79`（`generateN 100 10 (fromSeed 42)`）。

### 19.2 考察

- 80x24 は 1.81 ms、インベントリは 2.67 ms、120x40 は 6.63 ms、
  Modern Dark は 5.96 ms、ワイドインベントリは 6.86 ms、
  ヘルプは 4.19 ms、パレットは 4.43 ms、スコアは 3.48 ms、
  シェアは 3.49 ms。§18 の 3.80 / 4.49 / 8.49 / 8.96 / 13.30 /
  5.82 / 6.14 / 4.57 / 4.69 ms より全体的に速く、ホスト負荷の
  変動範囲である。描画ノード構成は変えていない。
- パレットは 24 項目になった。80x24 では 12 行 2 列で 1 画面に収まり、
  ワイドは 1 列のまま。描画は §18 の 6.14 ms から 4.43 ms で、
  項目追加による悪化は見られない。
- step は 0.90 ms/turn、生成レベルで 0.94 ms/turn。§18 の
  1.17 / 1.28 と同程度か少し速く、Core のコードは変更していない。
- step+render は 4.04〜6.52 ms/frame。セーブ/オートセーブは `step` の
  外側にあり、ターンごとの描画経路には入らない。
- オートセーブは 10 前進ターンごとに 1 回、`save.json` 全体を
  一時ファイルへ書いて `fsync` する。描画ループの毎フレーム処理ではないが、
  該当ターンだけは 1 回分のファイル I/O が加わる。今回の perf テストは
  純粋な `step` を測るため、この I/O は含まない。
- 起動時は `session.lock` の取得、`settings.json` と `scores.jsonl` の
  読み込み、`save.json` → `autosave.json` の順の復旧を行う。いずれも
  起動時に 1 回だけで、描画ループには入らない。
- セッションロックの取得は、データディレクトリが存在しない初回起動でも
  成功するよう `ensureDataDir` を先に呼ぶ。この修正は PTY スモークで
  「既に実行中」と誤判定されたことを受けて入れた。
- 1 階層の生成は 3.27 ms。§18 の 4.95 ms より速く、生成経路は不変。

## 20. M4 スライス 12 追測（2026-11-07）

M4 スライス 12（Rogue 5.4.4 忠実性監査）を入れた状態で `./verify.sh` を
実行した。クリーンビルド、789 件のテスト、PTY スモーク
（`starts, draws and quits on a PTY`）がすべて成功し、`== verify: ok ==` で
終了した。計測方法は §9〜§19 と同じ。

### 20.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 2,769 ms | 2.77 ms/frame |
| render (full map, M1 fixture) | 500 | 1,731 ms | 3.46 ms/frame |
| render view (80x24) | 500 | 749 ms | 1.50 ms/frame |
| render view (80x24, inventory) | 500 | 1,138 ms | 2.28 ms/frame |
| render view (120x40) | 500 | 3,477 ms | 6.95 ms/frame |
| render view (120x40, modern dark) | 500 | 2,904 ms | 5.81 ms/frame |
| render view (120x40, inventory) | 200 | 1,349 ms | 6.75 ms/frame |
| render view (80x24, help) | 200 | 828 ms | 4.14 ms/frame |
| render view (80x24, palette) | 200 | 893 ms | 4.47 ms/frame |
| render view (80x24, scores) | 200 | 662 ms | 3.31 ms/frame |
| render view (80x24, share seed) | 200 | 692 ms | 3.46 ms/frame |
| step (M1 fixture, 栄養 10,000) | 10,000 | 8,725 ms | 0.87 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 4,140 ms | 4.14 ms/frame |
| step+render (full map, M1 fixture) | 500 | 3,269 ms | 6.54 ms/frame |
| render (generated level 1) | 500 | 1,642 ms | 3.28 ms/frame |
| step (generated, survivable) | 1,000 | 877 ms | 0.88 ms/turn |
| step+render (generated) | 500 | 2,085 ms | 4.17 ms/frame |
| generate level (depth 10) | 100 | 344 ms | 3.44 ms/level |

生成 100 回後の RNG 状態は
`19a2b446df8069f25c343fb1c8b922f9`（`generateN 100 10 (fromSeed 42)`）。
§19 の `bb7b6c9d6f819216163597bcbde0ff79` から変わっているのは、スライス 12 で
装備の強化値・呪い率、指輪の強化値、杖の充填数の乱数消費を 5.4.4 に合わせて
修正したためである。生成経路の乱数呼び出し回数が変わるので、スライス 11 以前の
seed で生成した階層・リプレイとは一致しない。これは意図した変更であり、
同じビルド内の「同じ seed + 同じコマンド列」の決定論は保たれている。

### 20.2 考察

- 80x24 は 1.50 ms、インベントリは 2.28 ms、120x40 は 6.95 ms、
  Modern Dark は 5.81 ms、ワイドインベントリは 6.75 ms、
  ヘルプは 4.14 ms、パレットは 4.47 ms、スコアは 3.31 ms、
  シェアは 3.46 ms。§19 の 1.81 / 2.67 / 6.63 / 5.96 / 6.86 /
  4.19 / 4.43 / 3.48 / 3.49 ms と同水準で、描画ノード構成は変えていない。
  実行ごとの 10〜20% の変動範囲に収まっている。
- step は 0.87 ms/turn、生成レベルで 0.88 ms/turn。§19 の
  0.90 / 0.94 と同じで、スライス 12 はデータ表と確率の置換だけで、
  ターン処理の計算量を増やしていない。
- step+render は 4.14〜6.54 ms/frame。60 Hz のフレーム予算 16.67 ms に
  対して最悪ケースでも約 39% で、M1 の目標内に収まる。
- 生成は 3.44 ms/level。§19 の 3.27 ms と同程度。モンスター表・
  アイテム表の参照と乱数呼び出しの変更は、生成時間に影響しない。
- テストはスライス 11 時点の 780 件から 789 件へ増えた。増分はスライス 12 で
  追加した忠実性の回帰テスト（光の杖の充填数 10–19、dexterity の指輪が
  命中のみを上げ AC を変えないことなど）である。
- `verify.sh` はクリーンビルド、全テスト、PTY スモークの順に実行し、
  スモークは `$PWD/build/verify-data` に隔離される。ローカルの
  セーブ・戦績・設定・セッションロックには触れない。

## 21. シード生成修正 追測（2026-11-08）

新規ランが常に `sampleSeed` で始まっていた問題を修正した。通常起動では
`System.Clock` の UTC ナノ秒と PID から 64-bit seed を生成し、
`--seed <16 桁小文字 hex>` で共有 seed を再現できるようにした。
`./verify.sh` を実行し、クリーンビルド、795 件のテスト、PTY スモークが
すべて成功して `== verify: ok ==` で終了した。計測方法は §9〜§20 と同じ。

### 21.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 3,955 ms | 3.96 ms/frame |
| render (full map, M1 fixture) | 500 | 2,273 ms | 4.55 ms/frame |
| render view (80x24) | 500 | 1,094 ms | 2.19 ms/frame |
| render view (80x24, inventory) | 500 | 1,731 ms | 3.46 ms/frame |
| render view (120x40) | 500 | 3,275 ms | 6.55 ms/frame |
| render view (120x40, modern dark) | 500 | 3,314 ms | 6.63 ms/frame |
| render view (120x40, inventory) | 200 | 1,435 ms | 7.18 ms/frame |
| render view (80x24, help) | 200 | 862 ms | 4.31 ms/frame |
| render view (80x24, palette) | 200 | 918 ms | 4.59 ms/frame |
| render view (80x24, scores) | 200 | 707 ms | 3.54 ms/frame |
| render view (80x24, share seed) | 200 | 756 ms | 3.78 ms/frame |
| step (M1 fixture, 栄養 10,000) | 10,000 | 8,914 ms | 0.89 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 4,399 ms | 4.40 ms/frame |
| step+render (full map, M1 fixture) | 500 | 3,604 ms | 7.21 ms/frame |
| render (generated level 1) | 500 | 1,738 ms | 3.48 ms/frame |
| step (generated, survivable) | 1,000 | 941 ms | 0.94 ms/turn |
| step+render (generated) | 500 | 2,299 ms | 4.60 ms/frame |
| generate level (depth 10) | 100 | 374 ms | 3.75 ms/level |

生成 100 回後の RNG 状態は §20 と同じ
`19a2b446df8069f25c343fb1c8b922f9`。シード生成は `newGame` の外側にあり、
ダンジョン生成の乱数消費順序を変えていない。

### 21.2 シードの再現確認

PTY で実行し、画面出力の SHA-256 を比較した。

| 起動 | 結果 |
| --- | --- |
| `--seed 0123456789abcdef` を 2 回 | 2 回の画面出力が完全に一致 |
| `--seed 0123456789abcdef` と `--seed fedcba9876543210` | 画面出力が異なる |
| seed 指定なしを 2 回 | 画面出力が異なる |
| `--seed 0123456789ABCDEF` | 無効な seed として起動前にエラー |

- 同じ seed と同じコマンド列では同じ画面になる。リプレイの前提を保っている。
- seed 指定なしでは起動ごとにダンジョンが変わる。
- `--seed` の解析は `App.Startup.parseStartSeed` に閉じ込め、
  `tests/StartupTest.idr` で受理・拒否・欠落・未知引数を検証する。

### 21.3 考察

- 描画と `step` の値は §20 の 2.77 / 3.46 / 0.87 ms などと同じ範囲で、
  シード生成の追加によるターン処理の変化はない。seed の生成は起動時に
  1 回だけで、描画ループには入らない。
- テストは 789 件から 795 件へ増えた。増分は `App.Startup` の
  6 チェック（生成 seed、明示 seed、不正値、欠落、未知引数、混合）である。
- `sampleSeed` は UI テストとベンチマークの固定フィクスチャとして残す。
  実行時の新規ランには使わない。

## 22. M5 スライス 1 追測（2026-11-09）

M5 スライス 1（探索、searching の指輪、healing / extra healing、
magic missile 1d4）を入れた状態でテストスイートを実行した。
計測方法は §9〜§21 と同じ。`Search` は 1 ターン消費するが、
通常の移動・戦闘経路に追加の乱数消費はなく、searching の指輪を
装着していない限り `step` の計算量は変わらない。

### 22.1 結果

| 項目 | 反復 | 合計 | 1 回あたり |
|---|---:|---:|---:|
| render (initial FOV, M1 fixture) | 1,000 | 2,880 ms | 2.88 ms/frame |
| render (full map, M1 fixture) | 500 | 2,237 ms | 4.48 ms/frame |
| render view (80x24) | 500 | 932 ms | 1.86 ms/frame |
| render view (80x24, inventory) | 500 | 1,829 ms | 3.66 ms/frame |
| render view (120x40) | 500 | 3,744 ms | 7.49 ms/frame |
| render view (120x40, modern dark) | 500 | 3,147 ms | 6.29 ms/frame |
| render view (120x40, inventory) | 200 | 1,297 ms | 6.49 ms/frame |
| render view (80x24, help) | 200 | 887 ms | 4.44 ms/frame |
| render view (80x24, palette) | 200 | 835 ms | 4.18 ms/frame |
| render view (80x24, scores) | 200 | 602 ms | 3.01 ms/frame |
| render view (80x24, share seed) | 200 | 805 ms | 4.03 ms/frame |
| step (M1 fixture, 栄養 10,000) | 10,000 | 8,894 ms | 0.89 ms/turn |
| step+render (initial FOV, M1 fixture) | 1,000 | 3,888 ms | 3.89 ms/frame |
| step+render (full map, M1 fixture) | 500 | 2,942 ms | 5.89 ms/frame |
| render (generated level 1) | 500 | 1,889 ms | 3.78 ms/frame |
| step (generated, survivable) | 1,000 | 1,538 ms | 1.54 ms/turn |
| step+render (generated) | 500 | 2,535 ms | 5.07 ms/frame |
| generate level (depth 10) | 100 | 371 ms | 3.72 ms/level |

生成 100 回後の RNG 状態は §20〜§21 と同じ
`19a2b446df8069f25c343fb1c8b922f9`。探索と指輪は生成経路の乱数消費を
変えないため、既存 seed のダンジョンはそのまま再現できる。

### 22.2 考察

- 描画と `step` の値は §20〜§21 の範囲内で、パレットが 24 項目から
  25 項目に増えたことによる描画時間の悪化は見られない。
- `step` は検索対象のトラップがある場合だけ乱数を消費する。指輪を
  装着していない通常プレイでは、探索コマンドを明示的に使わない限り
  乱数消費順は従来と同じである。
- テストは 795 件から 814 件へ増えた。増分は `M5Test` の 15 チェックと、
  既存テストの `s` キー、パレットの `Search for traps` / `Quit`、
  ヘルプの search 表示の 4 チェックである。`PersistTest` は既存の
  コマンド往復チェックに `Search` を加えたため、チェック数は変わらない。
- `M3Test` の extra healing は固定の全回復を期待していたため、
  「HP が増え、最大 HP を超えない」という新しい契約に更新した。
- `./verify.sh` はクリーンビルド、814 件のテスト、PTY スモークを実行し、
  `== verify: ok ==` で終了する。
