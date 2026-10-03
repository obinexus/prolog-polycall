# prolog-polycall -- SWI-Prolog foreign library over the Polycall binding ABI v1.
#
#   make          build lib/prolog_polycall$(SOEXT) (load with swipl -p foreign=lib)
#   make test     run the PlUnit suite against the real core (tests/run-real-core.sh)
#   make clean
#
# The core is found through pkg-config (polycall.pc; set PKG_CONFIG_PATH for
# a non-system prefix), SWI-Prolog through `swipl --dump-runtime-variables`.
# Override POLYCALL_CFLAGS / POLYCALL_LIBS / SWI_CFLAGS if needed.

VERSION := 1.1.0
comma := ,
CC ?= cc
PKG_CONFIG ?= pkg-config
SWIPL ?= swipl

PLBASE := $(shell $(SWIPL) --dump-runtime-variables 2>/dev/null | sed -n 's/^PLBASE="\(.*\)";$$/\1/p')
SOEXT := $(or $(shell $(SWIPL) --dump-runtime-variables 2>/dev/null | sed -n 's/^PLSOEXT="\(.*\)";$$/\1/p'),so)
SWI_CFLAGS ?= -I"$(PLBASE)/include"

POLYCALL_CFLAGS ?= $(shell $(PKG_CONFIG) --cflags polycall)
POLYCALL_LIBS ?= $(shell $(PKG_CONFIG) --libs polycall)
POLYCALL_LIBDIR ?= $(shell $(PKG_CONFIG) --variable=libdir polycall)

CFLAGS ?= -O2 -g
WARN := -std=c11 -Wall -Wextra

UNAME_S := $(shell uname -s 2>/dev/null)
ifeq ($(OS),Windows_NT)
PIC :=
SHARED := -shared
# Windows foreign libraries must link libswipl explicitly
LINK_EXTRA := -L"$(PLBASE)/bin" -lswipl
else ifeq ($(UNAME_S),Darwin)
PIC := -fPIC
SHARED := -bundle -undefined dynamic_lookup
LINK_EXTRA := $(if $(POLYCALL_LIBDIR),-Wl$(comma)-rpath$(comma)$(POLYCALL_LIBDIR))
else
PIC := -fPIC
SHARED := -shared
# bind every core symbol at load time: an old core without the ABI v1
# symbols makes use_foreign_library/1 fail with "undefined symbol"
LINK_EXTRA := -Wl,-z,now $(if $(POLYCALL_LIBDIR),-Wl$(comma)-rpath$(comma)$(POLYCALL_LIBDIR))
endif

FOREIGN := lib/prolog_polycall.$(SOEXT)

.PHONY: all
all: $(FOREIGN)

.PHONY: check-deps
check-deps:
	@test -n "$(PLBASE)" || { echo "swipl not found (install SWI-Prolog >= 9)"; exit 2; }
	@$(PKG_CONFIG) --exists polycall || { echo "polycall.pc not found (install the Polycall core >= 1.1.0 or set PKG_CONFIG_PATH)"; exit 2; }

$(FOREIGN): src/prolog_polycall.c | check-deps
	@mkdir -p $(dir $@)
	$(CC) $(WARN) $(CFLAGS) $(PIC) $(SWI_CFLAGS) $(POLYCALL_CFLAGS) $(SHARED) \
		src/prolog_polycall.c -o $@ $(POLYCALL_LIBS) $(LINK_EXTRA) $(LDFLAGS)

.PHONY: test
test:
	sh tests/run-real-core.sh

.PHONY: clean
clean:
	rm -rf build lib
