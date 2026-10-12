## External tests of fuzzIsolated (ADR-FZZ-0001, ISO). Run twice by
## `make test`: without the coverage signal and with it.

import std/[unittest, strutils, sequtils]
import fuzz

proc clean(input: string): string {.raises: [CatchableError].} = ""

proc crashy(input: string): string {.raises: [CatchableError].} =
  if input.startsWith("C"): quit(7)                              # the process ends
  if input.startsWith("S"): cast[ptr int](1)[] = 1               # a segmentation fault
  ""

proc hangy(input: string): string {.raises: [CatchableError].} =
  if input.startsWith("H"):
    while true: discard
  ""

proc talkative(input: string): string {.raises: [CatchableError].} =
  try:
    stdout.write "noise on standard output\n"
    stdout.flushFile()
  except IOError:
    discard        # the test is that this noise does not reach the verdicts
  if "boom" in input: return "holds boom"
  if input.startsWith("!"): raise newException(ValueError, "a bang")
  if input.startsWith("L") and input[9] == 'x': return ""
  ""

proc staged(input: string): string {.raises: [CatchableError].} =
  if input.len >= 4:
    if input[0] == 'F':
      if input[1] == 'U':
        if input[2] == 'Z':
          if input[3] == 'Z': return "reached the fault"
  ""

# In the child this runs the named target and never returns.
serveIfChild({"clean": FuzzTarget(clean), "crashy": FuzzTarget(crashy), "hangy": FuzzTarget(hangy),
              "talkative": FuzzTarget(talkative), "staged": FuzzTarget(staged)})

proc config(runs: int; dictionary: seq[string] = @[]; maxLen = 32): FuzzConfig =
  FuzzConfig(runs: runs, seed: 0, maxLen: maxLen, dictionary: dictionary)

suite "a target in a process of its own":
  # SPEC: ISO-01
  test "Given a target with nothing wrong, When fuzzed in a process of its own, Then there is no finding and every input was run; and this program, not being the child, got past serveIfChild":
    let report = fuzzIsolated("clean", ["seed", ""], config(400), hangAfterMs = 2000)
    check report.findings.len == 0
    check report.runs == 400

  # SPEC: ISO-02
  test "Given a target that ends the process on inputs beginning with C, When fuzzed, Then that is a finding that names the exit code, made as small as the one letter, and the fuzzing goes on to its end":
    let report = fuzzIsolated("crashy", ["Crash here", "fine"], config(150), hangAfterMs = 2000)
    check report.runs == 150
    # Mutation may also reach the other fault of this target (an input beginning with S).
    let byCode = report.findings.filterIt("code 7" in it.reason)
    check byCode.len == 1
    check byCode[0].kind == fkCrashed
    check byCode[0].input == "C"

  # SPEC: ISO-02
  test "Given a target that faults on inputs beginning with S, When fuzzed, Then the finding names the signal":
    let report = fuzzIsolated("crashy", ["Segv", "fine"], config(60), hangAfterMs = 2000)
    let bySignal = report.findings.filterIt("signal" in it.reason)
    check bySignal.len == 1
    check bySignal[0].kind == fkCrashed
    check bySignal[0].input == "S"

  # SPEC: ISO-03
  test "Given a target that never returns on inputs beginning with H, and 150 ms to answer, When fuzzed, Then that is a finding that says so, the process is replaced, and the fuzzing goes on":
    let report = fuzzIsolated("hangy", ["Hang", "fine"], config(40), hangAfterMs = 150)
    check report.runs == 40
    check report.findings.len == 1
    check report.findings[0].kind == fkHung
    check "150 ms" in report.findings[0].reason
    check report.findings[0].input.startsWith("H")

  # SPEC: ISO-04
  test "Given a target that returns a reason, raises, and raises a defect, and that prints to standard output, When fuzzed, Then the findings are of the kinds and reasons an in-process run gives":
    let report = fuzzIsolated("talkative", ["!x", "L", "seed"], config(3000, dictionary = @["boom"]), hangAfterMs = 2000)
    var kinds: set[FindingKind]
    for finding in report.findings:
      kinds.incl finding.kind
      case finding.kind
      of fkReported:
        check finding.reason == "holds boom"
        check finding.input == "boom"
      of fkRaised: check "ValueError: a bang" in finding.reason
      of fkDefect: check "IndexDefect" in finding.reason
      else: fail()
    check kinds == {fkReported, fkRaised, fkDefect}

  # SPEC: ISO-04
  test "Given a target that reads past the end of inputs beginning with L, When fuzzed from a long seed, Then the finding's reason is the one its reduced input gives, as in an in-process run":
    let isolated = fuzzIsolated("talkative", ["Lorem"], config(100), hangAfterMs = 2000)
    let inProcess = fuzz(talkative, ["Lorem"], config(100))
    check isolated.findings.len == 1
    check isolated.findings[0].input == "L"
    check isolated.findings[0].reason == inProcess.findings[0].reason
    check "0 .. 0" in isolated.findings[0].reason       # of "L", not of "Lorem"

  # SPEC: ISO-05
  test "Given a fault behind four conditions on four bytes, When fuzzed in a process of its own with the signal, Then it is found":
    when defined(fuzzCoverage):
      let report = fuzzIsolated("staged", ["seed"], config(300_000, maxLen = 16), hangAfterMs = 2000)
      check report.coverageGuided
      check report.findings.len == 1
      check report.findings[0].input == "FUZZ"
      check report.corpusSize > 1
    else:
      skip()

  # SPEC: ISO-06
  test "Given a target that was not given to serveIfChild, or no time to answer, When fuzzed, Then it is refused":
    expect ValueError: discard fuzzIsolated("no such target", ["x"], config(5), hangAfterMs = 2000)
    expect ValueError: discard fuzzIsolated("clean", ["x"], config(5), hangAfterMs = 0)
    expect ValueError: discard fuzzIsolated("clean", ["x"], config(0), hangAfterMs = 2000)
