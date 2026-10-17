# G2 (変異検査): `src/fuzz.nim`

- 測定日: 2026-10-17
- 道具: nim-muter 0.2.10
- ジョブ: `tests/mutation/fuzz.json` (リポジトリ直下で `../nim-muter/bin/nim-muter run --config tests/mutation/fuzz.json`)
- 対象テスト: `tests/external/test_fuzz.nim` と `tests/external/test_fuzz_isolated.nim` (E テストのみ。公開 proc だけを呼ぶ)。どちらも信号なしと `--cc:clang -d:fuzzCoverage` の 2 通りでビルドして流す (`when defined(fuzzCoverage)` の中は後者でだけ走る)
- 台帳: `docs/quality/survivors-fuzz.json`

## 結果

| | killed | survived | timeout | compileError | 計 |
|---|---:|---:|---:|---:|---:|
| 追加前 (測定) | 212 | 98 | 17 | 30 | 357 |
| 追加後 (2026-10-17 測り直し、7898a910) | 247 | 60 | 20 | 30 | 357 |
| 規則の追加と 2 つの修正の後 (2026-10-17、a8408b5d) | 250 | 61 | 20 | 30 | 361 |
| ISO-02 のテストを 1 本足した後 (2026-10-17、accd2f3f) | 250 | 61 | 20 | 30 | 361 |
| 出力の向け直しの修正の後 (2026-10-18、8c78179f) | 250 | 67 | 21 | 30 | 368 |
| ISO-04 のテストを 1 本足した後 (2026-10-18、b5a5870a) | 251 | 66 | 21 | 30 | 368 |

「追加後」は足したテストを入れたコミット (7898a910) で測り直した値。足したテストで消える 38 件は、変異を 1 件ずつ `src/fuzz.nim` に手で当て、該当するビルド (信号なし、または `-d:fuzzCoverage`) で足したテストが落ちることも確かめてある。38 件のうち 35 件は killed、3 件は timeout になった (どちらも検出)。

timeout 17 件は、変異でテストが時間内に終わらなかったもので、検出として扱い (killed と同じ)、台帳には載せない。compileError 30 件は変異後のコードがコンパイルできなかったもので、テストの穴ではない。

## 生き残った変異と理由

残り 66 件の内訳: 等価 30 件、未到達 8 件、許容 28 件。行の番号は 6 回目に測ったコミット (b5a5870a) のもの (5 回目の 8c78179f と同じ)。表は台帳 (`survivors-fuzz.json`) から作った。`nim-muter-ledger check` は終了コード 0。

許容はどれも、利用者が 2026-10-17 に決めたもの (下の「利用者の決定」)。

