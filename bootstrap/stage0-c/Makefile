CC ?= cc
OPT = -O1
DEBUG = -g

# Function to check if a compiler flag is supported
check_flag = $(shell $(CC) -Werror $(1) -x c -E /dev/null -o /dev/null >/dev/null 2>&1 && echo $(1))

# Auto-detect if Valgrind is functional
HAS_VALGRIND := $(shell command -v valgrind >/dev/null 2>&1 && echo yes || echo no)
VALGRIND_WORKS := no
ifeq ($(HAS_VALGRIND),yes)
    VALGRIND_WORKS := $(if $(shell valgrind --quiet /bin/true 2>/dev/null && echo ok),yes,no)
endif

STRICT_FLAGS = -Wall -Wextra -Wpedantic -Werror -Wformat=2 -Wconversion -Wshadow -Wstrict-prototypes
STRICT_FLAGS += $(call check_flag,-Wno-gnu-zero-variadic-macro-arguments)
STRICT_FLAGS += $(call check_flag,-Wno-format-truncation)
STRICT_FLAGS += $(call check_flag,-Wno-stringop-truncation)
SECURITY_FLAGS = -fPIE -fstack-protector-strong -D_FORTIFY_SOURCE=2

QUIET ?= 0
export QUIET

GIT_HASH := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE := $(shell if [ -n "$$SOURCE_DATE_EPOCH" ]; then LC_ALL=C date -u -d "@$$SOURCE_DATE_EPOCH" '+%B %Y' 2>/dev/null || LC_ALL=C date -u -r "$$SOURCE_DATE_EPOCH" '+%B %Y' 2>/dev/null || date '+%B %Y'; else date '+%B %Y'; fi)
VERSION_SH := $(wildcard ../scripts/version.sh ../../scripts/version.sh)
VERSION_STR := $(shell if [ -n "$(VERSION_SH)" ]; then sh $(firstword $(VERSION_SH)) $$(dirname $$(dirname $(firstword $(VERSION_SH)))) 2>/dev/null; else echo "0.1.0-alpha"; fi)
VERSION_H = $(BUILD_DIR)/version.h
# cproc does not support -MMD -MP, gcc/clang optimization levels, or security/warning flags
ifeq ($(notdir $(firstword $(CC))),cproc)
    DEPFLAGS =
    SECURITY_FLAGS =
    STRICT_FLAGS =
    OPT =
    LDFLAGS ?=
else
    DEPFLAGS = -MMD -MP
    LDFLAGS ?= -pie
endif

CFLAGS = $(OPT) $(DEBUG) $(STRICT_FLAGS) $(SECURITY_FLAGS) -Iinclude -I$(BUILD_DIR) $(DEPFLAGS)

# cproc configuration
CPROC ?= cproc
CPROC_CFLAGS = $(DEBUG) -Iinclude -I$(BUILD_DIR)
CPROC_LDFLAGS =

# Standalone C preprocessor for cproc builds — set to mcpp (or tcc) for a gcc-free build.
# Note: we avoid the name CPP because GNU make has a built-in CPP = $(CC) -E that
# cannot be overridden with ?=, causing shell to try to exec "-E" as a command.
CPROC_CPP ?= cpp
MINIMAL_CPP ?= mcpp

LINK_CC ?= cc
MINIMAL_LINK_SEED ?= 1


SRC_DIR = src
BUILD_DIR = build
SCAN_DIR = $(BUILD_DIR)/scan
TEST_ARTIFACTS_DIR = $(BUILD_DIR)/tests
SCRIPTS_DIR = scripts
TEST_DIR = tests
TOP_ROOT ?= $(shell if [ -d ../../stdlib ]; then echo ../..; else echo ..; fi)

# Canonical toolchain variables
BACKEND_BIN ?= qbe
ASSEMBLER_BIN ?= as
LINKER_BIN ?= ld
export BACKEND_BIN
export ASSEMBLER_BIN
export LINKER_BIN
export LINK_CC
export CPROC
export MINIMAL_CPP

JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)
MAKEFLAGS += -j$(JOBS)

# Test timeouts
TIMEOUT_DUR ?= 10s
KILL_DUR ?= 2s
export TIMEOUT_DUR
export KILL_DUR

