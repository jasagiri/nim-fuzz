.PHONY: test spec-coverage clean

# The G1 tool lives in nimtype and takes the repository root as its argument.
SPEC_COVERAGE_SRC := ../nimtype/tests/tools/spec_coverage.nim

# Every test runs twice: without the coverage signal, and with it
# (-d:fuzzCoverage, which needs clang).
test:
	@mkdir -p bin/tests
	@set -e; for t in tests/external/test_*.nim; do \
	  echo "== $$t (no coverage signal)"; \
	  nim c -r --hints:off -o:bin/tests/$$(basename $$t .nim) $$t; \
	  echo "== $$t (coverage signal)"; \
	  nim c -r --hints:off --cc:clang -d:fuzzCoverage --nimcache:bin/nimcache-cov -o:bin/tests/$$(basename $$t .nim)_cov $$t; \
	done

spec-coverage:
	@mkdir -p bin/tools
	nim c --hints:off -o:bin/tools/spec_coverage $(SPEC_COVERAGE_SRC)
	./bin/tools/spec_coverage . > docs/quality/g1-spec-coverage.md

clean:
	rm -rf bin nimcache
