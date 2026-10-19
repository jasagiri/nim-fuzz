## A libFuzzer program for test_libfuzzer.nim: the target reads a global that
## the module's initialization fills.
import std/tables
import nim_fuzz_inprocess/libfuzzer

let known = {"a": 1, "b": 2}.toTable

proc target(input: string): string {.raises: [CatchableError].} =
  if known.len != 2: return "the module was not initialized"
  ""

libFuzzerTarget(target)
