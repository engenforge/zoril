CC ?= cc
OPT ?= -O1
DEBUG ?= -g

# Default to no sanitizers
SANITIZERS ?=

# Function to check if a compiler flag is supported
check_flag = $(shell $(CC) $(1) -x c -E /dev/null -o /dev/null >/dev/null 2>&1 && echo $(1))

# We use override to append to STRICT_FLAGS if it's passed from the environment,
# or define it if not. But here it's easier to just use a local variable and
# allow override via ?= if needed, but we want the dynamic part to work.
STRICT_FLAGS ?= -Wall -Wextra -Wpedantic -Werror -Wformat=2 -Wconversion -Wshadow -Wstrict-prototypes
STRICT_FLAGS += $(call check_flag,-Wno-gnu-zero-variadic-macro-arguments)
STRICT_FLAGS += $(call check_flag,-Wno-format-truncation)
STRICT_FLAGS += $(call check_flag,-Wno-stringop-truncation)
SECURITY_FLAGS ?= -fPIE -fstack-protector-strong -D_FORTIFY_SOURCE=2

QUIET ?= 0
export QUIET

# Canonical toolchain variables
BACKEND_BIN ?= qbe
ASSEMBLER_BIN ?= as
LINKER_BIN ?= ld
LINK_CC ?= cc
export BACKEND_BIN
export ASSEMBLER_BIN
export LINKER_BIN
export LINK_CC

GIT_HASH := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
# cproc does not support -MMD -MP (dependency file generation)
ifeq ($(notdir $(firstword $(CC))),cproc)
    DEPFLAGS =
    STRICT_FLAGS =
    SECURITY_FLAGS =
    OPT =
    LDFLAGS =
else
    DEPFLAGS = -MMD -MP
    LDFLAGS = -pie $(SANITIZERS)
endif
CFLAGS = $(OPT) $(DEBUG) $(STRICT_FLAGS) $(SECURITY_FLAGS) $(SANITIZERS) -I../include -I../src -Iunit -Ihelpers -DGIT_HASH=\"$(GIT_HASH)\" $(DEPFLAGS)

# Build directories
CONFIG_NAME = release

CC_NAME = $(notdir $(firstword $(CC)))
SRC_DIR = ../src
UNIT_DIR = unit
BASE_BUILD_DIR = ../build/tests
PURPOSE ?= unit
OBJ_DIR = $(BASE_BUILD_DIR)/obj/$(CC_NAME)/$(CONFIG_NAME)/$(PURPOSE)
BIN_DIR = $(BASE_BUILD_DIR)/bin/$(CC_NAME)/$(CONFIG_NAME)/$(PURPOSE)
TMP_DIR = $(BASE_BUILD_DIR)/tmp/$(CC_NAME)/$(PURPOSE)

# Allow overriding the base results directory for parallel isolation
RESULTS_BASE ?= $(BASE_BUILD_DIR)/results
RESULTS_DIR = $(RESULTS_BASE)/$(CC_NAME)/$(CONFIG_NAME)/$(PURPOSE)

export TEST_RESULTS_DIR := $(RESULTS_DIR)

