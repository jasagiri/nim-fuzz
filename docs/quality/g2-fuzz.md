# G2 変異検出の記録 — fuzz

**対象**: `src/fuzz.nim` **E テスト**: `tests/external/test_fuzz.nim` と `tests/external/test_fuzz_isolated.nim` (どちらも信号なしと `-d:fuzzCoverage` の 2 通りで流す。ジョブは `tests/mutation/fuzz.json`)

**未測定** (2026-10-07 に作った)。push の前に測り、生き残りを ADR-MUTER-0004 §3.3 の 4 種類に分けて理由を書く。
