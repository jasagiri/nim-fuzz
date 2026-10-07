# Package
version       = "0.1.0"
author        = "jasagiri"
description   = "Fuzzing in-process: inputs mutated from a seed corpus, kept when they reach new code, findings minimised"
license       = "Apache-2.0"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"

task test, "Run the test suite":
  exec "make test"
