# G2 (変異検査): `src/nim_fuzz_inprocess/libfuzzer.nim`

- 状態: 未測定 (2026-10-18 に追加したモジュール)
- E テスト: `tests/external/test_libfuzzer.nim` (LFZ-01〜05)。テストは libFuzzer でビルドした小さなプログラムを動かすので、変異のたびにそのプログラムも作り直す。ジョブを作るときは、`testCommand` がこのテストを流せばよい。
- 次に `fuzz.nim` を測るときに、あわせてジョブを作って測る。