| 行 | 変異子 | 元 → 変更後 | 分類 | 理由 |
|---:|---|---|---|---|
| 66 | CVR | `20` → `21` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。maxFindings (発見をいくつで止めるか、0 なら 20) を定める仕様 ID は無い。既定の上限 20 が 21 になる。 |
| 67 | CVR | `2000` → `2001` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。最小化の試行の上限 (プロセス内 2000、hung 24) を定める仕様 ID は無い (MIN-01 は上限があることだけを述べる)。上限 2000 が 2001 になる。 |
| 89 | ROR | `took <= config.slowAfterMs` → `<<= -> <>` | 許容 | 利用者が 2026-10-17 に受け入れると決めた。かかった時間がちょうど slowAfterMs ミリ秒のときだけ違い (FND-05 の「より長く」は元が満たす)、時計で測るのでテストで決定的に作れない。 |
| 89 | RVR | `return verdict` → `<return default>` | 等価 | 87 行で wrong の verdict は先に返るので、ここの verdict は wrong でない。wrong でない Verdict は judge でも answerOf (370 行) でも既定値 Verdict() そのもので、既定値を返しても同じ。 |
| 116 | CVR | `0` → `1` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。最小化の試行の上限 (プロセス内 2000、hung 24) を定める仕様 ID は無い (MIN-01 は上限があることだけを述べる)。試行の数え始めが 1 になり、上限に 1 回早く届く。 |
| 117 | CVR | `1` → `2` | 許容 | 利用者が 2026-10-17 に、MIN-01 の「除けるだけ除く」を 1-minimal (どの 1 バイトを除いても同じ発見でなくなる) の意味と決め、どの 1-minimal な入力になるかは定めないとした。変異は最初に除く幅を変えるだけで、修正後の最小化 (1 バイトずつの輪を、何も除けなくなるまで繰り返す) は最初の幅によらず 1-minimal な入力を返す。変異を当てて MIN-01 のテスト (両方のテストファイル) が通ることを手で確かめた。 |
| 118 | LOR | `size >= 1 and tries < budget` → `<and -> or>` | 等価 | size は 117 行で 1 以上になり、131 行の半減も 130 行で size が 1 のとき先に抜けるので 1 以上のまま。size >= 1 は常に真で、or にすると条件は常に真。tries が budget に達したあとも外側の輪は回るが、内側の輪 (120 行) が 1 度も回らず、size が 1 になって 130 行で抜ける。結果は同じ。 |
| 118 | ROR | `tries < budget` → `<< -> <=>` | 等価 | tries == budget で外側の輪に入っても、内側の輪 (120 行の tries < budget) は 1 度も回らず、130 行で抜けるまで size を半分にするだけ。結果は同じ。 |
| 121 | ROR | `tries < budget` → `<< -> <=>` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。最小化の試行の上限 (プロセス内 2000、hung 24) を定める仕様 ID は無い (MIN-01 は上限があることだけを述べる)。試行が上限より 1 回多くなる。 |
| 123 | SDL | `inc tries` → `discard` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。最小化の試行の上限 (プロセス内 2000、hung 24) を定める仕様 ID は無い (MIN-01 は上限があることだけを述べる)。上限が効かなくなる (輪は入力が縮むか at が減るので上限なしでも終わる)。 |
| 143 | CVR | `1` → `2` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。変異の作り方 (種類・幅・確率) を定める仕様 ID は無い (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も保たれる)。種類を選ぶ幅が 1 狭くなる。 |
| 153 | CVR | `7` → `8` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。変異の作り方 (種類・幅・確率) を定める仕様 ID は無い (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も保たれる)。「一続きを除く」の長さの上限が 1 増える。 |
| 160 | CVR | `1` → `2` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。変異の作り方 (種類・幅・確率) を定める仕様 ID は無い (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も保たれる)。「一続きを繰り返す」で末尾の 1 バイトが外れる。 |
| 160 | LBR | `at .. min(result.len - 1, at + rng.rand(15))` → `<.. -> ..<>` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。変異の作り方 (種類・幅・確率) を定める仕様 ID は無い (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も保たれる)。「一続きを繰り返す」が 1 バイト短くなる。 |
| 176 | CVR | `0` → `1` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。変異の作り方 (種類・幅・確率) を定める仕様 ID は無い (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も保たれる)。先頭から始まる数字の並びを差し替えず挿入する。 |
| 176 | ROR | `first < 0` → `<< -> <=>` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。変異の作り方 (種類・幅・確率) を定める仕様 ID は無い (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も保たれる)。先頭から始まる数字の並びを差し替えず挿入する。 |
| 179 | CVR | `1` → `2` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。変異の作り方 (種類・幅・確率) を定める仕様 ID は無い (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も保たれる)。数字の並びの終わりを 1 つ手前で止める。 |
| 180 | LBR | `0 ..< first` → `<..< -> ..>` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。変異の作り方 (種類・幅・確率) を定める仕様 ID は無い (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も保たれる)。差し替えで並びの最初の数字が残る。 |
| 181 | CVR | `9` → `10` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。変異の作り方 (種類・幅・確率) を定める仕様 ID は無い (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も保たれる)。辞書の語の挿入と上書きが入れ替わる。 |
| 186 | CVR | `1` → `2` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。変異の作り方 (種類・幅・確率) を定める仕様 ID は無い (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も保たれる)。上書きのあとの残りから末尾の 1 バイトが落ちる (^1 → ^2)。 |
| 186 | LBR | `at + word.len .. ^1` → `<.. -> ..<>` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。変異の作り方 (種類・幅・確率) を定める仕様 ID は無い (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も保たれる)。上書きのあとの残りから末尾の 1 バイトが落ちる。 |
| 186 | ROR | `at + word.len < result.len` → `<< -> <=>` | 等価 | at + word.len == result.len のとき、変異後の result[result.len .. ^1] は空文字列で、元の else の "" と同じ。 |
| 187 | ROR | `result.len > config.maxLen` → `<> -> >=>` | 等価 | result.len == maxLen のとき setLen(maxLen) は何も変えない。 |
| 197 | CVR | `0` → `1` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。maxFindings (発見をいくつで止めるか、0 なら 20) を定める仕様 ID は無い。maxFindings = 1 が既定と同じ扱いになる。 |
| 199 | ROR | `seed.len > config.maxLen` → `<> -> >=>` | 等価 | seed.len == maxLen のとき seed[0 ..< maxLen] は seed そのもの。 |
| 207 | ROR | `config.inFlightPath.len > 0` → `<> -> >=>` | 等価 | inFlightPath が空のとき removeFile("") が呼ばれる。unlink("") は ENOENT で失敗し、removeFile (tryRemoveFile) は ENOENT を誤りにしないので、何も起きない。 |
| 216 | ROR | `result.findings.len < findingsWanted` → `<< -> <=>` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。maxFindings (発見をいくつで止めるか、0 なら 20) を定める仕様 ID は無い。発見が上限より 1 つ多く残る。 |
| 231 | ROR | `config.inFlightPath.len > 0` → `<> -> >=>` | 等価 | inFlightPath が空のとき removeFile("") が呼ばれる。unlink("") は ENOENT で失敗し、removeFile (tryRemoveFile) は ENOENT を誤りにしないので、何も起きない。 |
| 242 | CVR | `16` → `17` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。保存の名前の形を定める仕様 ID は無く、CRP-01 の「同じ入力は同じ名前」「.input で終わる」は変異後も保たれる。16 進の桁が 17 桁になる。 |
| 243 | CVR | `0` → `1` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。保存の名前の形を定める仕様 ID は無く、CRP-01 の「同じ入力は同じ名前」「.input で終わる」は変異後も保たれる。最初の名前から「-1」が付く。 |
| 247 | CVR | `0` → `1` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。保存の名前の形を定める仕様 ID は無く、CRP-01 の「同じ入力は同じ名前」「.input で終わる」は変異後も保たれる。最初の名前に「-0」が付き、2 つ目が番号なしになる。 |
| 247 | ROR | `attempt == 0` → `<== -> !=>` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。保存の名前の形を定める仕様 ID は無く、CRP-01 の「同じ入力は同じ名前」「.input で終わる」は変異後も保たれる。最初の名前に「-0」が付き、2 つ目が番号なしになる。 |
| 269 | CVR | `125` → `126` | 未到達 | noSuchTarget を 126 にすると outputNotSilenced と同じ値になる。対象が無いときは親が先に noSuchTarget と比べるので、今までどおり ValueError になる (ISO-06 のテストが通る)。違いが出るのは子が出力を向け直せなかったときに ValueError と述べることだけで、その分岐はテストで通らない。 |
| 270 | CVR | `126` → `127` | 未到達 | outputNotSilenced (126) は、子が dup(1) か reopen に失敗したときだけ使われる。その分岐はテストで通らない (上の行)。 |
| 271 | CVR | `24` → `25` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。最小化の試行の上限 (プロセス内 2000、hung 24) を定める仕様 ID は無い (MIN-01 は上限があることだけを述べる)。hung の上限 24 が 25 になる。 |
| 276 | AOR | `cast[uint](data) + done.uint` → `<+ -> ->` | 等価 | write の結果が求めた長さより短い (部分書き込み) ときだけ 2 回目の呼び出しがあり、done が 0 でない。書く先はブロッキングのパイプで、POSIX はブロッキングの write が、シグナルで中断されない限り全バイトを書いて返ると定める。このプログラムはシグナルを受けないので done は常に 0 で使われる。100 万バイトの入力のテスト (RUN-01) を変異を当てて流しても通ることを手で確かめた。 |
| 276 | AOR | `size - done` → `<- -> +>` | 等価 | write の結果が求めた長さより短い (部分書き込み) ときだけ 2 回目の呼び出しがあり、done が 0 でない。書く先はブロッキングのパイプで、POSIX はブロッキングの write が、シグナルで中断されない限り全バイトを書いて返ると定める。このプログラムはシグナルを受けないので done は常に 0 で使われる。100 万バイトの入力のテスト (RUN-01) を変異を当てて流しても通ることを手で確かめた。 |
| 277 | BLR | `false` → `true` | 等価 | 書き込みが失敗するのは読み手が居なくなったときだけ。親 (answerOf) では、true を返しても続く poll がパイプの閉じを報告し、367 行の readAll が失敗して、元と同じ 375 行以降 (fkCrashed) に進む。子 (serveIfChild) では、続く sendFrame の書き込みも同じく true を返すが、次の receiveFrame が閉じたパイプで失敗して 317 行に進む。どちらも結果は同じ。 |
| 277 | ROR | `n <= 0` → `<<= -> <>` | 等価 | write は 1 バイト以上を求められて 0 を返さない (パイプでは書けるまで待つか -1)。n == 0 は起きない。 |
| 277 | RVR | `return false` → `<return default>` | 等価 | bool の既定値は false で、元の return false と同じ。 |
| 284 | AOR | `size - done` → `<- -> +>` | 等価 | 読みが部分的なとき、次の read に求める長さが残りより done だけ多くなる。相手は答え (親なら判定、子なら次の入力) を受け取るまで次の枠を送らないので、パイプにはこの枠の残りしか無く、read は残りを超えて返さない。100 万バイトの入力のテスト (RUN-01) を変異を当てて流しても通ることを手で確かめた。 |
| 291 | BLR | `false` → `true` | 等価 | 枠の長さの書き込みが失敗するのは読み手が居なくなったときだけ。親 (answerOf) では、続く poll と readAll が失敗して元と同じ fkCrashed に進む。子 (serveIfChild) では 316 行の break の代わりに輪に戻るが、次の receiveFrame が閉じたパイプで失敗して 317 行に進む。どちらも結果は同じ。 |
| 291 | RVR | `return false` → `<return default>` | 等価 | bool の既定値は false で、元の return false と同じ。 |
| 296 | BLR | `false` → `true` | 未到達 | 枠の長さが読めないのは相手がパイプを閉じたとき。子では、親が子を kill してからパイプを閉じる (stop、333 行) ので、子が読みの失敗を見ることは無い。親では、子が 2 バイトの判定を書いてから枠を書くまでの間に終わったときだけ通る。テストの対象はどれも判定の前 (対象の中) で終わるので、この行はどのテストからも実行されない。 |
| 296 | RVR | `return false` → `<return default>` | 等価 | bool の既定値は false で、元の return false と同じ。 |
| 314 | CVR | `0` → `1` | 等価 | 上と同じ。dup(1) は 3 以上か -1 を返すので、< 0 と < 1 は同じ。 |
| 314 | ROR | `answers < 0` → `<< -> <=>` | 等価 | dup(1) は空いている最小の番号を返す。子では 0・1・2 が開いている (0 は入力のパイプ) ので、成功すれば 3 以上、失敗すれば -1。0 を返すことはなく、< 0 と <= 0 は同じ。 |
| 316 | SDL | `quit(outputNotSilenced)` → `discard` | 未到達 | dup(1) か reopen が失敗したときだけ通る。失敗させる手段は公開 API の入力に無い (ファイル記述子を使い切らせるなど、プロセスの環境で作るしかない)。 |
| 325 | CVR | `0` → `1` | 未到達 | 子がこの行に来ることは無い (上の行と同じ)。終了コードを見る者も居ない。 |
| 325 | SDL | `quit(0)` → `discard` | 未到達 | 子の輪を抜けるのは、受け取りか返答が失敗したとき、つまり親がパイプを閉じたときだけ。親は子を kill してから閉じる (stop、333 行) ので、子がこの行に来ることは無い。 |
| 356 | CVR | `0` → `1` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。maxFindings (発見をいくつで止めるか、0 なら 20) を定める仕様 ID は無い。fuzzIsolated で maxFindings = 1 が既定と同じ扱いになる。 |
| 360 | BLR | `false` → `true` | 等価 | freshEdges は 400 行で読む前に、必ず answerOf の 355 行で false に置き直される。初期値は読まれない。 |
| 363 | BLR | `false` → `true` | 等価 | freshEdges が head から設定されずに残るのは hung (363 行) と crashed (381 行) の verdict だけで、どちらも wrong。400 行の reachedNew は 408 行で verdict が wrong でないときだけ使われ、そのときは 369 行で head[1] から設定されている。 |
| 367 | CVR | `1` → `2` | 許容 | 利用者が 2026-10-17 に受け入れると決めた。poll の数を 2 にしてスタックの隣を 2 つ目の pollfd として読ませる未定義の動作で、その値をテストで決められない。 |
| 373 | CVR | `2` → `3` | 等価 | head が 3 バイトになっても、読むのは 2 バイトで、使うのは head[0] と head[1] だけ。 |
| 378 | RVR | `return Verdict()` → `<return default>` | 等価 | Verdict の既定値は Verdict() で、同じ値。 |
| 379 | AOR | `head[0].int - 1` → `<- -> +>` | 等価 | head[0] + 1 は 4 以下で 5 を超えない。子は同じプログラムで、314 行で送る種類は 1 + ord(kind)。kind は judge が返す fkReported / fkRaised / fkDefect のどれかで (子の FuzzConfig() は slowAfterMs が 0 なので fkSlow にならない)、head[0] は 0〜3、head[1] は 0 か 1。元も変異後も 371 行の条件は偽で、例外は上がらず、372 行の kind も同じ。 |
| 379 | CVR | `0` → `1` | 等価 | head[0] の代わりに head[1] (0 か 1) を見ても、条件は偽のまま。子は同じプログラムで、314 行で送る種類は 1 + ord(kind)。kind は judge が返す fkReported / fkRaised / fkDefect のどれかで (子の FuzzConfig() は slowAfterMs が 0 なので fkSlow にならない)、head[0] は 0〜3、head[1] は 0 か 1。元も変異後も 371 行の条件は偽で、例外は上がらず、372 行の kind も同じ。 |
| 379 | CVR | `1` → `2` | 等価 | head[0] - 2 は 5 を超えない。子は同じプログラムで、314 行で送る種類は 1 + ord(kind)。kind は judge が返す fkReported / fkRaised / fkDefect のどれかで (子の FuzzConfig() は slowAfterMs が 0 なので fkSlow にならない)、head[0] は 0〜3、head[1] は 0 か 1。元も変異後も 371 行の条件は偽で、例外は上がらず、372 行の kind も同じ。 |
| 379 | ROR | `head[0].int - 1 > ord(high(FindingKind))` → `<> -> >=>` | 等価 | head[0] - 1 は 2 以下で 5 に届かない。子は同じプログラムで、314 行で送る種類は 1 + ord(kind)。kind は judge が返す fkReported / fkRaised / fkDefect のどれかで (子の FuzzConfig() は slowAfterMs が 0 なので fkSlow にならない)、head[0] は 0〜3、head[1] は 0 か 1。元も変異後も 371 行の条件は偽で、例外は上がらず、372 行の kind も同じ。 |
| 387 | CVR | `0` → `1` | 等価 | 383 行の 2 つ目の 0 (`< 0` の 0) を 1 にする変異。options 0 (待つ) の waitpid は子の pid (正) か -1 しか返さず、0 を返すのは WNOHANG のときだけなので、< 0 と < 1 はどの子についても同じ。 |
| 387 | ROR | `posix.waitpid(Pid(child.process.processID), status, 0) < 0` → `<< -> <=>` | 等価 | options 0 (待つ) の waitpid は、子の pid (正) か -1 しか返さない。0 を返すのは WNOHANG のときだけなので、< 0 と <= 0 はどの子についても同じ。 |
| 388 | ROR | `errno != EINTR` → `<!= -> ==>` | 未到達 | ループの本体は waitpid が失敗したときだけ通る。テストでは失敗しない。失敗するのは、待っている間にシグナルハンドラが割り込んだとき (EINTR) か、子がほかで刈り取られたとき (SIGCHLD を無視したときの ECHILD) で、どちらも呼び出し側のプロセスの設定で、テストの対象 API の入力では作れない。 |
| 388 | SDL | `raiseOSError(osLastError())` → `discard` | 未到達 | 上と同じ。raiseOSError は waitpid が EINTR 以外で失敗したときだけ通り、テストではその失敗が起きない。 |
| 407 | ROR | `seed.len > config.maxLen` → `<> -> >=>` | 等価 | seed.len == maxLen のとき seed[0 ..< maxLen] は seed そのもの。 |
| 419 | ROR | `result.findings.len < findingsWanted` → `<< -> <=>` | 許容 | 利用者が 2026-10-17 に「仕様として定めない」と決めた。maxFindings (発見をいくつで止めるか、0 なら 20) を定める仕様 ID は無い。fuzzIsolated で発見が上限より 1 つ多く残る。 |

