## External tests of fuzzIsolated (ADR-FZZ-0001, ISO). Run twice by
## `make test`: without the coverage signal and with it.

import std/[unittest, os, strutils, sequtils]
from std/posix import kill, getpid, exitnow, SIGTERM, SIGHUP, RLimit, getrlimit, setrlimit, RLIMIT_NOFILE
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

proc sleepy(input: string): string {.raises: [CatchableError].} =
  if input.startsWith("z"): sleep(600)
  ""

var nonEmptySeen = 0

proc branchy(input: string): string {.raises: [CatchableError].} =
  if input.len > 0: inc nonEmptySeen
  ""

proc long(input: string): string {.raises: [CatchableError].} =
  if input.len > 8: "longer than 8 bytes: " & $input.len else: ""

const wholeLen = 1_000_000

proc whole(input: string): string {.raises: [CatchableError].} =
  if input.len != wholeLen or input.count('a') != wholeLen:
    return "got " & $input.len & " bytes, " & $input.count('a') & " of them a"
  ""

proc signals(input: string): string {.raises: [CatchableError].} =
  if input == "T" and kill(getpid(), SIGTERM) != 0: return "could not send SIGTERM"
  if input == "H" and kill(getpid(), SIGHUP) != 0: return "could not send SIGHUP"
  if input == "E": exitnow(128)                 # quit clamps codes above 127
  ""

proc dies(input: string): string {.raises: [CatchableError].} =
  quit(3)

proc stuck(input: string): string {.raises: [CatchableError].} =
  while true: discard

# In the child this runs the named target and never returns.
serveIfChild({"clean": FuzzTarget(clean), "crashy": FuzzTarget(crashy), "hangy": FuzzTarget(hangy),
              "talkative": FuzzTarget(talkative), "staged": FuzzTarget(staged),
              "sleepy": FuzzTarget(sleepy), "branchy": FuzzTarget(branchy), "long": FuzzTarget(long),
              "whole": FuzzTarget(whole), "signals": FuzzTarget(signals), "dies": FuzzTarget(dies),
              "stuck": FuzzTarget(stuck)})

proc config(runs: int; dictionary: seq[string] = @[]; maxLen = 32): FuzzConfig =
  FuzzConfig(runs: runs, seed: 0, maxLen: maxLen, dictionary: dictionary)

template withOpenFilesAtMost(limit: int; body: untyped) =
  ## Runs `body` in a process that may hold at most `limit` files open, so
  ## that a child whose pipes are not closed shows within a short run.
  var saved: RLimit
  check getrlimit(RLIMIT_NOFILE, saved) == 0
  var lowered = saved
  lowered.rlim_cur = limit
  check setrlimit(RLIMIT_NOFILE, lowered) == 0
  try:
    body
  finally:
    check setrlimit(RLIMIT_NOFILE, saved) == 0

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

  # SPEC: ISO-07
  test "Given a target that takes 600 ms on inputs beginning with z, and a limit of 300 ms, When fuzzed in a process of its own, Then the slow inputs are one finding of the kind an in-process run gives, not reduced, that says how long it took":
    var cfg = config(6)
    cfg.slowAfterMs = 300
    let report = fuzzIsolated("sleepy", ["zzzz", "zz"], cfg, hangAfterMs = 5000)
    check report.runs == 6
    check report.findings.len == 1
    check report.findings[0].kind == fkSlow
    check report.findings[0].input == "zzzz"
    check "ms; the limit is 300 ms" in report.findings[0].reason

  # SPEC: RUN-03, ISO-06
  test "Given one run, a greatest length of 1, or 1 ms to answer, When fuzzed in a process of its own, Then it is not refused":
    check fuzzIsolated("clean", ["xy"], config(1, maxLen = 1), hangAfterMs = 2000).runs == 1
    check fuzzIsolated("clean", ["x"], config(1), hangAfterMs = 1).runs == 1

  # SPEC: RUN-02
  test "Given a greatest length of 8 and a seed that is longer, When fuzzed in a process of its own, Then no input the target gets is longer":
    let report = fuzzIsolated("long", ["a seed far longer than eight bytes"],
                              config(200, maxLen = 8, dictionary = @["0123456789abcdef"]), hangAfterMs = 2000)
    check report.runs == 200
    check report.findings.len == 0

  # SPEC: RUN-01
  test "Given a seed of a million bytes, more than a pipe holds at once, When fuzzed in a process of its own, Then the target gets it whole":
    let report = fuzzIsolated("whole", ['a'.repeat(wholeLen)], config(1, maxLen = wholeLen), hangAfterMs = 10_000)
    check report.runs == 1
    check report.findings.len == 0

  # SPEC: ISO-05, COV-01
  test "Given no seed and a target with a branch only a non-empty input takes, When fuzzed in a process of its own for two inputs, Then both run, and with the signal the mutated input that took the branch is kept and counted":
    let report = fuzzIsolated("branchy", newSeq[string](), config(2), hangAfterMs = 2000)
    check report.runs == 2
    check report.coverageGuided == coverageAvailable
    when defined(fuzzCoverage):
      check report.corpusSize == 2
      check report.edges > 0
    else:
      check report.corpusSize == 1
      check report.edges == 0

  # SPEC: ISO-02
  test "Given a target that ends its process with SIGTERM, with SIGHUP, or with exit code 128, When fuzzed, Then each is a finding that names its signal or its code":
    let report = fuzzIsolated("signals", ["T", "H", "E"], config(3), hangAfterMs = 2000)
    let reasons = report.findings.mapIt(it.reason)
    check report.findings.allIt(it.kind == fkCrashed)
    check reasons.len == 3
    check reasons.anyIt(it.endsWith("signal 15"))
    check reasons.anyIt(it.endsWith("signal 1"))
    check reasons.anyIt(it.endsWith("code 128"))

  # SPEC: MIN-01, ISO-04
  test "Given a long seed with boom in the middle, When fuzzed in a process of its own, Then the finding's input is exactly boom, as in an in-process run":
    let seed = 'x'.repeat(60) & "boom" & 'y'.repeat(60)
    let report = fuzzIsolated("talkative", [seed], config(1, maxLen = 256), hangAfterMs = 2000)
    check report.findings.len == 1
    check report.findings[0].reason == "holds boom"
    check report.findings[0].input == "boom"

  # SPEC: ISO-02
  test "Given a process allowed 64 open files, When a target that ends its process on every input is fuzzed 100 times, Then every input is run":
    withOpenFilesAtMost(64):
      check fuzzIsolated("dies", ["x"], config(100), hangAfterMs = 2000).runs == 100

  # SPEC: ISO-03
  test "Given a process allowed 64 open files, When a target that never answers is fuzzed 30 times with 20 ms to answer, Then every input is run":
    withOpenFilesAtMost(64):
      check fuzzIsolated("stuck", ["x"], config(30), hangAfterMs = 20).runs == 30

  # SPEC: ISO-01
  test "Given a process allowed 64 open files, When a target with nothing wrong is fuzzed in a process of its own 30 times over, Then every run goes to its end":
    withOpenFilesAtMost(64):
      for _ in 0 ..< 30:
        check fuzzIsolated("clean", ["x"], config(1), hangAfterMs = 2000).runs == 1
