## Fuzzing in-process (ADR-FZZ-0001).
##
## A target takes an input and says what is wrong with how it was handled:
## "" for nothing. The fuzzer runs the seed corpus, then inputs mutated
## from it; an input for which the target returns a reason, raises, raises
## a defect, or takes too long is a finding, made as small as it can be
## with the same reason.
##
## Compiled with `-d:fuzzCoverage` (clang), the program is instrumented
## and an input that reaches an edge no input reached before is kept and
## mutated further. Without it the fuzzer mutates the seeds alone.
##
## The target runs in this process: one that crashes the process or never
## returns takes the fuzzer with it. `inFlightPath` keeps the input being
## run in a file, so that it is not lost.

import std/[random, monotimes, times, os, hashes, strutils, sets]

when defined(fuzzCoverage):
  {.passC: "-fsanitize-coverage=trace-pc-guard".}
  const covrtPath = currentSourcePath().parentDir / "fuzz" / "covrt.c"
  {.compile(covrtPath, "-fno-sanitize-coverage=trace-pc-guard").}
  proc fuzzFreshEdges(): uint64 {.importc: "fuzz_fresh_edges", cdecl.}
  proc fuzzResetEdges() {.importc: "fuzz_reset_edges", cdecl.}
  const coverageAvailable* = true
    ## Whether this program was compiled with the coverage signal.
else:
  proc fuzzFreshEdges(): uint64 = 0
  proc fuzzResetEdges() = discard
  const coverageAvailable* = false

type
  FuzzTarget* = proc(input: string): string {.raises: [CatchableError].}
    ## What is wrong with how `input` was handled; "" for nothing.

  FuzzConfig* = object
    runs*: int                 ## inputs to run, the seeds among them
    seed*: int64               ## the same seed runs the same inputs
    maxLen*: int               ## no input is longer
    dictionary*: seq[string]   ## words of the format, put into inputs whole
    slowAfterMs*: int          ## an input that takes longer is a finding; 0 for no limit
    inFlightPath*: string      ## a file that holds the input being run; "" for none
    maxFindings*: int          ## stop keeping findings after so many; 0 for the default of 20

  FindingKind* = enum
    fkReported   ## the target returned a reason
    fkRaised     ## the target raised
    fkDefect     ## the target raised a defect (an index out of range, an overflow)
    fkSlow       ## the target took longer than the limit

  Finding* = object
    kind*: FindingKind
    input*: string
    reason*: string

  FuzzReport* = object
    runs*: int
    findings*: seq[Finding]
    coverageGuided*: bool      ## whether inputs were kept for the edges they reached
    edges*: int                ## edges reached; 0 without the signal
    corpusSize*: int           ## the seeds and the inputs kept

const
  defaultMaxFindings = 20
  minimiseBudget = 2000
  interestingBytes = ['\x00', '\xff', '\x7f', '\x80', ' ', '"', '\'', '\\', '/', '{', '}', '[', ']',
                      ':', ',', '\n', '\r', '%', '=', '&', '-', '0', '9', 'x']
  interestingNumbers = ["0", "-1", "1", "255", "256", "65535", "65536", "2147483647", "2147483648",
                        "4294967295", "4294967296", "9223372036854775807", "9223372036854775808",
                        "18446744073709551615", "18446744073709551616",
                        "115792089237316195423570985008687907853269984665640564039457584007913129639935",
                        "1e309", "00", "0x10"]

# ─── running one input ──────────────────────────────────────────────────────

type Verdict = object
  wrong: bool
  kind: FindingKind
  reason: string
  key: string        ## two findings with one key are one finding

