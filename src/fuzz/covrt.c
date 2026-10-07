/* The receiving end of clang's -fsanitize-coverage=trace-pc-guard.
 * Compiled without that flag itself: a callback that is instrumented
 * calls itself. Each edge of the instrumented program has a guard; the
 * first time an edge runs, its byte of the map is set and counted. */
#include <stdint.h>
#include <string.h>

#define FUZZ_MAP_SIZE 65536
static uint8_t fuzz_edges[FUZZ_MAP_SIZE];
static uint32_t fuzz_guards;
static uint64_t fuzz_fresh;

void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop) {
  for (uint32_t *p = start; p < stop; p++)
    if (*p == 0) *p = ++fuzz_guards;
}

void __sanitizer_cov_trace_pc_guard(uint32_t *guard) {
  uint32_t at = *guard & (FUZZ_MAP_SIZE - 1);
  if (!fuzz_edges[at]) {
    fuzz_edges[at] = 1;
    fuzz_fresh++;
  }
}

uint64_t fuzz_fresh_edges(void) { return fuzz_fresh; }
uint32_t fuzz_guard_count(void) { return fuzz_guards; }
void fuzz_reset_edges(void) {
  memset(fuzz_edges, 0, sizeof fuzz_edges);
  fuzz_fresh = 0;
}
