## External tests of the libFuzzer entrance (ADR-FZZ-0001, LFZ). Each test
## builds a program under tests/external/libfuzzer with a clang that has the
## libFuzzer runtime and runs it as libFuzzer would.
##
## The clang is $NIM_FUZZ_CLANG, else Homebrew's LLVM. Without one, the tests
## are skipped and say so: Apple's clang has no libFuzzer runtime.

import std/[unittest, os, osproc, strutils]

let root = currentSourcePath().parentDir
let work = getTempDir() / ("nim_fuzz_libfuzzer_" & $getCurrentProcessId())
let clang = getEnv("NIM_FUZZ_CLANG", "/opt/homebrew/opt/llvm/bin/clang")

proc build(program: string): string =
  ## The path of `program` built for libFuzzer with AddressSanitizer.
  result = work / program
  let (output, code) = execCmdEx("nim c --hints:off --warnings:off --cc:clang" &
    " --clang.exe:" & quoteShell(clang) & " --clang.linkerexe:" & quoteShell(clang) &
    " --noMain --panics:on -d:useMalloc -d:noSignalHandler" &
    " --passC:-fsanitize=fuzzer,address --passL:-fsanitize=fuzzer,address" &
    " --path:" & quoteShell(root.parentDir.parentDir / "src") &
    " --nimcache:" & quoteShell(work / "nc" / program) &
    " -o:" & quoteShell(result) & " " & quoteShell(root / "libfuzzer" / program & ".nim"))
  doAssert code == 0, output

proc runOn(binary, input: string): tuple[output: string, code: int] =
  ## libFuzzer runs the files it is given once each, without fuzzing.
  let file = work / "input"
  writeFile(file, input)
  let ran = execCmdEx(quoteShell(binary) & " -artifact_prefix=" & quoteShell(work & "/") & " " &
                      quoteShell(file))
  (ran.output, ran.exitCode)

if not fileExists(clang):
  echo "SKIP: no clang with the libFuzzer runtime at ", clang, " (set NIM_FUZZ_CLANG)"
  quit(0)

createDir(work)
let verdicts = build("lf_verdicts")
let init = build("lf_init")

suite "the libFuzzer entrance":
  test "Given a target that returns a reason, When libFuzzer runs that input, Then it is a finding and the reason is shown":
    # SPEC: LFZ-01
    let (output, code) = runOn(verdicts, "REASON here")
    check code != 0
    check "nim-fuzz finding: accepted what it must refuse" in output

  test "Given a target that raises, When libFuzzer runs that input, Then it is a finding naming the exception":
    # SPEC: LFZ-02
    let (output, code) = runOn(verdicts, "RAISE now")
    check code != 0
    check "ValueError" in output
    check "a refusal nobody caught" in output

  test "Given a target that indexes out of range, When libFuzzer runs that input, Then it is a finding":
    # SPEC: LFZ-03
    let (output, code) = runOn(verdicts, "DEFECT")
    check code != 0
    check "IndexDefect" in output

  test "Given a target reading a global, When libFuzzer runs, Then the module was initialized first":
    # SPEC: LFZ-04
    let (output, code) = runOn(init, "anything")
    if code != 0: echo output
    check code == 0

  test "Given a fault four comparisons deep, When libFuzzer fuzzes from a seed, Then it finds the fault and writes the input":
    # SPEC: LFZ-01, LFZ-05
    let corpus = work / "corpus"
    createDir(corpus)
    writeFile(corpus / "seed", "FUZ")
    let (output, code) = execCmdEx(quoteShell(verdicts) & " -max_total_time=60 -seed=1" &
      " -artifact_prefix=" & quoteShell(work & "/") & " " & quoteShell(corpus))
    check code != 0
    check "reached the fault" in output
    var written = ""
    for f in walkFiles(work / "crash-*"):
      if readFile(f).startsWith("FUZZ"): written = f
    check written.len > 0

removeDir(work)
