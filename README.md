# nim-fuzz

プロセス内のファジング。種の入力を変異させて対象に渡し、新しいコードに届いた入力を残してさらに変異させる。見つけた入力は最小化する。

```nim
import fuzz

proc target(input: string): string {.raises: [CatchableError].} =
  # "" は問題なし。受け入れてはならない入力を受け入れたら、理由を返す。
  let header = decodePaymentPayloadHeader(input)
  if header.isOk and encodeHeader(header.value) != input: return "符号化が元に戻らない"
  ""

let report = fuzz(target, [validHeader], FuzzConfig(runs: 300_000, seed: 0, maxLen: 2048,
                                                    dictionary: @["x402Version", "\"", "{"]))
for finding in report.findings: echo finding.kind, " ", finding.reason, " ", finding.input.escape
```

- 発見になるのは、対象が理由を返した入力、例外、Defect (配列の外の参照など)、設定より遅い入力。
- `-d:fuzzCoverage --cc:clang` でコンパイルすると、新しい辺 (edge) に届いた入力がコーパスに残る。付けないと、種からの変異だけになる。1 バイトずつ条件を重ねた先の問題は、信号つきで 1 秒かからず見つかり、信号なしでは 40 万回でも見つからなかった。
- 種は固定。同じ種・同じ種コーパス・同じバイナリは、同じ入力の列を試す。
- 見つけた入力は `saveInput` で保存し、`replay` でテストから毎回流す。ファジングそのものは時間をかけて別に流す。
- 対象が落ちる・止まるとファザーも止まる。`inFlightPath` を設定すると、実行中の入力がファイルに残る。

最初の成果: nim-x402 のヘッダーの読み取りが、4 バイトの入力で `IndexDefect` を上げた (標準ライブラリの `base64.decode` の、Nim 2.2.8 までの問題。nim-lang/Nim#25530、2.2.10 で修正済み)。

仕様と、守れないものは `docs/adr/ADR-FZZ-0001-in-process-fuzzing.md`。
