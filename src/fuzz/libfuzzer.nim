## libFuzzer as the engine for a nim-fuzz target (ADR-FZZ-0001, LFZ).
##
## ```nim
## import fuzz/libfuzzer
## proc target(input: string): string {.raises: [CatchableError].} = ...
## libFuzzerTarget(target)
## ```
##
## Build with a clang that has the libFuzzer runtime (Homebrew's LLVM on
## macOS; Apple's clang has none), without Nim's `main`, which libFuzzer
## provides:
##
## ```sh
## nim c --cc:clang --clang.exe:$LLVM/clang --clang.linkerexe:$LLVM/clang \
##   --noMain --panics:on -d:useMalloc -d:noSignalHandler \
##   --passC:-fsanitize=fuzzer,address --passL:-fsanitize=fuzzer,address prog.nim
## ```
##
## The verdicts are those of `fuzz`: a reason the target returns and an
## exception it raises are findings (the input is aborted on, so libFuzzer
## saves it); a Defect ends the process through `--panics:on`, which libFuzzer
## also reports. POSIX only.

when not defined(noSignalHandler):
  {.error: "build with -d:noSignalHandler: Nim's signal handlers would take " &
           "libFuzzer's, and it would not save the input that crashed".}

import std/posix
import ../fuzz

proc abort() {.importc, header: "<stdlib.h>", noreturn.}

proc report(text: string) {.raises: [].} =
  ## To standard error with write(2): a finding is reported even when Nim's
  ## streams are what broke.
  var written = 0
  while written < text.len:
    let n = posix.write(2, unsafeAddr text[written], text.len - written)
    if n <= 0: return
    written += n

proc runForLibFuzzer*(target: FuzzTarget, data: ptr UncheckedArray[byte],
                      size: int) {.raises: [].} =
  ## Runs `target` on one input; aborts when the target finds a problem.
  var input = newString(size)
  if size > 0:
    copyMem(addr input[0], data, size)
  var reason = ""
  try:
    reason = target(input)
  except CatchableError as e:
    reason = "raised " & $e.name & ": " & e.msg
  if reason.len > 0:
    report("nim-fuzz finding: " & reason & "\n")
    abort()

template libFuzzerTarget*(target: FuzzTarget) =
  ## Defines the entry points libFuzzer calls. Nim's module initialization
  ## runs once, before the first input.
  proc NimMain() {.importc.}

  # Exported from the program (`dynlib`): libFuzzer on macOS finds its
  # optional entry points with dlsym, which does not see a hidden symbol.
  proc LLVMFuzzerInitialize(argc: pointer, argv: pointer): cint {.exportc, dynlib, cdecl.} =
    NimMain()
    0

  proc LLVMFuzzerTestOneInput(data: ptr UncheckedArray[byte], size: csize_t): cint
      {.exportc, dynlib, cdecl.} =
    runForLibFuzzer(target, data, int(size))
    0