CONFIG_NAME = no_san
CC_NAME = $(notdir $(firstword $(CC)))
OBJ_DIR = $(BUILD_DIR)/obj/$(CC_NAME)/$(CONFIG_NAME)

# Sources and Objects
SRCS = $(wildcard $(SRC_DIR)/*.c)
OBJS = $(SRCS:$(SRC_DIR)/%.c=$(OBJ_DIR)/%.o)
DEPS = $(OBJS:.o=.d)

# Target executable
# Use specific names for different build types to avoid overwriting
TARGET ?= $(BUILD_DIR)/zoril-c
TARGET_BIN = $(TARGET)

all: $(VERSION_H) $(TARGET_BIN) $(BUILD_DIR)/zoril-c

-include $(DEPS)

# Regenerate build/version.h on every run (the version, git hash, and date are
# computed above each time) but replace it only when its content changes, so
# zoril-c.o is recompiled only when the reported version actually changes.
# The temp file is per-process: the stage0c gates run several makes here at once.
$(VERSION_H): FORCE
	@mkdir -p $(BUILD_DIR)
	@printf '#define VERSION "%s"\n#define GIT_HASH "%s"\n#define BUILD_DATE "%s"\n' "$(VERSION_STR)" "$(GIT_HASH)" "$(BUILD_DATE)" > $@.tmp.$$$$; \
	if cmp -s $@.tmp.$$$$ $@; then rm -f $@.tmp.$$$$; else mv -f $@.tmp.$$$$ $@; fi

ifneq ($(TARGET_BIN),$(BUILD_DIR)/zoril-c)
$(BUILD_DIR)/zoril-c: $(TARGET_BIN)
	@if [ ! -e $@ ] || [ "$$(readlink $@ 2>/dev/null)" != "$$(basename $(TARGET_BIN))" ]; then \
	    ln -sf $$(basename $(TARGET_BIN)) $@; \
	fi
endif

$(TARGET_BIN): $(OBJS)
	@mkdir -p $(BUILD_DIR)
	@$(CC) $(LDFLAGS) $^ -o $@.tmp && mv -f $@.tmp $@
	@if [ "$(QUIET)" -ne 1 ]; then echo "Successfully built $@"; fi

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	@$(CC) $(CFLAGS) -c $< -o $@

# zoril-c.o must be rebuilt whenever version.h changes (git hash or date).
$(OBJ_DIR)/zoril-c.o: $(VERSION_H)

.PHONY: help
help:
	@echo "Zoril Makefile targets:"
	@echo "  all                   Build the zoril-c executable (default)"
	@echo "  build-static          Build a statically-linked zoril-c executable"
	@echo "  clean                 Remove build artifacts"
	@echo "  distclean             Remove all build artifacts and the build directory"
	@echo "  cproc                 Build with cproc compiler"
	@echo "  help                  Show this help message"
	@echo "  lint                  Check for build artifacts outside the build directory"
	@echo "  release               Build optimized zoril-c executable"
	@echo "  minimal               Build with cproc + mcpp (no gcc/clang required)"
	@echo "  test_all              Run full CI pipeline (clean, build, all tests, static analysis)"
	@echo "  test_all_minimal      Run minimal-stack CI (cproc+mcpp, corpus, docs)"
	@echo "  test_bootstrap_requirements Run only critical tests required for bootstrapping"
	@echo "  test_corpus           Run all Zoril corpus examples"
	@echo "  test_docs             Verify code examples in documentation"
	@echo "  test_error_locations  Verify compiler error reporting"
	@echo "  test_infra            Verify test infrastructure can detect failures"
	@echo "  test_functional       Run end-to-end functional and bootstrap tests"
	@echo "  test_static_cppcheck  Run static analysis (cppcheck)"
	@echo "  test_static_scanbuild Run clang static analyzer (scan-build)"
	@echo "  test_unit             Build and run unit tests"
	@echo "  test_unit_cproc       Run tests with cproc compiler"
	@echo "  test_unit_valgrind    Run unit tests under Valgrind"
	@echo "  test_valgrind         Run Valgrind leak check on the zoril-c compiler"

.PHONY: test_all test_all_internal test_valgrind_binary test_valgrind_suite test_cproc_compatibility lint test_bootstrap_requirements test_bootstrap_requirements_internal

# The master CI target
test_all:
	@$(MAKE) --no-print-directory lint
	@$(MAKE) --no-print-directory QUIET=1 test_all_internal && \
	echo "=== ALL CHECKS PASSED ==="

.PHONY: test_all_internal
test_all_internal: test_unit test_corpus test_functional test_docs test_error_locations test_valgrind_suite test_static_scanbuild test_static_cppcheck

# Bootstrap requirements verification
test_bootstrap_requirements:
	@$(MAKE) --no-print-directory lint
	@$(MAKE) --no-print-directory QUIET=1 test_bootstrap_requirements_internal && \
	echo "=== ALL BOOTSTRAP REQUIREMENTS PASSED ==="

test_bootstrap_requirements_internal: test_bootstrap_unit test_corpus test_docs test_error_locations

lint:
	@if [ "$(QUIET)" -ne 1 ]; then echo "Checking for build artifacts outside build/..."; fi
	@FAILED=0; \
	UNTRACKED=$$(git ls-files --others --exclude-standard); \
	if [ -n "$$UNTRACKED" ]; then \
	    echo "Error: Untracked files found that are not in .gitignore:"; \
	    echo "$$UNTRACKED" | sed 's/^/  /'; \
	    FAILED=1; \
	fi; \
	IGNORED_OUTSIDE_BUILD=$$(git ls-files --others --ignored --exclude-standard | grep -v '^build/' | grep -v '^\.agent-data/' | grep -v '^\.claude/' | grep -v '^fuzz_data/' | grep -v '^chat.txt' || true); \
	if [ -n "$$IGNORED_OUTSIDE_BUILD" ]; then \
	    echo "Error: Ignored build artifacts found outside the build/ directory:"; \
	    echo "$$IGNORED_OUTSIDE_BUILD" | sed 's/^/  /'; \
	    FAILED=1; \
	fi; \
	if [ $$FAILED -eq 0 ]; then \
	    echo "test_lint: 1/1 passed"; \
	else \
	    echo "test_lint: 0/1 passed"; \
	    exit 1; \
	fi

.PHONY: test_fixed_bugs
test_fixed_bugs: release ## Gate: every fixed stage0-C bug in tests/fixed_bugs/ stays fixed (~2s)
	@QUIET=$(QUIET) ./scripts/test_fixed_bugs.sh

.PHONY: test_functional test_regressions
test_functional: $(BUILD_DIR)/zoril-c $(OBJS)
	@QUIET=$(QUIET) $(SCRIPTS_DIR)/test_functional.sh

test_regressions: test_functional

.PHONY: test_valgrind_binary
test_valgrind_binary: build-valgrind
	@if [ "$(QUIET)" -ne 1 ]; then echo "Running Valgrind on main binary..."; fi
	@mkdir -p $(BUILD_DIR)/test_tmp
	@touch $(BUILD_DIR)/test_tmp/empty.zil
	@((valgrind --leak-check=full --error-exitcode=2 --quiet $(BUILD_DIR)/zoril-c.valgrind --verify $(BUILD_DIR)/test_tmp/empty.zil -o /dev/null > /dev/null 2>&1 && \
	  echo "fn main() { let x = 0; }" > $(BUILD_DIR)/test_tmp/test_val.zrl && \
	  valgrind --leak-check=full --error-exitcode=2 --quiet $(BUILD_DIR)/zoril-c.valgrind $(BUILD_DIR)/test_tmp/test_val.zrl -o /dev/null > /dev/null 2>&1 && \
	  echo "test_valgrind_binary: 1/1 passed") || (echo "test_valgrind_binary: 0/1 passed" && exit 1))
	@rm -rf $(BUILD_DIR)/test_tmp

.PHONY: test_valgrind_suite
test_valgrind_suite:
ifeq ($(VALGRIND_WORKS),yes)
	@if [ "$(QUIET)" -ne 1 ]; then echo "Running Valgrind on test suite subset..."; fi
	@($(MAKE) --no-print-directory -C $(TEST_DIR) CC="$(CC)" LDFLAGS="" PURPOSE=valgrind valgrind-quiet) || \
	  (echo "test_valgrind_suite: 0/6 passed" && exit 1)
else
	@if [ "$(QUIET)" -ne 1 ]; then echo "[SKIP] test_valgrind_suite (Valgrind not functional on this host)"; fi
endif

.PHONY: test_cproc_compatibility
test_cproc_compatibility:
	@if ! command -v $(CPROC) > /dev/null 2>&1; then \
	    if [ "$(QUIET)" -ne 1 ]; then echo "[SKIP] test_cproc_compatibility (CProc not found)"; fi; \
	    exit 0; \
	fi
	@if [ "$(QUIET)" -ne 1 ]; then echo "Checking CProc compatibility..."; fi
	@(( $(MAKE) --no-print-directory cproc > /dev/null 2>&1 && \
	    $(MAKE) --no-print-directory -C $(TEST_DIR) CC=$(CPROC) LDFLAGS="" PURPOSE=cproc STRICT_FLAGS="-Wall -Werror" SECURITY_FLAGS="-I../include" QUIET=$(QUIET) cproc-smoke ) || \
	  (echo "[FAIL] test_cproc_compatibility" && exit 1))

.PHONY: test_infra
test_infra:
	@((if [ "$(QUIET)" -ne 1 ]; then CC="$(CC)" ./scripts/verify_test_failure.sh; else CC="$(CC)" ./scripts/verify_test_failure.sh > /dev/null 2>&1; fi) && \
	  echo "test_infra: 1/1 passed") || (echo "test_infra: 0/1 passed" && exit 1)

.PHONY: build-valgrind
build-valgrind:
	@$(MAKE) --no-print-directory LDFLAGS="" TARGET=$(BUILD_DIR)/zoril-c.valgrind all

.PHONY: release
release:
	@$(MAKE) --no-print-directory LDFLAGS="" OPT="-O3" DEBUG="" TARGET=$(BUILD_DIR)/zoril-c.release all

.PHONY: build-static
build-static:
	@$(MAKE) --no-print-directory LDFLAGS="-static" TARGET=$(BUILD_DIR)/zoril-c.static all

.PHONY: test_static_cppcheck
test_static_cppcheck:
	@if [ "$(QUIET)" -ne 1 ]; then echo "Running static analysis (cppcheck)..."; fi
	@mkdir -p $(SCAN_DIR)
	@((cppcheck --language=c --std=c11 --enable=warning,style,performance,portability --error-exitcode=1 \
		-j $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4) \
		--suppress=missingIncludeSystem \
		--suppress=normalCheckLevelMaxBranches \
		--suppress=checkersReport \
		--suppress=unmatchedSuppression \
		--suppress=unusedFunction \
		--suppress=constVariablePointer \
		--suppress=variableScope \
		--suppress=knownConditionTrueFalse \
		--suppress=nullPointerOutOfMemory \
		--suppress=nullPointerOutOfResources \
		--suppress=redundantAssignment \
		--suppress=intToPointerCast \
		--suppress=constParameterPointer \
		--suppress=constParameterCallback \
		--suppress=constStatement \
		-I include $(SRC_DIR) $(TEST_DIR) > $(SCAN_DIR)/cppcheck.log 2>&1 && \
	  echo "test_static_cppcheck: 1/1 passed") || (cat $(SCAN_DIR)/cppcheck.log && echo "test_static_cppcheck: 0/1 passed" && exit 1))

.PHONY: test_static_scanbuild
test_static_scanbuild:
	@if [ "$(QUIET)" -ne 1 ]; then echo "Running scan-build..."; fi
	@mkdir -p $(SCAN_DIR)
	@rm -rf $(SCAN_DIR)/scan-build-report
	@rm -rf $(SCAN_DIR)/build
	@((scan-build --status-bugs --use-cc=$(CC) -o $(SCAN_DIR)/scan-build-report \
		$(MAKE) --no-print-directory LDFLAGS="" BUILD_DIR=$(SCAN_DIR)/build all > $(SCAN_DIR)/scan-build.log 2>&1 && \
	  echo "test_static_scanbuild: 1/1 passed") || (cat $(SCAN_DIR)/scan-build.log && echo "test_static_scanbuild: 0/1 passed" && exit 1))

.PHONY: test_valgrind
test_valgrind:
ifeq ($(VALGRIND_WORKS),yes)
	@$(MAKE) LDFLAGS="" clean all
	@mkdir -p $(BUILD_DIR)/test_tmp
	@touch $(BUILD_DIR)/test_tmp/empty.zil
	valgrind --leak-check=full --show-leak-kinds=all --error-exitcode=2 $(TARGET) --verify $(BUILD_DIR)/test_tmp/empty.zil -o $(BUILD_DIR)/test_tmp/valgrind_test.out
	@rm -rf $(BUILD_DIR)/test_tmp
else
	@if [ "$(QUIET)" -ne 1 ]; then echo "[SKIP] test_valgrind (Valgrind not functional on this host)"; fi
endif

.PHONY: test_unit_valgrind
test_unit_valgrind:
	@$(MAKE) -C $(TEST_DIR) CC="$(CC)" LDFLAGS="" clean valgrind

.PHONY: cproc
cproc: $(VERSION_H)
	@mkdir -p $(BUILD_DIR)
	@CPP=$(CPROC_CPP) $(CPROC) $(CPROC_CFLAGS) $(SRCS) -o $(BUILD_DIR)/zoril-c.cproc.tmp $(CPROC_LDFLAGS) && mv -f $(BUILD_DIR)/zoril-c.cproc.tmp $(BUILD_DIR)/zoril-c.cproc
	@if [ "$(QUIET)" -ne 1 ]; then echo "Successfully built build/zoril-c.cproc"; fi

.PHONY: FORCE
FORCE:

$(BUILD_DIR)/bin/cpp: FORCE
	@mkdir -p $(BUILD_DIR)/bin
	@printf '#!/bin/sh\ncmd="%s"\ncase "$$cmd" in\n    *mcpp*)\n        args=""\n        for a in "$$@"; do\n            case "$$a" in\n                -undef) args="$$args -N" ;;\n                *) args="$$args $$a" ;;\n            esac\n        done\n        musl_inc=""\n        if [ -d /usr/lib/musl/include ]; then\n            musl_inc="-I /usr/lib/musl/include"\n        elif [ -d /usr/include/musl ]; then\n            musl_inc="-I /usr/include/musl"\n        elif [ -d /usr/include/x86_64-linux-musl ]; then\n            musl_inc="-I /usr/include/x86_64-linux-musl"\n        fi\n        exec $$cmd -e utf8 $$musl_inc $$args ;;\n    *)\n        exec $$cmd "$$@" ;;\nesac\n' "$(MINIMAL_CPP)" > $@.tmp
	@chmod +x $@.tmp
	@if cmp -s $@.tmp $@ 2>/dev/null; then rm -f $@.tmp; else mv $@.tmp $@; fi

$(BUILD_DIR)/bin/qbe: FORCE
	@mkdir -p $(BUILD_DIR)/bin
	@case "$(BACKEND_BIN)" in \
	    */*) \
	        _cmd="$$(cd "$$(dirname "$(BACKEND_BIN)")" 2>/dev/null && pwd)/$$(basename "$(BACKEND_BIN)")"; \
	        printf '#!/bin/sh\nexec "%s" "$$@"\n' "$$_cmd" > $@.tmp && \
	        chmod +x $@.tmp && \
	        if cmp -s $@.tmp $@ 2>/dev/null; then rm -f $@.tmp; else mv $@.tmp $@; fi ;; \
	    *) rm -f $@ ;; \
	esac

