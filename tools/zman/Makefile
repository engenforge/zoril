# tools/zman/Makefile — build zman, the standard library man page generator.
#
# zman is built by the self-hosted compiler in build/zoril, not by the stage0-C seed: it is a
# development tool outside src/'s import closure, so it may use the whole language (Result-based
# I/O, String, Vec, fsys). `make -C tools/zman test` regenerates every page and diffs it against
# doc/man, the same check `make test-man` runs.

TOOL_DIR := $(patsubst %/,%,$(dir $(abspath $(firstword $(MAKEFILE_LIST)))))
REPO := $(abspath $(TOOL_DIR)/../..)

-include $(REPO)/config.mk

ZORIL = $(REPO)/build/zoril
ZILC = $(REPO)/build/zilc
STDLIB_DIR = $(REPO)/stdlib
SRC_DIR = $(REPO)/src
BUILD_DIR = $(TOOL_DIR)/build
SRCS = $(wildcard $(TOOL_DIR)/src/*.zrl)

.PHONY: all build test clean man-gen

all: build

$(BUILD_DIR)/zman: $(SRCS) $(ZORIL) $(ZILC) $(REPO)/build/runtime.o
	@mkdir -p $(BUILD_DIR)
	$(REPO)/scripts/build_zrl.sh $(BUILD_DIR)/zman $(TOOL_DIR)/src/main.zrl \
		-I stdlib=$(STDLIB_DIR) -I $(SRC_DIR) -I $(TOOL_DIR)/src --compiler $(ZORIL)

build: $(BUILD_DIR)/zman

test: build
	@ZMAN_BIN="$(BUILD_DIR)/zman" $(REPO)/scripts/test_man_pages.sh

man-gen: build
	@$(MAKE) --no-print-directory -C $(REPO) man-gen ZMAN="$(BUILD_DIR)/zman"

clean:
	rm -rf $(BUILD_DIR)