## 利用者の決定 (2026-10-17)

| 問い | 決定 | 台帳 |
|---|---|---|
| maxFindings とその既定値 20 | 定めない | 66・193・212・348・403 行を許容 |
| 最小化の試行の上限 (2000、hung の 24) | 定めない | 67・116・120・122・265 行を許容 |
| MIN-01 の「除けるだけ除く」 | 1-minimal の意味 (どの 1 バイトを除いても、同じ発見ではなくなる)。ADR の MIN-01 に追記した | 117 行 CVR 1→2 を許容 (変異後も結果は 1-minimal で、どの 1-minimal な入力になるかは定めない) |
| 長すぎる種の切り方 | 先頭の maxLen バイトを残す。RUN-02 に追記した | 195・391 行 CVR をテストで消した |
| 保存するファイル名の形 | 定めない (CRP-01 で足りる) | 238・239・243 行を許容 |
| 変異の作り方の細部 | 定めない | 139・149・156・172・175・176・177・182 行を許容 |
| 子が起動時に通った辺の数え方 | まだどの入力も通っていない辺として数える。ISO-08 を足した | 309 行をテストで消した |
| 89 行 ROR、359 行 CVR | 受け入れる | 許容 |
| 「新しい辺に届いた入力を残す」の仕様 ID | COV-03 を足した (下の G0) | — |