$(BUILD_DIR)/bin/as: FORCE
	@mkdir -p $(BUILD_DIR)/bin
	@case "$(ASSEMBLER_BIN)" in \
	    */*) \
	        _cmd="$$(cd "$$(dirname "$(ASSEMBLER_BIN)")" 2>/dev/null && pwd)/$$(basename "$(ASSEMBLER_BIN)")"; \
	        printf '#!/bin/sh\nexec "%s" "$$@"\n' "$$_cmd" > $@.tmp && \
	        chmod +x $@.tmp && \
	        if cmp -s $@.tmp $@ 2>/dev/null; then rm -f $@.tmp; else mv $@.tmp $@; fi ;; \
	    *) rm -f $@ ;; \
	esac

$(BUILD_DIR)/bin/ld: FORCE
	@mkdir -p $(BUILD_DIR)/bin
	@case "$(LINKER_BIN)" in \
	    */*) \
	        _cmd="$$(cd "$$(dirname "$(LINKER_BIN)")" 2>/dev/null && pwd)/$$(basename "$(LINKER_BIN)")"; \
	        printf '#!/bin/sh\nexec "%s" "$$@"\n' "$$_cmd" > $@.tmp && \
	        chmod +x $@.tmp && \
	        if cmp -s $@.tmp $@ 2>/dev/null; then rm -f $@.tmp; else mv $@.tmp $@; fi ;; \
	    *) rm -f $@ ;; \
	esac