proc judge(target: FuzzTarget; input: string; config: FuzzConfig): Verdict {.raises: [IOError].} =
  if config.inFlightPath.len > 0: writeFile(config.inFlightPath, input)
  let started = getMonoTime()
  try:
    let reason = target(input)
    if reason.len > 0:
      result = Verdict(wrong: true, kind: fkReported, reason: reason, key: "reported " & reason)
  except CatchableError as e:
    let reason = $e.name & ": " & e.msg
    result = Verdict(wrong: true, kind: fkRaised, reason: reason, key: "raised " & reason)
  except Defect as e:
    # Not swallowed: a defect is what the fuzzer is looking for.
    result = Verdict(wrong: true, kind: fkDefect, reason: $e.name & ": " & e.msg, key: "defect " & $e.name)
  if not result.wrong and config.slowAfterMs > 0:
    let took = (getMonoTime() - started).inMilliseconds
    if took > config.slowAfterMs:
      result = Verdict(wrong: true, kind: fkSlow, key: "slow",
                       reason: "took " & $took & " ms; the limit is " & $config.slowAfterMs & " ms")

proc minimised(target: FuzzTarget; input: string; verdict: Verdict; config: FuzzConfig): Finding
              {.raises: [IOError].} =
  ## `input` with every stretch taken out that can go while the finding
  ## stays the same finding.
  result = Finding(kind: verdict.kind, input: input, reason: verdict.reason)
  if verdict.kind == fkSlow: return       # each try would take as long again
  var tries = 0
  var size = max(1, result.input.len div 2)
  while size >= 1 and tries < minimiseBudget:
    var at = result.input.len - size
    while at >= 0 and tries < minimiseBudget:
      let candidate = result.input[0 ..< at] & result.input[at + size .. ^1]
      inc tries
      let again = judge(target, candidate, config)
      if again.wrong and again.key == verdict.key:
        result.input = candidate
        result.reason = again.reason
        at = min(at, result.input.len - size)
      else:
        dec at
    if size == 1: break
    size = size div 2

# ─── mutation ───────────────────────────────────────────────────────────────

proc mutated(rng: var Rand; base: string; pool: seq[string]; config: FuzzConfig): string {.raises: [].} =
  result = base
  for step in 0 .. rng.rand(3):
    let kinds = if config.dictionary.len > 0: 11 else: 9
    case (if result.len == 0: 4 else: rng.rand(kinds - 1))
    of 0:   # flip a bit
      let at = rng.rand(result.len - 1)
      result[at] = chr(ord(result[at]) xor (1 shl rng.rand(7)))
    of 1:   # any byte
      result[rng.rand(result.len - 1)] = chr(rng.rand(255))
    of 2:   # a byte formats care about
      result[rng.rand(result.len - 1)] = interestingBytes[rng.rand(interestingBytes.len - 1)]
    of 3:   # take a stretch out
      let at = rng.rand(result.len - 1)
      result.delete(at .. min(result.len - 1, at + rng.rand(7)))
    of 4:   # put bytes in
      var added = ""
      for i in 0 .. rng.rand(3): added.add chr(rng.rand(255))
      result.insert(added, rng.rand(result.len))
    of 5:   # say a stretch twice
      let at = rng.rand(result.len - 1)
      let stretch = result[at .. min(result.len - 1, at + rng.rand(15))]
      result.insert(stretch, at)
    of 6:   # the head of this one, the tail of another
      let other = pool[rng.rand(pool.len - 1)]
      if other.len > 0:
        result = result[0 ..< rng.rand(result.len)] & other[rng.rand(other.len - 1) .. ^1]
    of 7:   # cut it short
      result.setLen(rng.rand(result.len))
    of 8:   # a number at an edge, in place of a run of digits or anywhere
      let number = interestingNumbers[rng.rand(interestingNumbers.len - 1)]
      var at = rng.rand(result.len - 1)
      var first = -1
      for i in at ..< result.len:
        if result[i] in Digits:
          first = i
          break
      if first < 0: result.insert(number, at)
      else:
        var last = first
        while last + 1 < result.len and result[last + 1] in Digits: inc last
        result = result[0 ..< first] & number & result[last + 1 .. ^1]
    of 9:   # a word of the format, put in
      result.insert(config.dictionary[rng.rand(config.dictionary.len - 1)], rng.rand(result.len))
    else:   # a word of the format, written over what is there
      let word = config.dictionary[rng.rand(config.dictionary.len - 1)]
      let at = rng.rand(result.len - 1)
      result = result[0 ..< at] & word & (if at + word.len < result.len: result[at + word.len .. ^1] else: "")
  if result.len > config.maxLen: result.setLen(config.maxLen)