## G0 (仕様の出どころ) の漏れ

- プロセス内の実行で、新しい辺に届いた入力をコーパスに残すこと。これは ADR-FZZ-0001 の「決定」と README に書かれていたが、仕様 ID が無かった (別プロセスの側には ISO-05 がある)。そのため G1 は 100% のまま、この振る舞いはどの仕様にも結ばれていなかった。1 回目の測定で、200 行 SDL と 217 行 ROR が生き残って分かった。2026-10-17 に COV-03 として足した。確かめるテストは既存の「Given no seed and a target with a branch only a non-empty input takes … twice …」で、タグ `COV-03` を付けた。
- 同じ測定で、MIN-01 の「除けるだけ」、RUN-02 の切り方、子の辺の数え方 (ISO-08) が、仕様の文から決まらないことが分かった。上の表のとおり、利用者が決めて規則に書いた。

## 追加したテスト (2 回目、2026-10-17、a8408b5d の測り直しで検出を確認)

| 仕様 ID とテスト名 (冒頭) | 確かめること |
|---|---|
| RUN-02 Given a greatest length of 4 and a seed of ten bytes, When fuzzed … | 種は先頭の 4 バイトになる (195 行 CVR を消す) |
| RUN-02 Given a greatest length of 4 and a seed of ten bytes, When fuzzed in a process of its own … | 同じことを別プロセスで (391 行 CVR を消す) |
| ISO-08 Given a target whose only branch for a non-empty input the program also ran before serveIfChild … | 起動時に通った辺に届いた入力も残る (309 行 SDL を消す。`-d:fuzzCoverage` の版) |
| MIN-01 Given a target that objects to aba, ba and b, When fuzzed from aba … | 結果が 1-minimal である。直す前は `ba` を返して落ちた (下の「未測定の変更」) |
| ISO-02 Given a target that ends its process with exit code 130 … | 終了コード 130 をコードとして述べる。直す前は落ちた (下の「未測定の変更」) |