.PHONY: minimal
minimal: $(VERSION_H) $(BUILD_DIR)/bin/cpp $(BUILD_DIR)/bin/qbe $(BUILD_DIR)/bin/as $(BUILD_DIR)/bin/ld
	@command -v $(CPROC) > /dev/null 2>&1 || (echo "ERROR: $(CPROC) not found — install $(CPROC)" && exit 1)
	@command -v $(firstword $(MINIMAL_CPP)) > /dev/null 2>&1 || \
	    (echo "ERROR: $(firstword $(MINIMAL_CPP)) not found — install a standalone C preprocessor (mcpp recommended; tcc also works with MINIMAL_CPP='tcc -E')" && exit 1)
	@case "$(MINIMAL_CPP)" in \
	    *mcpp*) \
	        if [ ! -d /usr/lib/musl/include ] && [ ! -d /usr/include/musl ] && [ ! -d /usr/include/x86_64-linux-musl ]; then \
	            echo "ERROR: musl include headers not found (checked /usr/lib/musl/include, /usr/include/musl, /usr/include/x86_64-linux-musl) — install musl development headers:" && \
	            echo "  Alpine:        apk add musl-dev" && \
	            echo "  Debian/Ubuntu: apt install musl-tools musl-dev" && \
	            echo "  Arch:          pacman -S musl" && \
	            exit 1; \
	        fi ;; \
	esac
	@mkdir -p $(BUILD_DIR)
	@PATH="$(CURDIR)/$(BUILD_DIR)/bin:$$PATH" $(CPROC) $(CPROC_CFLAGS) $(SRCS) -o $(BUILD_DIR)/zoril-c.minimal.tmp $(CPROC_LDFLAGS) && mv -f $(BUILD_DIR)/zoril-c.minimal.tmp $(BUILD_DIR)/zoril-c.minimal
	@if [ "$(MINIMAL_LINK_SEED)" -eq 1 ]; then \
	    ln -sf zoril-c.minimal $(BUILD_DIR)/zoril-c.release; \
	    ln -sf zoril-c.minimal $(BUILD_DIR)/zoril-c; \
	    touch -h $(BUILD_DIR)/zoril-c.release $(BUILD_DIR)/zoril-c 2>/dev/null || touch $(BUILD_DIR)/zoril-c.minimal; \
	else \
	    if [ ! -e $(BUILD_DIR)/zoril-c.release ]; then \
	        ln -sf zoril-c.minimal $(BUILD_DIR)/zoril-c.release; \
	    fi; \
	    if [ ! -e $(BUILD_DIR)/zoril-c ]; then \
	        ln -sf zoril-c.minimal $(BUILD_DIR)/zoril-c; \
	    fi; \
	fi
	@if [ "$(QUIET)" -ne 1 ]; then echo "Successfully built build/zoril-c.minimal (minimal stack: cproc + $(MINIMAL_CPP))"; fi


