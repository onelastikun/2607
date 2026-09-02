TOPNAME       := top
BUILD_DIR     := $(abspath build)
OBJ_DIR       := $(BUILD_DIR)/obj_dir
BIN           := $(OBJ_DIR)/V$(TOPNAME)
DIRECTED_ELF  := $(BUILD_DIR)/rv32e-directed.elf
DIRECTED_BIN  := $(BUILD_DIR)/rv32e-directed.bin
VERILATOR     ?= verilator
RISCV_CC       ?= riscv64-linux-gnu-gcc
RISCV_OBJCOPY  ?= riscv64-linux-gnu-objcopy
export CCACHE_DISABLE ?= 1
MAX_CYCLES    ?= 100
IMG           ?=
WAVE          ?=
ITRACE        ?= 0
DIFF          ?=
NEMU_REF      ?= $(abspath ../nemu/build/riscv32-nemu-interpreter-so)

VSRCS         := $(shell find $(abspath vsrc) -type f \( -name '*.v' -o -name '*.sv' \) | sort)
CSRCS         := $(shell find $(abspath csrc) -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' \) | sort)

VERILATOR_FLAGS := --cc --exe --build --trace \
                   --top-module $(TOPNAME) \
                   --Mdir $(OBJ_DIR) \
                   -Wall -Wno-DECLFILENAME \
                   -CFLAGS "-std=c++17 -O2 -Wall -Wextra -I$(abspath csrc/include)" \
                   -LDFLAGS "-ldl"

RUN_ARGS      := --max-cycles $(MAX_CYCLES)
ifneq ($(strip $(IMG)),)
RUN_ARGS      += --image $(abspath $(IMG))
endif
ifneq ($(strip $(WAVE)),)
RUN_ARGS      += --wave $(abspath $(WAVE))
endif
ifneq ($(ITRACE),0)
RUN_ARGS      += --itrace
endif
ifneq ($(strip $(DIFF)),)
RUN_ARGS      += --diff $(abspath $(DIFF))
endif

all: $(BIN)

$(BIN): $(VSRCS) $(CSRCS) Makefile
	@mkdir -p $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) $(VSRCS) $(CSRCS)

run: $(BIN)
	$(BIN) $(RUN_ARGS)

$(DIRECTED_ELF): tests/rv32e-directed.S tests/linker.ld
	@mkdir -p $(BUILD_DIR)
	$(RISCV_CC) -march=rv32e_zicsr -mabi=ilp32e -fno-pic -fno-pie \
		-nostdlib -nostartfiles -static -mno-relax -Wl,--build-id=none \
		-Wl,-T,$(abspath tests/linker.ld) -o $@ $<

$(DIRECTED_BIN): $(DIRECTED_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

test-rv32e: $(BIN) $(DIRECTED_BIN)
	$(BIN) --image $(DIRECTED_BIN) --max-cycles 1000 $(if $(filter-out 0,$(ITRACE)),--itrace)

test-diff: $(BIN) $(DIRECTED_BIN)
	@test -f $(NEMU_REF) || { echo "missing NEMU reference: $(NEMU_REF)"; exit 1; }
	$(BIN) --image $(DIRECTED_BIN) --max-cycles 1000 --diff $(NEMU_REF) 		$(if $(filter-out 0,$(ITRACE)),--itrace)

sim:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@$(MAKE) run MAX_CYCLES=$(MAX_CYCLES) IMG=$(IMG) WAVE=$(WAVE) ITRACE=$(ITRACE) DIFF=$(DIFF)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run test-rv32e test-diff sim clean

include ../Makefile