# Source files from src/ (only those needed for tests)
SRCS = $(filter-out $(SRC_DIR)/zoril-c.c, $(wildcard $(SRC_DIR)/*.c))
# Use a separate object directory for project objects built by tests
# to avoid race conditions with the main Makefile when running in parallel.
PROJECT_OBJ_DIR = $(BASE_BUILD_DIR)/project_obj/$(CC_NAME)/$(CONFIG_NAME)/$(PURPOSE)
OBJS = $(SRCS:$(SRC_DIR)/%.c=$(PROJECT_OBJ_DIR)/%.o)
OBJS_DEPS = $(OBJS:.o=.d)

# Test source files
TEST_SRCS = $(wildcard $(UNIT_DIR)/*.c)
TEST_BINS = $(TEST_SRCS:$(UNIT_DIR)/%.c=$(BIN_DIR)/%)
TEST_DEPS = $(TEST_SRCS:$(UNIT_DIR)/%.c=$(OBJ_DIR)/%.d)

all: run_tests

-include $(OBJS_DEPS)
-include $(TEST_DEPS)

# Pattern rule for objects from src/
$(PROJECT_OBJ_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	@$(CC) $(CFLAGS) -c $< -o $@

$(BIN_DIR)/%: $(UNIT_DIR)/%.c $(OBJS)
	@mkdir -p $(dir $@)
	@mkdir -p $(OBJ_DIR)
	@mkdir -p $(TMP_DIR)
	@$(CC) $(LDFLAGS) $(CFLAGS) -DTEST_TMP_DIR=\"$(TMP_DIR)\" $(if $(DEPFLAGS),-MF $(OBJ_DIR)/$*.d) $< $(OBJS) -o $@

TEST_NAMES = $(TEST_SRCS:$(UNIT_DIR)/%.c=%)
BOOTSTRAP_UNIT_TESTS = $(TEST_NAMES)

# Define explicit rules for each test target
define TEST_RULE
run-$(1): $(BIN_DIR)/$(1) | prepare-results
	@QUIET=$(QUIET) ../scripts/test_wrapper.sh ./$$<

valgrind-$(1): $(BIN_DIR)/$(1) | prepare-results
	@QUIET=$(QUIET) ../scripts/test_wrapper.sh valgrind --leak-check=full --error-exitcode=1 --quiet ./$$<
endef

$(foreach test,$(TEST_NAMES),$(eval $(call TEST_RULE,$(test))))

.PHONY: prepare-results
prepare-results:
	@mkdir -p $(RESULTS_DIR)

# Helper to print summary for a subset of tests
# Usage: $(call PRINT_SUMMARY,target_name,test_names)
define PRINT_SUMMARY
	@TOTAL=$(words $(2)); \
	 PASS=0; \
	 SKIP=0; \
	 RDIR=$(TEST_RESULTS_DIR); \
	 if [ -z "$$RDIR" ]; then RDIR=$(RESULTS_DIR); fi; \
	 for t in $(2); do \
	     if [ -f "$$RDIR/$$t.pass" ]; then PASS=$$((PASS + 1)); \
	     elif [ -f "$$RDIR/$$t.skip" ]; then SKIP=$$((SKIP + 1)); fi; \
	 done; \
	 if [ $$((PASS + SKIP)) -eq $$TOTAL ]; then \
	     if [ $$SKIP -gt 0 ]; then \
	         printf "%s: %d/%d passed, %d skipped\n" $(1) $$PASS $$TOTAL $$SKIP; \
	     else \
	         printf "%s: %d/%d passed\n" $(1) $$PASS $$TOTAL; \
	     fi; \
	 else \
	     if [ $$SKIP -gt 0 ]; then \
	         printf "%s: %d/%d passed, %d skipped\n" $(1) $$PASS $$TOTAL $$SKIP; \
	     else \
	         printf "%s: %d/%d passed\n" $(1) $$PASS $$TOTAL; \
	     fi; \
	     exit 1; \
	 fi
endef

.PHONY: run_tests $(TEST_NAMES:%=run-%)
run_tests: $(TEST_NAMES:%=run-%)
	@PASS=0; \
	SKIP=0; \
	TOTAL=$(words $(TEST_NAMES)); \
	for t in $(TEST_NAMES); do \
	    if [ -f "$(RESULTS_DIR)/$$t.pass" ]; then PASS=$$((PASS + 1)); \
	    elif [ -f "$(RESULTS_DIR)/$$t.skip" ]; then SKIP=$$((SKIP + 1)); fi; \
	done; \
	if [ $$((PASS + SKIP)) -ne $$TOTAL ]; then \
	    $(MAKE) --no-print-directory print_summary; \
	elif [ "$(QUIET)" != "1" ]; then \
	    $(MAKE) --no-print-directory print_summary; \
	else \
	    if [ $$SKIP -gt 0 ]; then \
	        printf "test_unit: %d/%d passed, %d skipped\n" $$PASS $$TOTAL $$SKIP; \
	    else \
	        printf "test_unit: %d/%d passed\n" $$PASS $$TOTAL; \
	    fi; \
	fi

.PHONY: test_bootstrap_unit
test_bootstrap_unit: $(BOOTSTRAP_UNIT_TESTS:%=run-%)
	@PASS=0; \
	SKIP=0; \
	TOTAL=$(words $(BOOTSTRAP_UNIT_TESTS)); \
	for t in $(BOOTSTRAP_UNIT_TESTS); do \
	    if [ -f "$(RESULTS_DIR)/$$t.pass" ]; then PASS=$$((PASS + 1)); \
	    elif [ -f "$(RESULTS_DIR)/$$t.skip" ]; then SKIP=$$((SKIP + 1)); fi; \
	done; \
	if [ $$((PASS + SKIP)) -ne $$TOTAL ]; then \
	    $(MAKE) --no-print-directory print_bootstrap_summary; \
	elif [ "$(QUIET)" != "1" ]; then \
	    $(MAKE) --no-print-directory print_bootstrap_summary; \
	else \
	    if [ $$SKIP -gt 0 ]; then \
	        printf "test_bootstrap_unit: %d/%d passed, %d skipped\n" $$PASS $$TOTAL $$SKIP; \
	    else \
	        printf "test_bootstrap_unit: %d/%d passed\n" $$PASS $$TOTAL; \
	    fi; \
	fi

.PHONY: print_bootstrap_summary
print_bootstrap_summary:
	@TOTAL=$(words $(BOOTSTRAP_UNIT_TESTS)); \
	 PASS=0; \
	 SKIP=0; \
	 for t in $(BOOTSTRAP_UNIT_TESTS); do \
	     if [ -f "$(RESULTS_DIR)/$$t.pass" ]; then PASS=$$((PASS + 1)); \
	     elif [ -f "$(RESULTS_DIR)/$$t.skip" ]; then SKIP=$$((SKIP + 1)); fi; \
	 done; \
	 if [ $$((PASS + SKIP)) -eq $$TOTAL ]; then \
	     if [ $$SKIP -gt 0 ]; then \
	         printf "test_bootstrap_unit: %d/%d passed, %d skipped\n" $$PASS $$TOTAL $$SKIP; \
	     else \
	         printf "test_bootstrap_unit: %d/%d passed\n" $$PASS $$TOTAL; \
	     fi; \
	 else \
	     if [ $$SKIP -gt 0 ]; then \
	         printf "test_bootstrap_unit: %d/%d passed, %d skipped\n" $$PASS $$TOTAL $$SKIP; \
	     else \
	         printf "test_bootstrap_unit: %d/%d passed\n" $$PASS $$TOTAL; \
	     fi; \
	     FAILS=""; \
	     for t in $(BOOTSTRAP_UNIT_TESTS); do \
	         if [ -f "$(RESULTS_DIR)/$$t.fail" ]; then FAILS="$$FAILS $(RESULTS_DIR)/$$t.fail"; fi; \
	     done; \
	     if [ -n "$$FAILS" ]; then \
	         printf "\nFailed bootstrap unit test suites:\n"; \
	         for f in $$FAILS; do \
	             printf "  --- %s ---\n" "$$(basename $$f .fail)"; \
	             cat "$$f"; \
	             printf "  ---\n\n"; \
	         done; \
	     else \
	         printf "\nSome bootstrap tests failed to build or run correctly (check logs above).\n\n"; \
	     fi; \
	     exit 1; \
	 fi

# print_summary: always-runnable target used by check-all after --keep-going runs.
# Prints the pass/fail count and dumps failure details so they appear at the end.
.PHONY: print_summary
print_summary:
	@TOTAL=$(words $(TEST_NAMES)); \
	 PASS=0; \
	 SKIP=0; \
	 for t in $(TEST_NAMES); do \
	     if [ -f "$(RESULTS_DIR)/$$t.pass" ]; then PASS=$$((PASS + 1)); \
	     elif [ -f "$(RESULTS_DIR)/$$t.skip" ]; then SKIP=$$((SKIP + 1)); fi; \
	 done; \
	 if [ $$((PASS + SKIP)) -eq $$TOTAL ]; then \
	     if [ $$SKIP -gt 0 ]; then \
	         printf "test_unit: %d/%d passed, %d skipped\n" $$PASS $$TOTAL $$SKIP; \
	     else \
	         printf "test_unit: %d/%d passed\n" $$PASS $$TOTAL; \
	     fi; \
	 else \
	     if [ $$SKIP -gt 0 ]; then \
	         printf "test_unit: %d/%d passed, %d skipped\n" $$PASS $$TOTAL $$SKIP; \
	     else \
	         printf "test_unit: %d/%d passed\n" $$PASS $$TOTAL; \
	     fi; \
	     FAILS=""; \
	     for t in $(TEST_NAMES); do \
	         if [ -f "$(RESULTS_DIR)/$$t.fail" ]; then FAILS="$$FAILS $(RESULTS_DIR)/$$t.fail"; fi; \
	     done; \
	     if [ -n "$$FAILS" ]; then \
	         printf "\nFailed test suites:\n"; \
	         for f in $$FAILS; do \
	             printf "  --- %s ---\n" "$$(basename $$f .fail)"; \
	             cat "$$f"; \
	             printf "  ---\n\n"; \
	         done; \
	     else \
	         printf "\nSome tests failed to build or run correctly (check logs above).\n\n"; \
	     fi; \
	     exit 1; \
	 fi

VALGRIND_SUBSET = test_il test_box_struct test_generics test_string_literal_leak test_recursive_types test_ownership
VALGRIND_TARGETS = $(VALGRIND_SUBSET:%=valgrind-%)

.PHONY: valgrind-quiet
valgrind-quiet:
	@$(MAKE) --no-print-directory CC="$(CC)" SANITIZERS="$(SANITIZERS)" $(VALGRIND_TARGETS)
	@$(MAKE) --no-print-directory CC="$(CC)" SANITIZERS="$(SANITIZERS)" ACTUAL_PRINT_VALGRIND_SUMMARY

.PHONY: ACTUAL_PRINT_VALGRIND_SUMMARY
ACTUAL_PRINT_VALGRIND_SUMMARY:
	@TOTAL=$(words $(VALGRIND_SUBSET)); \
	 PASS=0; \
	 for t in $(VALGRIND_SUBSET); do \
	     if [ -f "$(RESULTS_DIR)/valgrind ($$t).pass" ]; then PASS=$$((PASS + 1)); fi; \
	 done; \
	 if [ $$PASS -eq $$TOTAL ]; then \
	     printf "test_valgrind_suite: %d/%d passed\n" $$PASS $$TOTAL; \
	 else \
	     printf "test_valgrind_suite: %d/%d passed\n" $$PASS $$TOTAL; \
	     exit 1; \
	 fi

.PHONY: clean
clean:
	rm -rf $(BASE_BUILD_DIR)/obj $(BASE_BUILD_DIR)/bin $(BASE_BUILD_DIR)/results

CPROC_SUBSET = test_lexer test_parser test_lower test_e2e test_generics
CPROC_TARGETS = $(CPROC_SUBSET:%=run-%)

.PHONY: cproc-smoke
cproc-smoke:
	@$(MAKE) --no-print-directory $(CPROC_TARGETS)
	@TOTAL=$(words $(CPROC_SUBSET)); \
	 PASS=0; \
	 SKIP=0; \
	 for t in $(CPROC_SUBSET); do \
	     if [ -f "$(RESULTS_DIR)/$$t.pass" ]; then PASS=$$((PASS + 1)); \
	     elif [ -f "$(RESULTS_DIR)/$$t.skip" ]; then SKIP=$$((SKIP + 1)); fi; \
	 done; \
	 if [ $$((PASS + SKIP)) -eq $$TOTAL ]; then \
	     if [ $$SKIP -gt 0 ]; then \
	         printf "test_cproc_compatibility: %d/%d passed, %d skipped\n" $$PASS $$TOTAL $$SKIP; \
	     else \
	         printf "test_cproc_compatibility: %d/%d passed\n" $$PASS $$TOTAL; \
	     fi; \
	 else \
	     if [ $$SKIP -gt 0 ]; then \
	         printf "test_cproc_compatibility: %d/%d passed, %d skipped\n" $$PASS $$TOTAL $$SKIP; \
	     else \
	         printf "test_cproc_compatibility: %d/%d passed\n" $$PASS $$TOTAL; \
	     fi; \
	     exit 1; \
	 fi

# cproc-full: run the complete unit suite via cproc (used by test_all_minimal).
.PHONY: cproc-full
cproc-full:
	@$(MAKE) --no-print-directory $(TEST_NAMES:%=run-%)
	@TOTAL=$(words $(TEST_NAMES)); \
	 PASS=0; \
	 SKIP=0; \
	 for t in $(TEST_NAMES); do \
	     if [ -f "$(RESULTS_DIR)/$$t.pass" ]; then PASS=$$((PASS + 1)); \
	     elif [ -f "$(RESULTS_DIR)/$$t.skip" ]; then SKIP=$$((SKIP + 1)); fi; \
	 done; \
	 if [ $$((PASS + SKIP)) -eq $$TOTAL ]; then \
	     if [ $$SKIP -gt 0 ]; then \
	         printf "test_cproc_full: %d/%d passed, %d skipped\n" $$PASS $$TOTAL $$SKIP; \
	     else \
	         printf "test_cproc_full: %d/%d passed\n" $$PASS $$TOTAL; \
	     fi; \
	 else \
	     if [ $$SKIP -gt 0 ]; then \
	         printf "test_cproc_full: %d/%d passed, %d skipped\n" $$PASS $$TOTAL $$SKIP; \
	     else \
	         printf "test_cproc_full: %d/%d passed\n" $$PASS $$TOTAL; \
	     fi; \
	     exit 1; \
	 fi

print-OBJS:
	@echo $(OBJS)