.PHONY: test_unit_cproc
test_unit_cproc:
	@$(MAKE) --no-print-directory -C $(TEST_DIR) CC=$(CPROC) LDFLAGS="" STRICT_FLAGS="" SECURITY_FLAGS="-I../include" QUIET=$(QUIET) cproc-smoke

# Minimal-stack CI: corpus + docs + full cproc unit suite. No clang/sanitizers/valgrind.
.PHONY: test_all_minimal
test_all_minimal:
	@$(MAKE) --no-print-directory QUIET=1 test_all_minimal_internal
	@echo "=== MINIMAL BUILD: ALL CHECKS PASSED ==="

.PHONY: test_all_minimal_internal
test_all_minimal_internal: minimal
	@ZORIL_BIN=$(CURDIR)/$(BUILD_DIR)/zoril-c.minimal PATH="$(CURDIR)/$(BUILD_DIR)/bin:$$PATH" $(MAKE) --no-print-directory -C $(TEST_DIR) \
	    CC=$(CPROC) LDFLAGS="" PURPOSE=minimal STRICT_FLAGS="-Wall -Werror" SECURITY_FLAGS="-I../include" \
	    QUIET=$(QUIET) cproc-full
	@ZORIL_BIN=$(BUILD_DIR)/zoril-c.minimal QUIET=$(QUIET) $(SCRIPTS_DIR)/test_functional.sh
	@ZORIL_BIN=$(BUILD_DIR)/zoril-c.minimal QUIET=$(QUIET) $(SCRIPTS_DIR)/test_corpus.sh
	@ZORIL_BIN=$(BUILD_DIR)/zoril-c.minimal QUIET=$(QUIET) $(SCRIPTS_DIR)/test_docs.sh $(TOP_ROOT)/doc/spec/surface_syntax.md $(TOP_ROOT)/doc/spec/intermediate_language.md
	@ZORIL_BIN=$(BUILD_DIR)/zoril-c.minimal QUIET=$(QUIET) $(SCRIPTS_DIR)/test_error_locations.sh