既存の「… twice …」のテストに `COV-03` のタグを足した。テストの中身は変えていない。

## 直した 2 か所 (3 回目の測定 a8408b5d で測った)

2026-10-17 に `src/fuzz.nim` を 2 か所直した。3 回目の測定 (a8408b5d) で測り、新しい生き残りは `waitpid` の 4 件だった (383・384 行、表を参照)。

- **最小化 (`minimised`)**: 1 バイトずつ除く段を 1 度だけ回していた。この段で、手前のバイトを除いたあとに、もう通り過ぎた位置のバイトが除けるようになることがある。そのため、結果が 1-minimal にならない入力があった。手で書いた Python の写しでランダムに探して見つけ、いちばん小さい例をテストにした (対象が `aba`・`ba`・`b` にだけ理由を返すとき、`aba` から縮めると `ba` で止まる。`b` まで縮むはずである)。直したあとは、1 バイトの段を、何も除けなくなるまで繰り返す。
- **子の終わり方 (`fuzzIsolated` の crashed の判定)**: `waitForExit` は、シグナルで終わったときに 128 + シグナルの番号を返す (osproc の `exitStatusLikeShell`)。そのため、終了コードが 129 以上の子は「signal (コード - 128)」と述べられていた。テスト「… exit code 130 …」が `reason == "the process ended with code 130"` で落ちることを確かめた (Red)。直したあとは、`waitpid` の状態を `WIFSIGNALED` / `WTERMSIG` / `WEXITSTATUS` で読み分ける。発見の key も、`crashed <コードかシグナル>` になった。