# ─── the fuzzer ─────────────────────────────────────────────────────────────

proc fuzz*(target: FuzzTarget; seeds: openArray[string]; config: FuzzConfig): FuzzReport
          {.raises: [ValueError, IOError, OSError].} =
  ## Runs `target` on the seeds, in order, and then on inputs mutated from
  ## them, `config.runs` inputs in all.
  if config.runs < 1: raise newException(ValueError, "a fuzzing run is of at least one input")
  if config.maxLen < 1: raise newException(ValueError, "inputs are of at least one byte at most")
  let findingsWanted = if config.maxFindings > 0: config.maxFindings else: defaultMaxFindings
  var pool: seq[string]
  for seed in seeds: pool.add (if seed.len > config.maxLen: seed[0 ..< config.maxLen] else: seed)
  if pool.len == 0: pool.add ""
  let seedCount = pool.len
  var rng = initRand(config.seed)
  var found: HashSet[string]
  fuzzResetEdges()
  result.coverageGuided = coverageAvailable
  defer:
    if config.inFlightPath.len > 0: removeFile(config.inFlightPath)

  for run in 0 ..< config.runs:
    let input = if run < seedCount: pool[run] else: mutated(rng, pool[rng.rand(pool.len - 1)], pool, config)
    let before = fuzzFreshEdges()
    let verdict = judge(target, input, config)
    let reachedNew = fuzzFreshEdges() > before
    inc result.runs
    if verdict.wrong:
      if verdict.key notin found and result.findings.len < findingsWanted:
        found.incl verdict.key
        result.findings.add minimised(target, input, verdict, config)
    elif reachedNew and run >= seedCount:
      pool.add input       # it reached code no input reached before: mutate from it too
  result.edges = fuzzFreshEdges().int
  result.corpusSize = pool.len

proc replay*(target: FuzzTarget; inputs: openArray[string]; config = FuzzConfig()): seq[Finding]
            {.raises: [IOError, OSError].} =
  ## Runs `target` once on each of `inputs` and returns what went wrong:
  ## for a test that runs the inputs a fuzzing run found, every time.
  defer:
    if config.inFlightPath.len > 0: removeFile(config.inFlightPath)
  for input in inputs:
    let verdict = judge(target, input, config)
    if verdict.wrong: result.add Finding(kind: verdict.kind, input: input, reason: verdict.reason)

# ─── inputs as files ────────────────────────────────────────────────────────

proc saveInput*(dir, input: string): string {.raises: [IOError, OSError].} =
  ## Saves `input` under `dir`, byte for byte, and returns the file's path.
  ## The same input has the same name.
  createDir(dir)
  let stem = toHex(cast[uint64](hash(input)), 16).toLowerAscii & "-" & $input.len
  var attempt = 0
  while true:
    # ".input": a name with no extension is what ignore rules written for
    # compiler output throw away.
    result = dir / ((if attempt == 0: stem else: stem & "-" & $attempt) & ".input")
    if not fileExists(result):
      writeFile(result, input)
      return
    if readFile(result) == input: return
    inc attempt          # another input with this hash and length

proc loadCorpus*(dir: string): seq[string] {.raises: [IOError, OSError].} =
  ## Every input saved under `dir`.
  if not dirExists(dir): raise newException(IOError, "no corpus at " & dir)
  for path in walkFiles(dir / "*"): result.add readFile(path)
