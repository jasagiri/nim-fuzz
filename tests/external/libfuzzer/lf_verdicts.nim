## A libFuzzer program for test_libfuzzer.nim: each kind of finding, by the
## input's first word.
import std/strutils
import fuzz/libfuzzer

proc target(input: string): string {.raises: [CatchableError].} =
  if input.startsWith("REASON"): return "accepted what it must refuse"
  if input.startsWith("RAISE"): raise newException(ValueError, "a refusal nobody caught")
  if input.startsWith("DEFECT"):
    let empty: seq[int] = @[]
    return $empty[input.len]
  if input.len >= 4 and input[0] == 'F' and input[1] == 'U' and input[2] == 'Z' and input[3] == 'Z':
    return "reached the fault"
  ""

libFuzzerTarget(target)
