# Zoril Self-Hosted Compiler Makefile

# Two-stage source bootstrap:
#   bootstrap/stage0-c/ (C99) builds bootstrap/stage1/ (frozen snapshot) into
#   build/zoril-stage1 and build/zilc-stage1; those build src/ into build/zoril.
# Once build/zoril exists it rebuilds src/ itself.
# To skip the bootstrap seed when a system zoril compiler is available:
#   make SYSTEM_ZORIL=1

.DEFAULT_GOAL := all

TARGET = build/zoril
ZILC = build/zilc


STAGE0_C_DIR ?= bootstrap/stage0-c
STAGE1_DIR   ?= bootstrap/stage1

##var ZORIL_STDLIB Path to the zoril-c standard library
ZORIL_STDLIB ?= $(STAGE0_C_DIR)/lib/rt

ZILC_SRCS = tools/zilc/src/*.zrl

-include config.mk

# Installation paths
##var PREFIX Installation prefix (default: /usr/local)
PREFIX ?= /usr/local
EXEC_PREFIX ?= $(PREFIX)
##var BINDIR Binary installation directory (default: $$(PREFIX)/bin)
BINDIR ?= $(EXEC_PREFIX)/bin
##var LIBDIR Library installation directory (default: $$(PREFIX)/lib)
LIBDIR ?= $(EXEC_PREFIX)/lib
##var DATADIR Data/stdlib installation directory (default: $$(PREFIX)/share)
DATADIR ?= $(PREFIX)/share
##var DOCDIR Documentation installation directory (default: $$(DATADIR)/doc/zoril)
DOCDIR ?= $(DATADIR)/doc/zoril
##var MANDIR Manual page installation directory (default: $$(DATADIR)/man)
MANDIR ?= $(DATADIR)/man
##var DESTDIR Staging directory for installation (default: empty)
DESTDIR ?=

INSTALL ?= install
INSTALL_PROGRAM ?= $(INSTALL) -m 755
INSTALL_DATA ?= $(INSTALL) -m 644
INSTALL_DIR ?= $(INSTALL) -d

ZILC_BIN ?= build/zilc
##var BACKEND_BIN Path to system backend binary (default: qbe)
BACKEND_BIN ?= qbe
ASSEMBLER_BIN ?= as
LINKER_BIN ?= ld

export ZILC_BIN
export BACKEND_BIN
export ASSEMBLER_BIN
export LINKER_BIN

##var SYSTEM_ZORIL Set to 1 to skip bootstrap seed if system zoril is installed (default: 0)
SYSTEM_ZORIL ?= 0
##var ZORIL_SEED Directory containing seed zoril and zilc binaries
ZORIL_SEED ?=
ifeq ($(SYSTEM_ZORIL),1)
    ZORIL_BUILDER ?= zoril
    ZILC_BUILDER ?= zilc
    BOOTSTRAP_CC ?= zoril
endif
ifneq ($(ZORIL_SEED),)
    ZORIL_BUILDER ?= $(ZORIL_SEED)/zoril
    ZILC_BUILDER ?= $(ZORIL_SEED)/zilc
    BOOTSTRAP_CC ?= $(ZORIL_SEED)/zoril
endif

BOOTSTRAP_CC_TIMEOUT ?= 600s
BOOTSTRAP_BUILD_TIMEOUT ?= 300s

export TARGET
export ZILC
export ZORIL_BUILDER
export ZILC_BUILDER
export BOOTSTRAP_CC_TIMEOUT
export BOOTSTRAP_BUILD_TIMEOUT

##var ZORIL_CC Path to the compiler to test/build with (default: build/zoril)
ZORIL_CC ?= $(TARGET)
EXTRA_OBJS ?=

##var TIMEOUT_DUR Timeout for each test step (default: 30s)
TIMEOUT_DUR ?= 30s
##var KILL_DUR Grace period after timeout before SIGKILL (default: 2s)
KILL_DUR ?= 2s
##var QUIET Set to empty string to disable quiet mode (e.g. QUIET=)
QUIET ?= --quiet
##var BASE Base commit to compare changed files against in test-changed (default: preflight_base)
BASE ?= $(PREFLIGHT_BASE)
TEST_RUNNER ?= ./scripts/test.sh

GATE = TIMEOUT_SECS=$(TIMEOUT_DUR) KILL_DUR=$(KILL_DUR) ./scripts/test.sh $(QUIET) --gate

# Use --foreground so timeout and its children remain in the caller's process group
# and respond immediately to Ctrl-C (SIGINT) and break signals.
HAVE_TIMEOUT := $(shell command -v timeout 2>/dev/null)
TIMEOUT_FOREGROUND := $(if $(HAVE_TIMEOUT),$(shell timeout --foreground 0 true 2>/dev/null && echo --foreground),)
TIMEOUT_BIN ?= $(if $(HAVE_TIMEOUT),timeout $(TIMEOUT_FOREGROUND),)

SRCS = src/*.zrl src/driver/*.zrl src/lower_zir/*.zrl src/parser/*.zrl src/fmt/*.zrl stdlib/*.zrl $(wildcard stdlib/*/*.zrl) rt/runtime.s

##@ Core & Build
all: $(TARGET) $(ZILC) build/zbuild build/runtime.o build/runtime_hosted.o ## Build the toolchain: the compiler, zilc, zbuild and the runtimes (default)
	@if [ -f build/.rebuilt ]; then \
		rm -f build/.rebuilt; \
		echo "Built: the toolchain is up to date in build/ (zoril, zilc, zbuild; zoril $$(./scripts/version.sh)). Next: make test"; \
	else \
		echo "Up to date: build/zoril, build/zilc and build/zbuild (zoril $$(./scripts/version.sh))"; \
	fi

