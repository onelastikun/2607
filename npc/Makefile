TOPNAME       := top
BUILD_DIR     := $(abspath build)
OBJ_DIR       := $(BUILD_DIR)/obj_dir
BIN           := $(OBJ_DIR)/V$(TOPNAME)
VERILATOR     ?= verilator
export CCACHE_DISABLE ?= 1
CYCLES        ?= 10
WAVE          ?=

VSRCS         := $(shell find $(abspath vsrc) -type f \( -name '*.v' -o -name '*.sv' \) | sort)
CSRCS         := $(shell find $(abspath csrc) -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' \) | sort)

VERILATOR_FLAGS := --cc --exe --build --trace \
                   --top-module $(TOPNAME) \
                   --Mdir $(OBJ_DIR) \
                   -Wall -Wno-DECLFILENAME \
                   -CFLAGS "-std=c++17 -O2 -Wall -Wextra"

RUN_ARGS      := --cycles $(CYCLES)
ifneq ($(strip $(WAVE)),)
RUN_ARGS      += --wave $(abspath $(WAVE))
endif

all: $(BIN)

$(BIN): $(VSRCS) $(CSRCS) Makefile
	@mkdir -p $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) $(VSRCS) $(CSRCS)

run: $(BIN)
	$(BIN) $(RUN_ARGS)

sim:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@$(MAKE) run CYCLES=$(CYCLES) WAVE=$(WAVE)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run sim clean

include ../Makefile