台帳は 3 回目の測定で同期し直した。

## 測定で見つかったこと (1 回目)

- Nim の `quit` は、127 を超える終了コードを 127 に丸める。そのため、終了コード 128 と 130 のテストの対象は `posix.exitnow` (`_exit`) で終わる。

## 追加したテスト (1 回目、7898a910 の測り直しで検出を確認)

| 仕様 ID とテスト名 (冒頭) | 殺した変異 |
|---|---|
| FND-05 Given a limit of 1 ms and a target that takes 30 ms … | 87 行 CVR |
| IFL-01 Given a file for the input in flight whose name is one letter … | 94 行 CVR、203 行 CVR、227 行 CVR、227 行 SDL |
| FND-01 Given a target whose reason is one letter … | 98 行 CVR |
| MIN-01 Given a target that objects to inputs of an even number of bytes … | 117 行 AOR、117 行 CVR |
| MIN-01 Given a target with one reason for boom and another for q … | 124 行 LOR |
| RUN-03 Given one run and a greatest length of 1 … | 191 行 CVR、191 行 ROR、192 行 CVR、192 行 ROR |
| RUN-04 Given no seed and a target with a branch only a non-empty input takes … twice … | 200 行 SDL、217 行 ROR |
| CRP-01 Given the file an input would be saved to already holds another input of its length … | 248 行 SDL |
| RUN-01 Given a seed of a million bytes, more than a pipe holds at once … | 278 行 AOR |
| ISO-03 Given a process allowed 64 open files, When a target that never answers is fuzzed 30 times … | 335 行 SDL、361 行 SDL |
| RUN-03 Given one run, a greatest length of 1, or 1 ms to answer … | 345 行 CVR、345 行 ROR、346 行 CVR、346 行 ROR |
| ISO-06 Given one run, a greatest length of 1, or 1 ms to answer … | 347 行 CVR、347 行 ROR |
| ISO-01 Given a process allowed 64 open files, When a target with nothing wrong is fuzzed … 30 times over … | 350 行 SDL |
| ISO-02 Given a process allowed 64 open files, When a target that ends its process on every input is fuzzed 100 times … | 377 行 SDL |
| ISO-02 Given a target that ends its process with SIGTERM, with SIGHUP, or with exit code 128 … | 382 行 AOR、382 行 CVR、382 行 CVR、382 行 ROR |
| RUN-02 Given a greatest length of 8 and a seed that is longer, When fuzzed in a process of its own … | 391 行 LBR |
| ISO-05 Given no seed and a target with a branch … in a process of its own for two inputs … | 392 行 CVR、392 行 ROR、392 行 SDL、408 行 ROR |
| MIN-01 Given a long seed with boom in the middle, When fuzzed in a process of its own … | 407 行 ROR |
| COV-01 Given no seed and a target with a branch … in a process of its own for two inputs … | 410 行 SDL |

