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
| 追加後 (見込み) | 250 | 60 | 17 | 30 | 357 |

「追加後」は測り直した値ではない。足したテストで消える 38 件は、変異を 1 件ずつ `src/fuzz.nim` に手で当て、該当するビルド (信号なし、または `-d:fuzzCoverage`) で足したテストが落ちることを確かめた (台帳では `test_owed`、理由にテスト名)。次の測定で killed になるはず。

timeout 17 件は、変異でテストが時間内に終わらなかったもので、検出として扱い (killed と同じ)、台帳には載せない。compileError 30 件は変異後のコードがコンパイルできなかったもので、テストの穴ではない。

## 生き残った変異と理由

残り 60 件の内訳: 等価 26 件、未到達 3 件、仕様への問い 31 件。仕様への問いは、利用者の答えを待つ (答えが出るまで `nim-muter-ledger check` は通らない)。うち 89 行 ROR と 359 行 CVR は仕様の問いではなく、テストで決定的に作れない状況なので受け入れるかの判断を求めている。

| 行 | 変異子 | 元 → 変更後 | 分類 | 理由 |
|---:|---|---|---|---|
| 66 | CVR | `20` → `21` | 仕様への問い | 既定の発見の上限 20 が 21 になる。maxFindings (発見をいくつで止めるか、0 なら 20) はフィールドの doc comment にだけあり、仕様 ID が無い。maxFindings の振る舞いを仕様に足すか、定めないか。 |
| 67 | CVR | `2000` → `2001` | 仕様への問い | 最小化の試行の上限 2000 が 2001 になる。MIN-01 は上限なしに「除けるだけ除く」と述べ、試行の上限 (プロセス内 2000、hung 24) を述べていない。上限を仕様に書くか、定めないか。 |
| 89 | ROR | `took <= config.slowAfterMs` の `<= -> <` | 仕様への問い | かかった時間がちょうど slowAfterMs ミリ秒のときだけ違う (元は発見にしない、変異後は発見)。FND-05 は「より長く」と述べ、元が仕様どおり。時計で測るので、ちょうどの時間をテストで決定的に作れない。この生き残りを受け入れる (accepted) か、利用者の判断が要る。 |
| 89 | RVR | `return verdict` の `return default` | 等価 | 87 行で wrong の verdict は先に返るので、ここの verdict は wrong でない。wrong でない Verdict は judge でも answerOf (370 行) でも既定値 Verdict() そのもので、既定値を返しても同じ。 |
| 116 | CVR | `0` → `1` | 仕様への問い | 試行の数え始めが 1 になり、上限に 1 回早く届く。MIN-01 は上限なしに「除けるだけ除く」と述べ、試行の上限 (プロセス内 2000、hung 24) を述べていない。上限を仕様に書くか、定めないか。 |
| 117 | CVR | `1` → `2` | 仕様への問い | 最初に除く幅が、長さ 2〜3 の入力でも 2 になる。結果が変わるのは、2 バイトまとめて除くと同じ発見のままで、1 バイトでは変わる入力 (例: 長さが 1 でない入力に理由を返す対象と seed "ab": 元は "ab"、変異後は "")。このときは変異後の方が小さい。MIN-01 の「除けるだけ除く」は、1 バイトずつ除いてもう縮まないこと (1-minimal) を言うのか、どの部分を除いても縮まないことを言うのか。後者なら元の実装が仕様を満たさない入力がある。 |
| 118 | LOR | `size >= 1 and tries < budget` の `and -> or` | 等価 | size は 117 行で 1 以上になり、131 行の半減も 130 行で size が 1 のとき先に抜けるので 1 以上のまま。size >= 1 は常に真で、or にすると条件は常に真。tries が budget に達したあとも外側の輪は回るが、内側の輪 (120 行) が 1 度も回らず、size が 1 になって 130 行で抜ける。結果は同じ。 |
| 118 | ROR | `tries < budget` の `< -> <=` | 等価 | tries == budget で外側の輪に入っても、内側の輪 (120 行の tries < budget) は 1 度も回らず、130 行で抜けるまで size を半分にするだけ。結果は同じ。 |
| 120 | ROR | `tries < budget` の `< -> <=` | 仕様への問い | 試行が上限より 1 回多くなる。MIN-01 は上限なしに「除けるだけ除く」と述べ、試行の上限 (プロセス内 2000、hung 24) を述べていない。上限を仕様に書くか、定めないか。 |
| 122 | SDL | `inc tries` → `discard` | 仕様への問い | 試行の上限が効かなくなる (輪は、入力が縮むか at が減るので上限なしでも終わる)。MIN-01 は上限なしに「除けるだけ除く」と述べ、試行の上限 (プロセス内 2000、hung 24) を述べていない。上限を仕様に書くか、定めないか。 |
| 139 | CVR | `1` → `2` | 仕様への問い | 変異の種類を選ぶ幅が 1 狭くなり、辞書が無いと「端の数への差し替え」、辞書があると「辞書の語の上書き」が選ばれなくなる。どの仕様 ID も変異の作り方 (種類・幅・選ぶ確率) を定めていない (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も同じ種は同じ列を作る)。変異の作り方を仕様に書くか、定めないか。 |
| 149 | CVR | `7` → `8` | 仕様への問い | 「一続きを除く」の長さの上限が 8 バイトから 9 バイトになる。どの仕様 ID も変異の作り方 (種類・幅・選ぶ確率) を定めていない (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も同じ種は同じ列を作る)。変異の作り方を仕様に書くか、定めないか。 |
| 156 | CVR | `1` → `2` | 仕様への問い | 「一続きを繰り返す」で末尾の 1 バイトが対象から外れる。どの仕様 ID も変異の作り方 (種類・幅・選ぶ確率) を定めていない (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も同じ種は同じ列を作る)。変異の作り方を仕様に書くか、定めないか。 |
| 156 | LBR | `at .. min(result.len - 1, at + rng.rand(15))` の `.. -> ..<` | 仕様への問い | 「一続きを繰り返す」の長さが 1 バイト短くなる (空になることもある)。どの仕様 ID も変異の作り方 (種類・幅・選ぶ確率) を定めていない (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も同じ種は同じ列を作る)。変異の作り方を仕様に書くか、定めないか。 |
| 172 | CVR | `0` → `1` | 仕様への問い | 数字の並びが先頭のバイトから始まるとき、差し替えずに数を挿入する。どの仕様 ID も変異の作り方 (種類・幅・選ぶ確率) を定めていない (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も同じ種は同じ列を作る)。変異の作り方を仕様に書くか、定めないか。 |
| 172 | ROR | `first < 0` の `< -> <=` | 仕様への問い | 数字の並びが先頭のバイトから始まるとき、差し替えずに数を挿入する。どの仕様 ID も変異の作り方 (種類・幅・選ぶ確率) を定めていない (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も同じ種は同じ列を作る)。変異の作り方を仕様に書くか、定めないか。 |
| 175 | CVR | `1` → `2` | 仕様への問い | 数字の並びの終わりを 1 つ手前で止め、末尾まで続く並びの最後の数字が残る。どの仕様 ID も変異の作り方 (種類・幅・選ぶ確率) を定めていない (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も同じ種は同じ列を作る)。変異の作り方を仕様に書くか、定めないか。 |
| 176 | LBR | `0 ..< first` の `..< -> ..` | 仕様への問い | 差し替えのとき、並びの最初の数字が数の前に残る。どの仕様 ID も変異の作り方 (種類・幅・選ぶ確率) を定めていない (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も同じ種は同じ列を作る)。変異の作り方を仕様に書くか、定めないか。 |
| 177 | CVR | `9` → `10` | 仕様への問い | 辞書の語の「挿入」と「上書き」が、選ばれる番号で入れ替わる (どちらも 1/11)。どの仕様 ID も変異の作り方 (種類・幅・選ぶ確率) を定めていない (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も同じ種は同じ列を作る)。変異の作り方を仕様に書くか、定めないか。 |
| 182 | CVR | `1` → `2` | 仕様への問い | 辞書の語で上書きしたあとの残りから末尾の 1 バイトが落ちる (^1 → ^2)。どの仕様 ID も変異の作り方 (種類・幅・選ぶ確率) を定めていない (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も同じ種は同じ列を作る)。変異の作り方を仕様に書くか、定めないか。 |
| 182 | LBR | `at + word.len .. ^1` の `.. -> ..<` | 仕様への問い | 辞書の語で上書きしたあとの残りから末尾の 1 バイトが落ちる。どの仕様 ID も変異の作り方 (種類・幅・選ぶ確率) を定めていない (RUN-04 は同じ種が同じ列を作ることだけを述べ、変異後も同じ種は同じ列を作る)。変異の作り方を仕様に書くか、定めないか。 |
| 182 | ROR | `at + word.len < result.len` の `< -> <=` | 等価 | at + word.len == result.len のとき、変異後の result[result.len .. ^1] は空文字列で、元の else の "" と同じ。 |
| 183 | ROR | `result.len > config.maxLen` の `> -> >=` | 等価 | result.len == maxLen のとき setLen(maxLen) は何も変えない。 |
| 193 | CVR | `0` → `1` | 仕様への問い | maxFindings = 1 が「既定 (20)」と同じ扱いになる。maxFindings (発見をいくつで止めるか、0 なら 20) はフィールドの doc comment にだけあり、仕様 ID が無い。maxFindings の振る舞いを仕様に足すか、定めないか。 |
| 195 | CVR | `0` → `1` | 仕様への問い | 長すぎる種が、先頭の maxLen バイトでなく 2 バイト目からの maxLen - 1 バイトに切られる。RUN-02 は長さが maxLen を超えないことだけを述べ、長すぎる種を切ったあとの中身を述べていない。「先頭の maxLen バイトを残す」を仕様に足すか、定めないか。 |
| 195 | ROR | `seed.len > config.maxLen` の `> -> >=` | 等価 | seed.len == maxLen のとき seed[0 ..< maxLen] は seed そのもの。 |
| 203 | ROR | `config.inFlightPath.len > 0` の `> -> >=` | 等価 | inFlightPath が空のとき removeFile("") が呼ばれる。unlink("") は ENOENT で失敗し、removeFile (tryRemoveFile) は ENOENT を誤りにしないので、何も起きない。 |
| 212 | ROR | `result.findings.len < findingsWanted` の `< -> <=` | 仕様への問い | 発見が上限より 1 つ多く残る。maxFindings (発見をいくつで止めるか、0 なら 20) はフィールドの doc comment にだけあり、仕様 ID が無い。maxFindings の振る舞いを仕様に足すか、定めないか。 |
| 227 | ROR | `config.inFlightPath.len > 0` の `> -> >=` | 等価 | inFlightPath が空のとき removeFile("") が呼ばれる。unlink("") は ENOENT で失敗し、removeFile (tryRemoveFile) は ENOENT を誤りにしないので、何も起きない。 |
| 238 | CVR | `16` → `17` | 仕様への問い | 名前の 16 進の桁が 17 桁 (先頭に 0) になる。CRP-01 は「同じ入力は同じ名前」「.input で終わる」だけを述べ、変異後もこの 2 つは保たれる (名前の形だけが変わる)。名前の形 (16 桁の 16 進 - 長さ [- 番号] .input) を仕様に書くか、定めないか。 |
| 239 | CVR | `0` → `1` | 仕様への問い | 最初の名前から「-1」が付く。CRP-01 は「同じ入力は同じ名前」「.input で終わる」だけを述べ、変異後もこの 2 つは保たれる (名前の形だけが変わる)。名前の形 (16 桁の 16 進 - 長さ [- 番号] .input) を仕様に書くか、定めないか。 |
| 243 | CVR | `0` → `1` | 仕様への問い | 最初の名前に「-0」が付き、2 つ目が番号なしになる。CRP-01 は「同じ入力は同じ名前」「.input で終わる」だけを述べ、変異後もこの 2 つは保たれる (名前の形だけが変わる)。名前の形 (16 桁の 16 進 - 長さ [- 番号] .input) を仕様に書くか、定めないか。 |
| 243 | ROR | `attempt == 0` の `== -> !=` | 仕様への問い | 最初の名前に「-0」が付き、2 つ目が番号なしになる。CRP-01 は「同じ入力は同じ名前」「.input で終わる」だけを述べ、変異後もこの 2 つは保たれる (名前の形だけが変わる)。名前の形 (16 桁の 16 進 - 長さ [- 番号] .input) を仕様に書くか、定めないか。 |
| 265 | CVR | `24` → `25` | 仕様への問い | hung の発見の最小化の上限 24 が 25 になる。MIN-01 は上限なしに「除けるだけ除く」と述べ、試行の上限 (プロセス内 2000、hung 24) を述べていない。上限を仕様に書くか、定めないか。 |
| 270 | AOR | `cast[uint](data) + done.uint` の `+ -> -` | 等価 | write の結果が求めた長さより短い (部分書き込み) ときだけ 2 回目の呼び出しがあり、done が 0 でない。書く先はブロッキングのパイプで、POSIX はブロッキングの write が、シグナルで中断されない限り全バイトを書いて返ると定める。このプログラムはシグナルを受けないので done は常に 0 で使われる。100 万バイトの入力のテスト (RUN-01) を変異を当てて流しても通ることを手で確かめた。 |
| 270 | AOR | `size - done` の `- -> +` | 等価 | write の結果が求めた長さより短い (部分書き込み) ときだけ 2 回目の呼び出しがあり、done が 0 でない。書く先はブロッキングのパイプで、POSIX はブロッキングの write が、シグナルで中断されない限り全バイトを書いて返ると定める。このプログラムはシグナルを受けないので done は常に 0 で使われる。100 万バイトの入力のテスト (RUN-01) を変異を当てて流しても通ることを手で確かめた。 |
| 271 | BLR | `false` → `true` | 等価 | 書き込みが失敗するのは読み手が居なくなったときだけ。親 (answerOf) では、true を返しても続く poll がパイプの閉じを報告し、367 行の readAll が失敗して、元と同じ 375 行以降 (fkCrashed) に進む。子 (serveIfChild) では、続く sendFrame の書き込みも同じく true を返すが、次の receiveFrame が閉じたパイプで失敗して 317 行に進む。どちらも結果は同じ。 |
| 271 | ROR | `n <= 0` の `<= -> <` | 等価 | write は 1 バイト以上を求められて 0 を返さない (パイプでは書けるまで待つか -1)。n == 0 は起きない。 |
| 271 | RVR | `return false` の `return default` | 等価 | bool の既定値は false で、元の return false と同じ。 |
| 278 | AOR | `size - done` の `- -> +` | 等価 | 読みが部分的なとき、次の read に求める長さが残りより done だけ多くなる。相手は答え (親なら判定、子なら次の入力) を受け取るまで次の枠を送らないので、パイプにはこの枠の残りしか無く、read は残りを超えて返さない。100 万バイトの入力のテスト (RUN-01) を変異を当てて流しても通ることを手で確かめた。 |
| 285 | BLR | `false` → `true` | 等価 | 枠の長さの書き込みが失敗するのは読み手が居なくなったときだけ。親 (answerOf) では、続く poll と readAll が失敗して元と同じ fkCrashed に進む。子 (serveIfChild) では 316 行の break の代わりに輪に戻るが、次の receiveFrame が閉じたパイプで失敗して 317 行に進む。どちらも結果は同じ。 |
| 285 | RVR | `return false` の `return default` | 等価 | bool の既定値は false で、元の return false と同じ。 |
| 290 | BLR | `false` → `true` | 未到達 | 枠の長さが読めないのは相手がパイプを閉じたとき。子では、親が子を kill してからパイプを閉じる (stop、333 行) ので、子が読みの失敗を見ることは無い。親では、子が 2 バイトの判定を書いてから枠を書くまでの間に終わったときだけ通る。テストの対象はどれも判定の前 (対象の中) で終わるので、この行はどのテストからも実行されない。 |
| 290 | RVR | `return false` の `return default` | 等価 | bool の既定値は false で、元の return false と同じ。 |
| 309 | SDL | `fuzzResetEdges()` → `discard` | 仕様への問い | 子が起動してから serveIfChild に入るまでに通った辺 (モジュールの初期化など) が、どの入力も通っていないのに「既に通った」と数えられ、入力がその辺を通っても残らない。ISO-05 も README も「新しい辺」が何に対して新しいかを述べていない。「どの入力もまだ通っていない辺」と定めるか (定めるなら、起動時に通る辺を対象も通る E テストを足す)、定めないか。 |
| 317 | CVR | `0` → `1` | 未到達 | 子がこの行に来ることは無い (上の行と同じ)。終了コードを見る者も居ない。 |
| 317 | SDL | `quit(0)` → `discard` | 未到達 | 子の輪を抜けるのは、受け取りか返答が失敗したとき、つまり親がパイプを閉じたときだけ。親は子を kill してから閉じる (stop、333 行) ので、子がこの行に来ることは無い。 |
| 348 | CVR | `0` → `1` | 仕様への問い | fuzzIsolated で maxFindings = 1 が既定 (20) と同じ扱いになる。maxFindings (発見をいくつで止めるか、0 なら 20) はフィールドの doc comment にだけあり、仕様 ID が無い。maxFindings の振る舞いを仕様に足すか、定めないか。 |
| 352 | BLR | `false` → `true` | 等価 | freshEdges は 400 行で読む前に、必ず answerOf の 355 行で false に置き直される。初期値は読まれない。 |
| 355 | BLR | `false` → `true` | 等価 | freshEdges が head から設定されずに残るのは hung (363 行) と crashed (381 行) の verdict だけで、どちらも wrong。400 行の reachedNew は 408 行で verdict が wrong でないときだけ使われ、そのときは 369 行で head[1] から設定されている。 |
| 359 | CVR | `1` → `2` | 仕様への問い | poll に pollfd を 1 つしか渡さないのに数を 2 にし、スタックの隣の値を 2 つ目の pollfd として読ませる (未定義の動作)。隣の値によって hung の判定が壊れ得るが、テストでその値を決められない。この生き残りを受け入れる (accepted) か、利用者の判断が要る。 |
| 365 | CVR | `2` → `3` | 等価 | head が 3 バイトになっても、読むのは 2 バイトで、使うのは head[0] と head[1] だけ。 |
| 370 | RVR | `return Verdict()` の `return default` | 等価 | Verdict の既定値は Verdict() で、同じ値。 |
| 371 | AOR | `head[0].int - 1` の `- -> +` | 等価 | head[0] + 1 は 4 以下で 5 を超えない。子は同じプログラムで、314 行で送る種類は 1 + ord(kind)。kind は judge が返す fkReported / fkRaised / fkDefect のどれかで (子の FuzzConfig() は slowAfterMs が 0 なので fkSlow にならない)、head[0] は 0〜3、head[1] は 0 か 1。元も変異後も 371 行の条件は偽で、例外は上がらず、372 行の kind も同じ。 |
| 371 | CVR | `0` → `1` | 等価 | head[0] の代わりに head[1] (0 か 1) を見ても、条件は偽のまま。子は同じプログラムで、314 行で送る種類は 1 + ord(kind)。kind は judge が返す fkReported / fkRaised / fkDefect のどれかで (子の FuzzConfig() は slowAfterMs が 0 なので fkSlow にならない)、head[0] は 0〜3、head[1] は 0 か 1。元も変異後も 371 行の条件は偽で、例外は上がらず、372 行の kind も同じ。 |
| 371 | CVR | `1` → `2` | 等価 | head[0] - 2 は 5 を超えない。子は同じプログラムで、314 行で送る種類は 1 + ord(kind)。kind は judge が返す fkReported / fkRaised / fkDefect のどれかで (子の FuzzConfig() は slowAfterMs が 0 なので fkSlow にならない)、head[0] は 0〜3、head[1] は 0 か 1。元も変異後も 371 行の条件は偽で、例外は上がらず、372 行の kind も同じ。 |
| 371 | ROR | `head[0].int - 1 > ord(high(FindingKind))` の `> -> >=` | 等価 | head[0] - 1 は 2 以下で 5 に届かない。子は同じプログラムで、314 行で送る種類は 1 + ord(kind)。kind は judge が返す fkReported / fkRaised / fkDefect のどれかで (子の FuzzConfig() は slowAfterMs が 0 なので fkSlow にならない)、head[0] は 0〜3、head[1] は 0 か 1。元も変異後も 371 行の条件は偽で、例外は上がらず、372 行の kind も同じ。 |
| 391 | CVR | `0` → `1` | 仕様への問い | fuzzIsolated で、長すぎる種が 2 バイト目からの maxLen - 1 バイトに切られる。RUN-02 は長さが maxLen を超えないことだけを述べ、長すぎる種を切ったあとの中身を述べていない。「先頭の maxLen バイトを残す」を仕様に足すか、定めないか。 |
| 391 | ROR | `seed.len > config.maxLen` の `> -> >=` | 等価 | seed.len == maxLen のとき seed[0 ..< maxLen] は seed そのもの。 |
| 403 | ROR | `result.findings.len < findingsWanted` の `< -> <=` | 仕様への問い | fuzzIsolated で発見が上限より 1 つ多く残る。maxFindings (発見をいくつで止めるか、0 なら 20) はフィールドの doc comment にだけあり、仕様 ID が無い。maxFindings の振る舞いを仕様に足すか、定めないか。 |

## 追加したテスト

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

## 測定で見つかったこと

- 子の終わり方の読み分け (382 行): `waitForExit` は、シグナルで終わったときに 128 + シグナルの番号を返す (`exitStatusLikeShell`)。このため、子が終了コード 129 以上で終わると、理由は「signal (コード - 128)」になる (例: `_exit(130)` は「signal 2」。コードからの推論で、テストでは確かめていない)。ISO-02 の「そのコードかシグナルを述べる」に反する入力がある。足したテストは、この区別が付く 128 (コード) と SIGTERM・SIGHUP (シグナル) だけを確かめる。直すかは別に決める。
- Nim の `quit` は 127 を超える終了コードを 127 に丸める。終了コード 128 のテストの対象は `posix.exitnow` (`_exit`) で終わる。
- プロセス内の実行で「新しい辺に届いた入力をコーパスに残す」ことは、ADR-FZZ-0001 の「決定」と README にはあるが、仕様 ID が無い (別プロセスの側は ISO-05)。足したテストは RUN-04 (2 度の実行が同じに振る舞う) として書いた。COV に仕様 ID を足すかは利用者に問う。