.PHONY: test_error_locations
test_error_locations: $(BUILD_DIR)/zoril-c $(OBJS)
	@QUIET=$(QUIET) $(SCRIPTS_DIR)/test_error_locations.sh

.PHONY: test_corpus
test_corpus: $(BUILD_DIR)/zoril-c $(OBJS)
	@QUIET=$(QUIET) $(SCRIPTS_DIR)/test_corpus.sh

.PHONY: test_docs
test_docs: $(BUILD_DIR)/zoril-c $(OBJS)
	@QUIET=$(QUIET) $(SCRIPTS_DIR)/test_docs.sh $(TOP_ROOT)/doc/spec/surface_syntax.md $(TOP_ROOT)/doc/spec/intermediate_language.md

.PHONY: test_unit
test_unit: $(BUILD_DIR)/zoril-c $(OBJS)
	@($(MAKE) --no-print-directory -j1 -k -C $(TEST_DIR) CC="$(CC)" PURPOSE=unit QUIET=$(QUIET) || $(MAKE) --no-print-directory -j1 -C $(TEST_DIR) CC="$(CC)" PURPOSE=unit QUIET=$(QUIET) print_summary)

.PHONY: test_bootstrap_unit
test_bootstrap_unit: $(BUILD_DIR)/zoril-c $(OBJS)
	@($(MAKE) --no-print-directory -j1 -k -C $(TEST_DIR) CC="$(CC)" PURPOSE=bootstrap QUIET=$(QUIET) test_bootstrap_unit || $(MAKE) --no-print-directory -j1 -C $(TEST_DIR) CC="$(CC)" PURPOSE=bootstrap QUIET=$(QUIET) print_bootstrap_summary)

