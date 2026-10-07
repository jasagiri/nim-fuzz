## External tests of fuzz (ADR-FZZ-0001). Run twice by `make test`:
## without the coverage signal and with it (-d:fuzzCoverage).

import std/[unittest, os, strutils, sequtils, algorithm]
import fuzz

proc quiet(input: string): string {.raises: [CatchableError].} = ""

proc config(runs: int; seed = 0'i64; maxLen = 64; dictionary: seq[string] = @[]): FuzzConfig =
  FuzzConfig(runs: runs, seed: seed, maxLen: maxLen, dictionary: dictionary)

suite "running a target":
  # SPEC: RUN-01
  test "Given three seeds and a target with nothing wrong, When fuzzed 500 times, Then the seeds come first, in order, there is no finding, and 500 inputs were run":
    var seen: seq[string]
    let report = fuzz(proc(input: string): string {.raises: [CatchableError].} =
                        seen.add input
                        "",
                      ["alpha", "", "beta"], config(500))
    check seen[0 .. 2] == @["alpha", "", "beta"]
    check report.findings.len == 0
    check report.runs == 500
    check seen.len == 500
    check seen.toSeq.deduplicate.len > 50       # the rest are not the seeds again

  # SPEC: RUN-01
  test "Given no seed, When fuzzed, Then the empty input comes first and others follow":
    var seen: seq[string]
    discard fuzz(proc(input: string): string {.raises: [CatchableError].} =
                   seen.add input
                   "",
                 newSeq[string](), config(200))
    check seen[0] == ""
    check seen.anyIt(it.len > 0)

  # SPEC: RUN-02
  test "Given a greatest length of 8, When fuzzed, Then no input is longer, a seed that is longer is cut to it":
    var longest = 0
    discard fuzz(proc(input: string): string {.raises: [CatchableError].} =
                   longest = max(longest, input.len)
                   "",
                 ["a seed far longer than eight bytes"], config(2000, maxLen = 8, dictionary = @["0123456789abcdef"]))
    check longest == 8

  # SPEC: RUN-03
  test "Given no run, or a greatest length of 0, When fuzzed, Then it is refused":
    expect ValueError: discard fuzz(quiet, ["x"], config(0))
    expect ValueError: discard fuzz(quiet, ["x"], config(10, maxLen = 0))

  # SPEC: RUN-04
  test "Given one seed twice, When fuzzed, Then the same inputs are run in the same order; another seed runs others":
    proc inputsOf(seed: int64): seq[string] =
      var seen: seq[string]
      discard fuzz(proc(input: string): string {.raises: [CatchableError].} =
                     seen.add input
                     "",
                   ["{\"amount\":\"10\"}"], config(400, seed = seed, dictionary = @["\"", "amount"]))
      seen
    check inputsOf(3) == inputsOf(3)
    check inputsOf(3) != inputsOf(4)

suite "findings":
  # SPEC: FND-01
  test "Given a target that objects to inputs holding a word of the dictionary, When fuzzed, Then there is a finding with the target's reason, and its input holds the word":
    let report = fuzz(proc(input: string): string {.raises: [CatchableError].} =
                        if "boom" in input: "accepted an input it must refuse" else: "",
                      ["a payment", "another"], config(5000, dictionary = @["boom", "zap"]))
    check report.findings.len == 1
    check report.findings[0].reason == "accepted an input it must refuse"
    check report.findings[0].kind == fkReported
    check "boom" in report.findings[0].input

  # SPEC: FND-02
  test "Given a target that raises for an input, When fuzzed, Then the finding's reason names the exception and carries its message":
    let report = fuzz(proc(input: string): string {.raises: [CatchableError].} =
                        if input.startsWith("!"): raise newException(ValueError, "cannot begin with a bang")
                        "",
                      ["!x", "ok"], config(50))
    check report.findings.len == 1
    check report.findings[0].kind == fkRaised
    check "ValueError" in report.findings[0].reason
    check "cannot begin with a bang" in report.findings[0].reason

  # SPEC: FND-03
  test "Given a target that reads past the end of some inputs, When fuzzed, Then the defect is a finding and the fuzzing goes on to its end":
    var runs = 0
    let report = fuzz(proc(input: string): string {.raises: [CatchableError].} =
                        inc runs
                        if input.len > 0 and input[0] == 'L':
                          let claimed = 9                    # trusts a length the input does not have
                          if input[claimed] == 'x': return ""
                        "",
                      ["L", "fine"], config(300))
    check report.findings.len == 1
    check report.findings[0].kind == fkDefect
    check "IndexDefect" in report.findings[0].reason
    check runs >= 300

  # SPEC: FND-04
  test "Given a target with two things wrong, each reached often, When fuzzed, Then there are two findings, one for each reason":
    let report = fuzz(proc(input: string): string {.raises: [CatchableError].} =
                        if "boom" in input: return "first"
                        if "zap" in input: return "second"
                        "",
                      ["seed"], config(8000, dictionary = @["boom", "zap"]))
    check report.findings.mapIt(it.reason).sorted == @["first", "second"]

  # SPEC: FND-05
  test "Given a target that takes 30 ms on inputs beginning with z, and a limit of 10 ms, When fuzzed, Then the slow input is a finding that says how long it took":
    var cfg = config(20)
    cfg.slowAfterMs = 10
    let report = fuzz(proc(input: string): string {.raises: [CatchableError].} =
                        if input.startsWith("z"): sleep(30)
                        "",
                      ["z"], cfg)
    check report.findings.len == 1
    check report.findings[0].kind == fkSlow
    check "ms" in report.findings[0].reason
    check report.findings[0].input.startsWith("z")

suite "making a finding small":
  # SPEC: MIN-01
  test "Given a target that objects to inputs holding boom, When fuzzed from long seeds, Then the finding's input is exactly boom":
    let report = fuzz(proc(input: string): string {.raises: [CatchableError].} =
                        if "boom" in input: "holds boom" else: "",
                      ["{\"scheme\":\"exact\",\"network\":\"base\",\"amount\":\"10000\"}"],
                      config(5000, maxLen = 200, dictionary = @["boom"]))
    check report.findings.len == 1
    check report.findings[0].input == "boom"

  # SPEC: MIN-01
  test "Given a target that reads past the end when the input begins with L, When fuzzed from a long seed, Then the finding's input is the one letter":
    let report = fuzz(proc(input: string): string {.raises: [CatchableError].} =
                        if input.len > 0 and input[0] == 'L' and input[9] == 'x': return ""
                        "",
                      ["Lorem"], config(100))
    check report.findings[0].input == "L"

suite "the coverage signal":
  # SPEC: COV-01
  test "Given how the test was compiled, When fuzzed, Then the report says whether the signal was on, and with it on, edges were reached":
    let report = fuzz(quiet, ["x"], config(50))
    check report.coverageGuided == coverageAvailable
    when defined(fuzzCoverage):
      check coverageAvailable
      check report.edges > 0
    else:
      check not coverageAvailable
      check report.edges == 0

  # SPEC: COV-02
  test "Given a fault behind four conditions on four bytes, and no hint in the dictionary, When fuzzed with the signal, Then it is found, and the input that reaches it is the four bytes":
    proc staged(input: string): string {.raises: [CatchableError].} =
      if input.len >= 4:
        if input[0] == 'F':
          if input[1] == 'U':
            if input[2] == 'Z':
              if input[3] == 'Z': return "reached the fault"
      ""
    when defined(fuzzCoverage):
      let report = fuzz(staged, ["seed"], config(400_000, maxLen = 16))
      check report.findings.len == 1
      check report.findings[0].input == "FUZZ"
      check report.corpusSize > 1          # the steps on the way were kept
    else:
      skip()

suite "keeping inputs, and running them again":
  let dir = getTempDir() / "nim_fuzz_test_corpus"

  proc faulty(input: string): string {.raises: [CatchableError].} =
    if input == "bad": "is bad"
    elif input == "worse": raise newException(IOError, "worse")
    else: ""

  # SPEC: RPL-01
  test "Given four inputs of which two are wrong, When replayed, Then the target saw each once, and the findings are the two, with their reasons":
    var seen: seq[string]
    let findings = replay(proc(input: string): string {.raises: [CatchableError].} =
                            seen.add input
                            faulty(input),
                          ["good", "bad", "", "worse"])
    check seen == @["good", "bad", "", "worse"]
    check findings.mapIt(it.input) == @["bad", "worse"]
    check findings[0].reason == "is bad"
    check findings[1].kind == fkRaised

  # SPEC: CRP-01
  test "Given inputs with every kind of byte, When saved and loaded, Then they come back unchanged; the same input saved twice is one file":
    removeDir(dir)
    let binary = "\x00\xff\r\n\"quote\"\x7f"
    let first = saveInput(dir, binary)
    check saveInput(dir, binary) == first
    check first.endsWith(".input")       # ignore rules for compiler output drop names without an extension
    discard saveInput(dir, "")
    discard saveInput(dir, "plain")
    check loadCorpus(dir).sorted == @["", binary, "plain"].sorted
    check toSeq(walkFiles(dir / "*")).len == 3
    removeDir(dir)

  # SPEC: CRP-01
  test "Given a directory that is not there, When its corpus is loaded, Then it is an error that names it":
    try:
      discard loadCorpus("/no/such/corpus")
      fail()
    except IOError as e:
      check "/no/such/corpus" in e.msg

  # SPEC: IFL-01
  test "Given a file for the input in flight, When fuzzed, Then while the target runs the file holds the input it was given, and afterwards the file is gone":
    let path = getTempDir() / "nim_fuzz_test_in_flight"
    removeFile(path)
    var cfg = config(60)
    cfg.inFlightPath = path
    var mismatches = 0
    var checked = 0
    discard fuzz(proc(input: string): string {.raises: [CatchableError].} =
                   inc checked
                   if readFile(path) != input: inc mismatches
                   "",
                 ["one", "\x00two"], cfg)
    check checked == 60
    check mismatches == 0
    check not fileExists(path)