# Check dependencies for build (backend, assembler, linker, awk, sed)
.PHONY: deps-build
deps-build:
	@./scripts/check_deps.sh build

# Check dependencies for C bootstrap seed compiler (CC)
.PHONY: deps-seed
deps-seed:
	@./scripts/check_deps.sh seed

STAGE0_C_TARGET ?= $(if $(filter cproc,$(notdir $(firstword $(CC)))),minimal,release)

STAGE0_C_SRCS := $(wildcard $(STAGE0_C_DIR)/src/*.c) $(wildcard $(STAGE0_C_DIR)/include/*.h) $(wildcard $(STAGE0_C_DIR)/src/*.h) $(STAGE0_C_DIR)/Makefile
$(STAGE0_C_DIR)/build/zoril-c.release: $(STAGE0_C_SRCS)
	@./scripts/check_deps.sh seed
	@mkdir -p build
	@echo "Building stage0-C $(STAGE0_C_TARGET) compiler..."
	@$(MAKE) --no-print-directory -C $(STAGE0_C_DIR) $(STAGE0_C_TARGET) > build/stage0c-release.log 2>&1 || \
		{ cat build/stage0c-release.log; echo "building stage0-C failed"; exit 1; }

STAGE1_ZRL := $(shell find $(STAGE1_DIR) -name '*.zrl' 2>/dev/null)
STAGE0_C_RUN = $(if $(TIMEOUT_BIN),$(TIMEOUT_BIN) -k 5s 120s,) $(STAGE0_C_DIR)/build/zoril-c.release

build/runtime-stage1.o: $(STAGE1_DIR)/rt/runtime.s | deps-build
	@mkdir -p build
	@$(ASSEMBLER_BIN) -o build/runtime-stage1.o $(STAGE1_DIR)/rt/runtime.s

define stage1_build
	@mkdir -p build
	@echo "Building $(1) from $(STAGE1_DIR)/ with stage0-C..."
	@$(STAGE0_C_RUN) $(2) --emit-ir -o $(1).ssa $(3) > $(1).log 2>&1 || (cat $(1).log && echo "stage0-C failed to build $(1)" && exit 1)
	@if grep -q "warning:" $(1).log; then cat $(1).log; echo "Error: warnings building $(1)"; exit 1; fi
	@$(BACKEND_BIN) -o $(1).s $(1).ssa || (echo "$(1): backend failed" && exit 1)
	@$(ASSEMBLER_BIN) -o $(1).o $(1).s || (echo "$(1): assembler failed" && exit 1)
	@$(LINKER_BIN) -o $(1).tmp build/runtime-stage1.o $(1).o && mv $(1).tmp $(1) || (echo "$(1): linker failed" && exit 1)
	@chmod +x $(1)
endef

build/zoril-stage1: $(STAGE0_C_DIR)/build/zoril-c.release $(STAGE1_ZRL) build/runtime-stage1.o
	@$(call stage1_build,build/zoril-stage1,-I $(STAGE1_DIR)/stdlib -I $(STAGE1_DIR)/src,$(STAGE1_DIR)/src/main.zrl)

build/zilc-stage1: $(STAGE0_C_DIR)/build/zoril-c.release $(STAGE1_ZRL) build/runtime-stage1.o
	@$(call stage1_build,build/zilc-stage1,-I $(STAGE1_DIR)/stdlib -I $(STAGE1_DIR)/src -I $(STAGE1_DIR)/tools/zilc/src,$(STAGE1_DIR)/tools/zilc/src/main.zrl)

# build/zilc-boot: a zilc that can read the ZIL a compiler built from MUTABLE src/ writes,
# assembled entirely through the stage1 path: stage1's front end compiles tools/zilc/src
# (its ZIL is the dialect build/zilc-stage1 was itself built for), and build/zilc-stage1
# links it. Needed whenever no build/zilc exists yet -- the fresh-checkout path of
# $(TARGET), and zilc's own first build ($(ZILC), which reads ./build/zilc-boot) -- so the
# one recipe serves both and they cannot drift apart.
#
# zilc-stage1 must NOT take that job itself. It is the zilc of the freeze, and the ZIL
# src/ writes is not: since Phase D (2026-10-12) src/ writes `RawPtr<T>` / `RawPtrMut<T>`,
# which zilc-stage1 does not know. It reads the unknown name as a var type, leaves the
# `<...>` behind, and then loops forever in parse_module (a `t` that starts no `type`
# declaration makes no progress). That is a HANG, not an error, so it cost the fresh path
# its BOOTSTRAP_BUILD_TIMEOUT (2026-10-13). build/zilc-boot is the same trick zilc's own
# bootstrap below uses.
#
# build/gen/version.zrl is order-only: `-I build/gen` needs the file to exist, but a boot
# zilc's own version string is throwaway (it assembles ZIL; the version a shipped build/zilc
# reports comes from the ZIL it is built from), and as a normal prerequisite it would force
# this rule to re-run on every invocation -- build/gen/version.zrl is FORCE'd.
build/zilc-boot: build/zoril-stage1 build/zilc-stage1 build/runtime.o $(ZILC_SRCS) | build/gen/version.zrl
	@mkdir -p build
	@echo "No build/zilc yet: building a bootstrap zilc (build/zilc-boot)..."
	@$(RUN_BIG_STACK) $(if $(TIMEOUT_BIN),$(TIMEOUT_BIN) -k 5s $(BOOTSTRAP_BUILD_TIMEOUT),) ./build/zoril-stage1 -I stdlib=stdlib -I src -I tools/zilc/src -I build/gen --emit-zil -o build/zilc-boot.zil tools/zilc/src/main.zrl > build/zilc-boot.log 2>&1 \
		&& $(RUN_BIG_STACK) $(if $(TIMEOUT_BIN),$(TIMEOUT_BIN) -k 5s $(BOOTSTRAP_BUILD_TIMEOUT),) ./build/zilc-stage1 build/zilc-boot.zil build/zilc-boot.ssa \
		&& $(BACKEND_BIN) -o build/zilc-boot.s build/zilc-boot.ssa \
		&& $(ASSEMBLER_BIN) -o build/zilc-boot.o build/zilc-boot.s \
		&& $(LINKER_BIN) -o build/zilc-boot build/zilc-boot.o build/runtime.o \
		|| { cat build/zilc-boot.log; echo "bootstrap zilc failed"; exit 1; }

# Which zilc assembles which ZIL is the one thing that must not be guessed. The rule follows
# the dialect of the ZIL in hand, not the handy binary:
#   * ZIL written by build/zoril-stage1 -- the frozen front end -- is assembled by
#     build/zilc-stage1, the zilc of the same freeze. They were built together and agree.
#   * ZIL written by a compiler built from src/ (generation 1, the self-hosted rebuild
#     below, and the branch where build/zoril already exists) is assembled by $(ZILC), or by
#     build/zilc-boot when build/zilc does not exist yet (modern_zilc below).
# Feeding src/'s ZIL to zilc-stage1 is the bug this split fixes (2026-10-13): see the
# build/zilc-boot comment above.
TARGET_IS_LEGACY_SYMLINK := $(shell test -L $(TARGET) && echo yes)
$(TARGET): $(SRCS) build/runtime.o build/gen/version.zrl $(if $(TARGET_IS_LEGACY_SYMLINK),FORCE)
	@./scripts/bootstrap_zoril.sh

BOOTSTRAP_CC ?= $(TARGET)
RUN_BIG_STACK = ulimit -s 262144 2>/dev/null;
BOOTSTRAP_CC_RUN = $(RUN_BIG_STACK) $(if $(TIMEOUT_BIN),$(TIMEOUT_BIN) -k 5s $(BOOTSTRAP_CC_TIMEOUT),) $(BOOTSTRAP_CC)

RT_HOST = build/runtime.o

build/runtime.o: rt/runtime.s | deps-build
	@mkdir -p build
	@$(ASSEMBLER_BIN) -o build/runtime.o rt/runtime.s

# The runtime for a program linked into a libc process (`zoril --hosted`): the HOSTED branch of rt/runtime.s.
build/runtime_hosted.o: rt/runtime.s | deps-build
	@mkdir -p build
	@$(ASSEMBLER_BIN) --defsym HOSTED=1 -o build/runtime_hosted.o rt/runtime.s

$(ZILC): $(TARGET) $(ZILC_SRCS) build/runtime.o build/gen/version.zrl
	@mkdir -p build
	@echo "Building zilc using $(BOOTSTRAP_CC)..."
	@had_zilc=0; [ -x build/zilc ] && had_zilc=1; \
	./scripts/build_zrl.sh build/zilc tools/zilc/src/main.zrl \
		-I stdlib=stdlib -I src -I tools/zilc/src -I build/gen \
		--compiler $(BOOTSTRAP_CC) --toolchain-stamp \
	&& { [ "$$had_zilc" = 1 ] || touch build/.selfhost-unverified; }

ZBUILD_SRCS := $(wildcard tools/zbuild/src/*.zrl) src/module_path.zrl stdlib/fsys.zrl stdlib/proc.zrl

build/zbuild: $(TARGET) $(ZBUILD_SRCS) $(ZILC) build/runtime.o build/gen/version.zrl
	@mkdir -p build
	@echo "Building zbuild using $(TARGET)..."
	@./scripts/build_zrl.sh build/zbuild tools/zbuild/src/main.zrl \
		-I stdlib=stdlib -I src -I tools/zbuild/src -I build/gen --compiler $(TARGET)
	@touch build/.rebuilt
	@[ ! -f build/.selfhost-unverified ] || ./scripts/selfhost_finalize.sh

zbuild: build/zbuild ## Build the zbuild incremental driver

# ── Version module ────────────────────────────────────────────────────────────
build/gen/version.zrl: FORCE | deps-build
	@mkdir -p build/gen
	@v=$$(./scripts/version.sh); \
	tmp=build/gen/version.zrl.$$$$.tmp; \
	printf 'pub fn version() -> [u8] { return "%s"; }\n' "$$v" > "$$tmp"; \
	if [ ! -f build/gen/version.zrl ] || ! cmp -s "$$tmp" build/gen/version.zrl; then \
		mv -f "$$tmp" build/gen/version.zrl; \
	else \
		rm -f "$$tmp"; \
	fi

##@ Testing
test-versions: $(TARGET) $(ZILC) build/zbuild $(TEST_VERSIONS_DEPS) ## Verify --version and -V output for all tools
	@./scripts/test_tool_versions.sh $(TEST_VERSIONS_ARGS)

.PHONY: FORCE
FORCE:

##var TSUITE Test suite (all|language|types|memory|stdlib|integration|corpus|chain)
TSUITE ?= all
##var T Name of the test to run (for a single test run)
T ?=

##@ Gates
selfhost-build-check: ## Gate: stage0-C builds stage1/, and stage1 builds src/
	@./scripts/selfhost-check.sh --build-only

# Repository gates: mechanical checks driven through scripts/test.sh --gate.
# The 26 gates below, together with the six stage0c suites, match scripts/test.sh --list-gates.
GATES = fmt-check md-check no-new-deps binary-sizes no-warnings test-strength fuzz-record fuzz-fresh \
        safety-matrix safety-matrix-zbuild safety-model safety-comments safety-figures comment-noise reborrow-probes exhaustive route-coverage temp-names unsafe-scan runtimes static-image \
        perf-gate toolchain portability clean-tree toolchain-offpath stage0c-fixed-bugs mutation-self-test

$(GATES):
	@$(GATE) $@

# Recipe-less prerequisites and descriptions for repository gates.
fmt-check: $(TARGET) ## Gate: all source files formatted and formatter rules pass
md-check: ## Check all markdown files are formatted (per .dprint.json)
no-new-deps: ## Gate: no dev tool brings a runtime this repository does not depend on (Python is the named case)
binary-sizes: ## Gate: README's compact-binary figures match the binaries this tree builds (within 10%)
no-warnings: $(TARGET) ## Gate: compile with no compiler warnings
test-strength: ## Gate: reject tests that cannot fail
fuzz-record: ## Gate: fuzz findings record is reproducible
fuzz-fresh: ## Gate: the fuzz record's fingerprint matches the compiler sources (reports; --strict fails)
mutation-self-test: ## Gate: self-test of the mutation testing engine
safety-matrix: $(TARGET) $(ZILC) $(RT_HOST) ## Gate: every safety probe matches its documented behaviour
safety-matrix-zbuild: $(TARGET) $(ZILC) build/zbuild $(RT_HOST) build/runtime_hosted.o ## Gate: every safety probe through an installed zbuild gives the outcome its header records
safety-model: $(TARGET) ## Gate: safety_model.md citations and evidence levels are self-consistent
comment-noise: ## Gate: comments state why, not what, and stay within their recorded budget
reborrow-probes: $(TARGET) ## Gate: the programs the reborrow rule must reject are rejected
store-grid: $(TARGET) $(ZILC) $(RT_HOST) ## Gate: the store-rule grid (source x carrier x path x destination x invalidation)
	@./scripts/check_store_grid.sh
safety-comments: ## Gate: every stdlib unsafe block states its invariant
safety-figures: ## Gate: the figures doc/SAFETY.md section 5 quotes match the tree
exhaustive: ## Gate: transfer functions marked // exhaustive have no wildcard arm
route-coverage: $(TARGET) ## Gate: every route a safety-matrix row lists has a probe
temp-names: ## Gate: no expected diagnostic names a compiler temporary by id
unsafe-scan: ## Gate: scan for unapproved unsafe constructs
runtimes: ## Gate: the runtime/linker pairing is consistent (no compiler run)
static-image: $(TARGET) ## Gate: determinism of static compiler images
perf-gate: $(TARGET) $(ZILC) $(RT_HOST) ## Gate: generated code executes no more instructions than recorded
toolchain: ## Gate: verify toolchain configuration consistency
portability: ## Gate: verify script portability across platforms
clean-tree: ## Gate: ensure no stray build artifacts outside build/
toolchain-offpath: ## Gate: verify build with toolchain off PATH
stage0c-fixed-bugs: $(STAGE0_C_DIR)/build/zoril-c.release ## Gate: stage0-C fixed-bug regressions

##@ Maintenance
comment-census: ## Record scripts/comment_budget.tsv from the comments this tree has now
	@sh scripts/comment_census.sh --record

md-fmt: ## Format all markdown files with dprint (per .dprint.json)
	dprint fmt

##@ Fuzzing
fuzz-short: $(TARGET) $(ZILC) build/runtime.o build/zbuild build/runtime_hosted.o ## Generate safe programs, run them, and diff the outcome with rustc
	@FUZZ_FINDINGS=$$(mktemp -d) ./scripts/fuzz_safe.sh --seeds 1-25 --count 4 --mode mix --checked

# The calibration stream: one self-contained program per known memory-safety hole, in its fixed
# state - 21 refused by the compiler, two accepted with one drop. `scripts/fuzz_calibrate.sh` reports
# the table in bench/fuzz/README.md and names a row to update when a mechanism changes.
# `scripts/preflight.sh` runs `scripts/check_fuzz_calibrate.sh` in both preflight modes, so a
# reopened hole fails the pre-merge gate; this target prints the per-row table on demand.
fuzz-calibrate: $(TARGET) $(ZILC) build/runtime.o build/zbuild build/runtime_hosted.o ## Run one program per known hole through both runtime oracles
	@./scripts/fuzz_calibrate.sh

# The record itself is kept honest by the `fuzz-record` gate in `make test` (scripts/check_fuzz_record.sh,
# which also runs the driver through scripts/fuzz/stub_zoril.sh); these two run the fuzzer itself, and
# `fuzz` files what it finds in bench/fuzz/findings/, where that gate requires each pair to be named in
# the directory's README. See bench/fuzz/README.md for the oracles and the scope.
fuzz: $(TARGET) $(ZILC) build/runtime.o build/zbuild build/runtime_hosted.o ## 400 seeds, findings filed in bench/fuzz/findings/ (on demand)
	@./scripts/fuzz_safe.sh --seeds 1-400 --count 8 --mode mix --record-findings

fuzz-release: $(TARGET) $(ZILC) build/runtime.o build/zbuild build/runtime_hosted.o ## Budget run: pass FUZZ_ARGS='--jobs N --seeds A-B --mode mix'
	@./scripts/fuzz_safe.sh --release $(FUZZ_ARGS)

# Fuzz sessions, run from outside: each of these is one script in scripts/fuzz/, documented in
# doc/developer_guide.md ("Fuzzing"). Variables: SEEDS=A-B, JOBS=n (default: the cores), RAN=n (a
# compiled-and-ran target), RUN=name-or-path (default: the latest run), NAME=n (default: a UTC
# timestamp), RELEASE=1 (a cited session: freshness and rustc are enforced), WATCH=seconds, FORMAT=record, MARGIN=percent.
fuzz-session: $(TARGET) $(ZILC) build/runtime.o build/zbuild build/runtime_hosted.o ## Your own fuzz session in the foreground: SEEDS=1-20000 [JOBS=n] [NAME=n]
	@./scripts/fuzz/session.sh --seeds '$(SEEDS)' $(if $(JOBS),--jobs $(JOBS)) $(if $(NAME),--name $(NAME)) $(if $(RAN),--ran $(RAN)) $(if $(RELEASE),--release)

fuzz-start: $(TARGET) $(ZILC) build/runtime.o build/zbuild build/runtime_hosted.o ## The same, in the background (survives the terminal): SEEDS=1-20000
	@./scripts/fuzz/session.sh --background --seeds '$(SEEDS)' $(if $(JOBS),--jobs $(JOBS)) $(if $(NAME),--name $(NAME)) $(if $(RAN),--ran $(RAN)) $(if $(RELEASE),--release)

fuzz-status: ## Where is a fuzz run: banner, status line, workers, findings [RUN=n] [WATCH=60]
	@./scripts/fuzz/status.sh $(if $(RUN),--run $(RUN)) $(if $(WATCH),--watch $(WATCH))

fuzz-stop: ## Stop a background fuzz run and mark it killed [RUN=n]
	@./scripts/fuzz/stop.sh $(RUN)

fuzz-summary: ## The figures of a run, summed over its workers [RUN=n] [FORMAT=record]
	@./scripts/fuzz/summary.sh $(if $(RUN),--run $(RUN)) $(if $(FORMAT),--format $(FORMAT))

fuzz-preflight: ## Everything a cited fuzz run needs, one [PASS]/[FAIL] line each
	@./scripts/fuzz/preflight.sh

fuzz-pilot: ## Pre-flight, then the standard pilot (10,000 seeds x 8) and its plan [RAN=2500000]
	@./scripts/fuzz/pilot.sh $(if $(NAME),--name $(NAME)) $(if $(RAN),--ran $(RAN)) $(if $(JOBS),--jobs $(JOBS))

fuzz-plan: ## Seed range, expected count and wall time from a pilot: RAN=2500000 [RUN=n] [MARGIN=5]
	@./scripts/fuzz/plan.sh --ran '$(RAN)' $(if $(RUN),--run $(RUN)) $(if $(MARGIN),--margin $(MARGIN))

fuzz-release-start: ## The cited budget run in the background, after pre-flight: SEEDS=1-N RAN=2500000
	@./scripts/fuzz/release_start.sh --seeds '$(SEEDS)' --ran '$(RAN)' $(if $(NAME),--name $(NAME)) $(if $(JOBS),--jobs $(JOBS))

fuzz-record-update: ## After a clean budget run: write its numbers into the record RUN=release-<name> [SHORT=1: a RELEASE=1 session on the launched code]
	@./scripts/fuzz/record_update.sh $(if $(RUN),--run $(RUN)) $(if $(SHORT),--short-session)

fuzz-prove: $(TARGET) $(ZILC) build/runtime.o ## Prove the fuzzer's oracles fire: break a scratch compiler, require the report [ORACLE=value|bounds|box|mode|all]
	@./scripts/fuzz/prove_oracle.sh $(or $(ORACLE),all)

stage0c-build:
	@mkdir -p build
	@$(MAKE) --no-print-directory -C $(STAGE0_C_DIR) all > build/stage0c-build.log 2>&1 || \
		{ cat build/stage0c-build.log; echo "building stage0-C failed"; exit 1; }

##@ Gates
stage0c-suites: stage0c-build ## Gate: stage0-C's own test suites
	@$(GATE) stage0c-unit --gate stage0c-corpus --gate stage0c-docs --gate stage0c-error-locations --gate stage0c-functional --gate stage0c-minimal

mutation-check: ## Break the compiler on purpose; require the suite to notice
	@./scripts/mutation-check.sh

selfhost-check: ## Full gate: self-hosting fixpoint
	@./scripts/selfhost-check.sh

selfhost-confirm: $(TARGET) $(ZILC) build/zbuild ## Rebuild zoril, zilc and zbuild with themselves; keep the self-built ones if they differ from build/'s
	@./scripts/selfhost_finalize.sh --force

repro-check: ## Gate: bootstrap from scratch twice and require identical results [HASHES=file: also compare with a release's hashes]
	@./scripts/repro-check.sh $(if $(filter 1,$(KEEP)),--keep) $(if $(HASHES),--hashes '$(HASHES)')

# Both pre-merge gates run selfhost-check (a clean copy of the tree builds with the DEFAULT
# rules -- the fresh-checkout path -- plus the self-hosting fixpoint) in the BACKGROUND,
# beside mutation-check, and WAIT for it before the bench step: the bench thresholds refuse a
# loaded host, so nothing else may still be running when they start.
preflight: $(TARGET) $(ZILC) build/runtime.o build/zbuild build/runtime_hosted.o ## Full pre-merge gate: selfhost + mutation + bench thresholds
	@./scripts/preflight.sh

preflight-changed: $(TARGET) $(ZILC) build/runtime.o build/zbuild build/runtime_hosted.o ## Fast pre-merge gate: selfhost + mutations of changed files
	@./scripts/preflight.sh --changed

##@ Testing
test-changed: $(TARGET) $(ZILC) build/zbuild build/runtime.o build/runtime_hosted.o ## Run tests scoped to changed files (BASE=<commit>, default: preflight_base)
	@./scripts/check_deps.sh test
	@if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		echo "test-changed: not inside a git checkout, running all tests"; \
		TIMEOUT_SECS=$(TIMEOUT_DUR) KILL_DUR=$(KILL_DUR) $(TEST_RUNNER) $(QUIET) --gates; \
	else \
		. scripts/lib/preflight_base.sh; \
		if [ -n "$(BASE)" ]; then \
			PREFLIGHT_BASE="$(BASE)"; \
		fi; \
		if ! preflight_base; then \
			echo "[FAIL] test-changed: no base to check the change against: $$PF_BASE_ERR" >&2; \
			exit 1; \
		fi; \
		echo "test-changed: base $$PF_BASE ($$PF_BASE_WHY)"; \
		args=$$( (git diff --name-only --no-renames "$$PF_BASE" 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null) | sort -u | ./scripts/select_test_tier.sh ) || exit $$?; \
		TIMEOUT_SECS=$(TIMEOUT_DUR) KILL_DUR=$(KILL_DUR) $(TEST_RUNNER) $(QUIET) $$args; \
	fi

test-checked: $(TARGET) $(ZILC) build/runtime.o ## Run the tests, corpus, apps and safety probes under `zoril --checked`
	@./scripts/test_checked.sh

test-fast: $(TARGET) $(ZILC) build/runtime.o ## Smoke tests while editing (tests/smoke.list)
	@./scripts/test.sh --quiet --smoke

test-readme: $(TARGET) $(ZILC) $(RT_HOST) ## Test code snippets extracted from README.md (Zoril and Rust)
	@./scripts/test_readme_snippets.sh

test-docs: $(TARGET) $(ZILC) $(RT_HOST) ## Compile the Zoril code blocks in the docs, run complete programs
	@./scripts/test_doc_snippets.sh

test-getting-started: $(TARGET) $(ZILC) $(RT_HOST) build/zbuild build/runtime_hosted.o ## Test code snippets and walkthrough commands in doc/getting_started.md
	@./scripts/test_getting_started.sh

TEST_GATE_DEPS = $(RT_HOST) build/runtime_hosted.o $(STAGE0_C_DIR)/build/zoril-c.release stage0c-build
test: $(if $(T),,$(TEST_GATE_DEPS)) $(TARGET) $(ZILC) build/zbuild ## Run tests (TSUITE=all|..., T=<pattern> for verbose matching tests)
	@./scripts/check_deps.sh test
	@TIMEOUT_SECS=$(TIMEOUT_DUR) KILL_DUR=$(KILL_DUR) ./scripts/test.sh $(if $(T),--verbose --filter '$(T)' tests corpus,$(QUIET) --suite '$(TSUITE)')

deps-matrix: $(TARGET) $(ZILC) build/zbuild ## Run the tool dependency matrix (optional, configurable, required tools)
	@./scripts/test_dep_matrix.sh $(FILTER)

MAN_SRCS_1 := $(wildcard doc/man/*.1.scd)
MAN_SRCS_3 := $(wildcard doc/man/*.3.scd)
MAN_SRCS_7 := $(wildcard doc/man/*.7.scd)

# The roff pages are committed beside their sources, so installing never needs scdoc.
MAN_PAGES_1 := $(MAN_SRCS_1:.scd=)
MAN_PAGES_3 := $(MAN_SRCS_3:.scd=)
MAN_PAGES_7 := $(MAN_SRCS_7:.scd=)
MAN_PAGES := $(MAN_PAGES_1) $(MAN_PAGES_3) $(MAN_PAGES_7)

man: ## Regenerate the committed man pages (doc/man/<page>.<n>) from their scdoc sources
	@./scripts/check_deps.sh man
	@./scripts/man_pages.sh render

# The stdlib pages (zoril-<module>.3.scd) are generated, not written: zman reads one fresh
# interface per module plus the module's own comment blocks. The interfaces go to build/man-gen, so
# a page can never be generated from a stale build/zri copy.
MAN_PAGES_DIR = build/man-gen/zri
# A module below stdlib/<dir>/ is named <dir>_<module> (stdlib/os/unix.zrl is os_unix).
MAN_SOURCES := $(wildcard stdlib/*.zrl stdlib/*/*.zrl)
MAN_SUBDIRS := $(patsubst stdlib/%/,%,$(sort $(dir $(wildcard stdlib/*/*.zrl))))
MAN_INTERFACES := $(patsubst stdlib/%.zrl,$(MAN_PAGES_DIR)/%.zri,$(wildcard stdlib/*.zrl)) \
	$(foreach d,$(MAN_SUBDIRS),$(patsubst stdlib/$(d)/%.zrl,$(MAN_PAGES_DIR)/$(d)_%.zri,$(wildcard stdlib/$(d)/*.zrl)))
ZMAN ?= tools/zman/build/zman

$(MAN_PAGES_DIR)/%.zri: stdlib/%.zrl $(TARGET)
	@mkdir -p $(MAN_PAGES_DIR)
	@$(TARGET) --emit-interface -I stdlib=stdlib -o $@ $<

define MAN_SUBDIR_RULE
$(MAN_PAGES_DIR)/$(1)_%.zri: stdlib/$(1)/%.zrl $(TARGET)
	@mkdir -p $(MAN_PAGES_DIR)
	@$(TARGET) --emit-interface -I stdlib=stdlib -o $$@ $$<
endef
$(foreach d,$(MAN_SUBDIRS),$(eval $(call MAN_SUBDIR_RULE,$(d))))

$(ZMAN): $(wildcard tools/zman/src/*.zrl) $(TARGET) $(ZILC) build/runtime.o
	@$(MAKE) --no-print-directory -C tools/zman build

##@ Maintenance
man-gen: $(ZMAN) $(MAN_INTERFACES) ## Regenerate the stdlib man pages (doc/man/zoril-<module>.3 and its .scd) from the stdlib comments
	@./scripts/check_deps.sh man
	@$(ZMAN) --zri $(MAN_PAGES_DIR) --out doc/man $(MAN_SOURCES)
	@./scripts/man_pages.sh render

##@ Testing
test-man: $(TARGET) $(ZILC) build/zbuild build/runtime.o $(ZMAN) $(MAN_INTERFACES) ## Test man page syntax, options, examples, and that the pages match the stdlib
	@./scripts/test_man_pages.sh

##@ Release
dist: ## Source tarball build/dist/zoril-<version>.tar.xz (reproducible; needs bsdtar)
	@./scripts/check_deps.sh dist
	@./scripts/dist.sh src

dist-bin: all build/zbuild build/runtime.o build/runtime_hosted.o ## Binary tarball build/dist/zoril-<version>-linux-x86_64.tar.xz, smoke-tested
	@./scripts/check_deps.sh dist
	@./scripts/dist.sh bin

dist-check: all build/zbuild build/runtime.o build/runtime_hosted.o ## Build both tarballs twice and require identical archives
	@./scripts/check_deps.sh dist
	@./scripts/dist.sh check

##@ Core & Build
install: all build/zbuild build/runtime.o build/runtime_hosted.o ## Install compiler, tools, runtime, stdlib, documentation, and man pages
	@$(MAKE) --no-print-directory install-files

# Copies what is already built and never builds: a gate staging an install must not rebuild or re-stamp build/ (a rebuild after bench/ turns the tree dirty changes the version string).
install-files:
	@for f in $(TARGET) $(ZILC) build/zbuild build/runtime.o build/runtime_hosted.o; do [ -f "$$f" ] || { echo "install-files: $$f is not built; run make install, or build it first" >&2; exit 1; }; done
	@for p in $(MAN_PAGES); do [ -f "$$p" ] || { echo "install: $$p is missing (the man pages are committed; regenerate with make man)" >&2; exit 1; }; done
	$(INSTALL_DIR) $(DESTDIR)$(BINDIR)
	$(INSTALL_PROGRAM) $(TARGET) $(DESTDIR)$(BINDIR)/zoril
	$(INSTALL_PROGRAM) $(ZILC) $(DESTDIR)$(BINDIR)/zilc
	$(INSTALL_PROGRAM) build/zbuild $(DESTDIR)$(BINDIR)/zbuild
	$(INSTALL_DIR) $(DESTDIR)$(LIBDIR)/zoril
	$(INSTALL_DATA) build/runtime.o $(DESTDIR)$(LIBDIR)/zoril/runtime.o
	$(INSTALL_DATA) build/runtime_hosted.o $(DESTDIR)$(LIBDIR)/zoril/runtime_hosted.o
	$(INSTALL_DATA) rt/runtime.s $(DESTDIR)$(LIBDIR)/zoril/runtime.s
	$(INSTALL_DIR) $(DESTDIR)$(DATADIR)/zoril/stdlib
	$(INSTALL_DATA) stdlib/*.zrl $(DESTDIR)$(DATADIR)/zoril/stdlib/
	for d in $(MAN_SUBDIRS); do $(INSTALL_DIR) $(DESTDIR)$(DATADIR)/zoril/stdlib/$$d && $(INSTALL_DATA) stdlib/$$d/*.zrl $(DESTDIR)$(DATADIR)/zoril/stdlib/$$d/; done
	$(INSTALL_DIR) $(DESTDIR)$(DOCDIR)
	$(INSTALL_DATA) README.md LICENSE NOTICE KNOWN_ISSUES.md CHANGELOG.md CONTRIBUTING.md $(DESTDIR)$(DOCDIR)/
	$(INSTALL_DIR) $(DESTDIR)$(DOCDIR)/doc
	$(INSTALL_DATA) doc/getting_started.md doc/dependencies.md doc/tour.md doc/SAFETY.md doc/developer_guide.md doc/ROADMAP.md doc/STABILITY.md doc/zero_overhead.md doc/reproducible_builds.md $(DESTDIR)$(DOCDIR)/doc/
	$(INSTALL_DIR) $(DESTDIR)$(MANDIR)/man1 $(DESTDIR)$(MANDIR)/man3 $(DESTDIR)$(MANDIR)/man7
	$(INSTALL_DATA) $(MAN_PAGES_1) $(DESTDIR)$(MANDIR)/man1/
	$(INSTALL_DATA) $(MAN_PAGES_3) $(DESTDIR)$(MANDIR)/man3/
	$(INSTALL_DATA) $(MAN_PAGES_7) $(DESTDIR)$(MANDIR)/man7/

uninstall: ## Uninstall compiler, tools, runtime, stdlib, documentation, and man pages
	rm -f $(DESTDIR)$(BINDIR)/zoril
	rm -f $(DESTDIR)$(BINDIR)/zilc
	rm -f $(DESTDIR)$(BINDIR)/zbuild
	rm -rf $(DESTDIR)$(LIBDIR)/zoril
	rm -rf $(DESTDIR)$(DATADIR)/zoril
	rm -rf $(DESTDIR)$(DOCDIR)
	rm -f $(patsubst doc/man/%.1,$(DESTDIR)$(MANDIR)/man1/%.1,$(MAN_PAGES_1))
	rm -f $(patsubst doc/man/%.3,$(DESTDIR)$(MANDIR)/man3/%.3,$(MAN_PAGES_3))
	rm -f $(patsubst doc/man/%.7,$(DESTDIR)$(MANDIR)/man7/%.7,$(MAN_PAGES_7))

clean: ## Remove build artifacts
	rm -rf build/
	rm -rf $(STAGE0_C_DIR)/build/
	-@rm -rf bootstrap/*/framework/lowered/ bootstrap/*/relowered/ bootstrap/*/build/ 2>/dev/null

# `make help` lists only these; `make help-all` lists every documented target and variable.
HELP_COMMON := all install uninstall clean help-all test test-changed test-fast test-checked test-docs \
	preflight-changed preflight PREFIX DESTDIR SYSTEM_ZORIL TSUITE T

help: HELP_ONLY = $(HELP_COMMON)
help: ## Show the common targets and variables
help-all: ## Show every target and variable
help help-all:
	@color=; [ -t 1 ] && color=1; \
	awk -v only='$(HELP_ONLY)' -v color="$$color" '\
		BEGIN { \
			num_sections = 0; num_vars = 0; cur_sec = ""; \
			num_keep = split(only, keep_list, " "); \
			filtered = num_keep > 0; \
			for (k = 1; k <= num_keep; k++) keep[keep_list[k]] = k; \
			on = color ? "\033[36m" : ""; off = color ? "\033[0m" : "" \
		} \
		/^##@ / { \
			cur_sec = substr($$0, 5); \
			if (!(cur_sec in sec_seen)) { sec_seen[cur_sec] = 1; sec_names[num_sections++] = cur_sec } \
			next \
		} \
		/^[a-zA-Z0-9_\/.-]+:.*## / { \
			if (cur_sec == "") cur_sec = "Other"; \
			match($$0, /^[a-zA-Z0-9_\/.-]+/); \
			target = substr($$0, RSTART, RLENGTH); \
			if (target in target_seen) next; \
			target_seen[target] = 1; \
			if (filtered && !(target in keep)) next; \
			if (!(cur_sec in sec_seen)) { sec_seen[cur_sec] = 1; sec_names[num_sections++] = cur_sec } \
			desc_idx = index($$0, "##"); \
			desc = substr($$0, desc_idx + 2); \
			gsub(/\$$\$$/, "$$", desc); \
			sub(/^[ \t]+/, "", desc); \
			n = filtered ? keep[target] : sec_count[cur_sec] + 0; \
			sec_count[cur_sec]++; \
			sec_targets[cur_sec, n] = target; \
			sec_descs[cur_sec, n] = desc; \
			next \
		} \
		/^##var[ \t]+/ { \
			line = substr($$0, 6); \
			sub(/^[ \t]+/, "", line); \
			match(line, /^[a-zA-Z0-9_]+/); \
			var = substr(line, RSTART, RLENGTH); \
			desc = substr(line, RSTART + RLENGTH); \
			gsub(/\$$\$$/, "$$", desc); \
			sub(/^[ \t]+/, "", desc); \
			if (var in var_seen) next; \
			var_seen[var] = 1; \
			if (filtered && !(var in keep)) next; \
			n = filtered ? keep[var] : num_vars; \
			var_names[n] = var; \
			var_descs[n] = desc; \
			num_vars++; \
			next \
		} \
		END { \
			printf "Usage: make [target] [VARIABLE=value]\n\nTargets:\n"; \
			for (s = 0; s < num_sections; s++) { \
				sec = sec_names[s]; \
				if (!sec_count[sec]) continue; \
				printf "  %s:\n", sec; \
				for (i = 0; i <= num_keep + sec_count[sec]; i++) { \
					if (!((sec, i) in sec_targets)) continue; \
					printf "    %s%-22s%s %s\n", on, sec_targets[sec, i], off, sec_descs[sec, i]; \
				} \
				print ""; \
			} \
			if (num_vars > 0) { \
				print "Variables:"; \
				for (i = 0; i <= num_keep + num_vars; i++) { \
					if (!(i in var_names)) continue; \
					printf "  %s%-20s%s %s\n", on, var_names[i], off, var_descs[i]; \
				} \
			} \
			if (filtered) printf "\nRun \047make help-all\047 for every target and variable.\n"; \
		} \
	' $(MAKEFILE_LIST)

.PHONY: $(GATES) all test test-changed test-fast stage0c-build install install-files uninstall clean help help-all dist dist-bin dist-check \
        selfhost-check selfhost-confirm selfhost-build-check repro-check mutation-check \
        stage0c-suites fuzz-short fuzz fuzz-release fuzz-calibrate preflight preflight-changed \
        md-fmt test-readme test-docs test-getting-started zbuild test-versions man test-man