## 追加したテスト (3 回目の測定のあと、accd2f3f で測った)

| テスト | 確かめること |
|---|---|
| ISO-02 Given a target that closes its pipes and ends its process with exit code 3 a moment later … | パイプが閉じてから子が終わるまでの間に状態を読んでも、終わった時のコード (3) を述べる。子は応答に標準出力の写し (`serveIfChild` の `dup(1)`) を使うので、テストの対象は標準エラー以外の記述子をすべて閉じる |

訂正: 3 回目の測定のあと、383 行の CVR の生き残りを waitpid の options (1 つ目の 0) の変異と読み違え、このテストで消える `test_owed` とした。生き残っていたのは 2 つ目の 0 (`< 0` の 0) で、等価である。options の変異は 3 回目も 4 回目も既存のテストで killed だった。ただし既存のテストでは、子が終わり切る前に状態を読むかどうかが時の運で、このテストはそれを決まった形で確かめる (options を 1 にした変異で 10 回とも落ちることを手で確かめた)。

## 出力の向け直しの修正 (2026-10-18、5 回目の測定 8c78179f で測った)

`serveIfChild` が標準出力・標準エラーを `/dev/null` へ向ける `reopen` の結果を `discard` で捨てていた (エラーの握り潰し)。直したあとは、`dup(1)` か `reopen` に失敗した子は入力を 1 つも走らせずに終了コード 126 で終わり、親はそれを発見ではなく `IOError` として上げる (125 の「対象が無い」と同じ扱い)。失敗させる手段は公開 API の入力に無いので、この分岐の変異は未到達とした (表の 269・270・316 行)。

測ってみると、314 行の 2 つ目の `or` を `and` にする変異が生き残った。この変異では標準エラーが `/dev/null` へ向かず、対象の標準エラーが親の読まないパイプに残る。これは、標準エラーに書く対象のテストが無かったという穴だった。

## 追加したテスト (5 回目の測定のあと、b5a5870a の測り直しで検出を確認)

| テスト | 確かめること |
|---|---|
| ISO-04 Given a target that writes more to standard error than a pipe holds and returns a reason … | 標準エラーにパイプより多く (256 KiB) 書く対象でも、プロセス内の実行と同じ fkReported の発見になる。314 行の LOR の変異で 3 回とも fkHung になって落ちることを手で確かめた |
