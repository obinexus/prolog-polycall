CC ?= gcc
AR ?= ar
SWIPL ?= swipl
SWIPL_LD ?= swipl-ld

CPPFLAGS ?=
CPPFLAGS += -Iinclude -Igenerated
CFLAGS ?= -O2
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic
FOREIGN_CFLAGS := $(filter-out -Wpedantic,$(CFLAGS))
POLYCALL_LDFLAGS ?=

BUILD_DIR := build
LIB_DIR := lib
ADAPTER_OBJ := $(BUILD_DIR)/prolog_polycall.o
STATIC_LIB := $(LIB_DIR)/libprolog_polycall.a
NATIVE_TEST_BIN := $(BUILD_DIR)/prolog_polycall_adapter_test

ifeq ($(OS),Windows_NT)
EXE_EXT := .exe
FOREIGN_EXT := .dll
SWI_HOME ?= C:/PROGRA~1/swipl
SWI_INCLUDE ?= $(SWI_HOME)/include
SWI_LIB_DIR ?= $(SWI_HOME)/bin
SWIPL_PATH := $(shell where $(SWIPL) 2>nul)
PROLOG_TOOLS_AVAILABLE := $(strip $(SWIPL_PATH))
else
EXE_EXT :=
FOREIGN_EXT := .so
SWIPL_PATH := $(shell command -v $(SWIPL) 2>/dev/null)
SWIPL_LD_PATH := $(shell command -v $(SWIPL_LD) 2>/dev/null)
PROLOG_TOOLS_AVAILABLE := $(and $(strip $(SWIPL_PATH)),$(strip $(SWIPL_LD_PATH)))
endif

NATIVE_TEST_BIN := $(NATIVE_TEST_BIN)$(EXE_EXT)

.DEFAULT_GOAL := all

.PHONY: all
all: $(STATIC_LIB)

$(BUILD_DIR) $(LIB_DIR):
ifeq ($(OS),Windows_NT)
	@if not exist "$@" mkdir "$@"
else
	@mkdir -p $@
endif

$(ADAPTER_OBJ): src/prolog_polycall.c include/prolog_polycall.h generated/polycall/polycall_ffi.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

$(STATIC_LIB): $(ADAPTER_OBJ) | $(LIB_DIR)
	$(AR) rcs $@ $^

$(NATIVE_TEST_BIN): src/prolog_polycall.c tests/polycall_ffi_mock.c tests/prolog_polycall_adapter_test.c | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) -Itests $(CFLAGS) $^ -o $@

.PHONY: test
test: $(NATIVE_TEST_BIN)
	$(NATIVE_TEST_BIN)

.PHONY: foreign
foreign: | $(LIB_DIR)
ifeq ($(OS),Windows_NT)
	@if "$(strip $(POLYCALL_LDFLAGS))"=="" (echo Set POLYCALL_LDFLAGS to the libpolycall linker flags & exit /b 2)
else
	@test -n "$(POLYCALL_LDFLAGS)" || (echo "Set POLYCALL_LDFLAGS to the libpolycall linker flags" && exit 2)
endif
ifeq ($(OS),Windows_NT)
	$(CC) $(CPPFLAGS) -I"$(SWI_INCLUDE)" $(FOREIGN_CFLAGS) -shared \
		src/prolog_polycall_foreign.c src/prolog_polycall.c \
		-L"$(SWI_LIB_DIR)" -lswipl $(POLYCALL_LDFLAGS) \
		-o $(LIB_DIR)/prolog_polycall$(FOREIGN_EXT)
else
	$(SWIPL_LD) -shared -o $(LIB_DIR)/prolog_polycall $(CPPFLAGS) \
		src/prolog_polycall_foreign.c src/prolog_polycall.c $(POLYCALL_LDFLAGS)
endif

.PHONY: test-prolog
test-prolog: | $(BUILD_DIR)
ifeq ($(OS),Windows_NT)
	$(CC) $(CPPFLAGS) -Itests -I"$(SWI_INCLUDE)" $(FOREIGN_CFLAGS) -shared \
		src/prolog_polycall_foreign.c src/prolog_polycall.c \
		tests/polycall_ffi_mock.c -L"$(SWI_LIB_DIR)" -lswipl \
		-o $(BUILD_DIR)/prolog_polycall$(FOREIGN_EXT)
else
	$(SWIPL_LD) -shared -o $(BUILD_DIR)/prolog_polycall $(CPPFLAGS) -Itests \
		src/prolog_polycall_foreign.c src/prolog_polycall.c \
		tests/polycall_ffi_mock.c
endif
	$(SWIPL) -q -p foreign=$(BUILD_DIR) -s tests/prolog_polycall_tests.pl \
		-g run_tests -t halt

.PHONY: test-prolog-if-available
ifneq ($(PROLOG_TOOLS_AVAILABLE),)
test-prolog-if-available: test-prolog
else
test-prolog-if-available:
	@echo SWI-Prolog toolchain not found; skipping Prolog foreign-interface test
endif

.PHONY: verify-dry
verify-dry:
ifeq ($(OS),Windows_NT)
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-dry.ps1
else
	sh scripts/verify-dry.sh
endif

.PHONY: clean
clean:
ifeq ($(OS),Windows_NT)
	@if exist "$(BUILD_DIR)" rmdir /s /q "$(BUILD_DIR)"
	@if exist "$(LIB_DIR)" rmdir /s /q "$(LIB_DIR)"
else
	rm -rf $(BUILD_DIR) $(LIB_DIR)
endif

-include $(ADAPTER_OBJ:.o=.d)
