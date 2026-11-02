ZORIL = ../../build/zoril
ZILC = ../../build/zilc
STDLIB_DIR = ../../stdlib
SRC_DIR = ../../src
-include ../../config.mk
RUNTIME_O = ../../build/runtime.o
QBE ?= $(BACKEND_BIN)
ASSEMBLER_BIN ?= as
LINKER_BIN ?= ld
BUILD_DIR = build

.PHONY: all build test clean

all: build

$(BUILD_DIR)/zilc.zil: src/main.zrl
	@mkdir -p $(BUILD_DIR)
	$(ZORIL) -I $(STDLIB_DIR) -I $(SRC_DIR) --emit-zil src/main.zrl -o $(BUILD_DIR)/zilc.zil

$(BUILD_DIR)/zilc.ssa: $(BUILD_DIR)/zilc.zil
	$(ZILC) $(BUILD_DIR)/zilc.zil $(BUILD_DIR)/zilc.ssa

$(BUILD_DIR)/zilc.s: $(BUILD_DIR)/zilc.ssa
	$(QBE) -o $(BUILD_DIR)/zilc.s $(BUILD_DIR)/zilc.ssa

$(BUILD_DIR)/zilc.o: $(BUILD_DIR)/zilc.s
	$(ASSEMBLER_BIN) -o $(BUILD_DIR)/zilc.o $(BUILD_DIR)/zilc.s

$(BUILD_DIR)/zilc: $(BUILD_DIR)/zilc.o $(RUNTIME_O)
	$(LINKER_BIN) -o $(BUILD_DIR)/zilc $(RUNTIME_O) $(BUILD_DIR)/zilc.o

build: $(BUILD_DIR)/zilc

test: build
	@echo "Running zilc tests..."
	@passed=0; failed=0; \
	for zil in test/*.zil; do \
		name=$$(basename $$zil .zil); \
		expected=test/$$name.ssa; \
		if [ ! -f "$$expected" ]; then continue; fi; \
		actual=$$($(BUILD_DIR)/zilc $$zil 2>/dev/null); \
		if [ "$$actual" = "$$(cat $$expected)" ]; then \
			echo "[PASS] $$name"; passed=$$((passed+1)); \
		else \
			echo "[FAIL] $$name"; failed=$$((failed+1)); \
		fi; \
	done; \
	total=$$((passed+failed)); \
	echo "$$passed/$$total tests passed."

clean:
	rm -rf $(BUILD_DIR)