.PHONY: clean distclean
clean:
	rm -f $(BUILD_DIR)/zoril-c* $(BUILD_DIR)/*.log $(BUILD_DIR)/zoril-c $(BUILD_DIR)/*.ssa $(BUILD_DIR)/version.h $(BUILD_DIR)/memcpy_test*
	rm -f a.out a.out.s a.out.ssa
	rm -rf $(BUILD_DIR)/obj $(BUILD_DIR)/scan $(BUILD_DIR)/tests $(BUILD_DIR)/corpus $(BUILD_DIR)/bin
	rm -rf $(TEST_ARTIFACTS_DIR)
	rm -f tests/*.o tests/*.ssa tests/*.s tests/*.d tests/*_bin tests/vgcore.* tests/a.out tests/test_arg_copy.ssa.ssa
	rm -f tests/unit/*.o tests/unit/*.ssa tests/unit/*.s tests/unit/*.d tests/unit/*_bin tests/unit/vgcore.* tests/unit/a.out
	find tests/regressions tests/functional tests/bootstrap -type f \( -name "*.o" -o -name "*.ssa" -o -name "*.s" -o -name "*.d" -o -name "*_bin" -o -name "vgcore.*" -o -name "a.out" \) -delete 2>/dev/null || true
	@$(MAKE) --no-print-directory -C $(TEST_DIR) clean > /dev/null 2>&1 || true

distclean: clean
	rm -rf $(BUILD_DIR)
