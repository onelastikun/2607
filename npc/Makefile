TOPNAME       := top
BUILD_DIR     := $(abspath build)
OBJ_DIR       := $(BUILD_DIR)/obj_dir
DELAY_OBJ_DIR := $(BUILD_DIR)/delay_obj_dir
BIN           := $(OBJ_DIR)/V$(TOPNAME)
DELAY_BIN     := $(DELAY_OBJ_DIR)/V$(TOPNAME)
DIRECTED_ELF  := $(BUILD_DIR)/minirv-directed.elf
DIRECTED_BIN  := $(BUILD_DIR)/minirv-directed.bin
BUS_ERROR_ELF := $(BUILD_DIR)/bus-error.elf
BUS_ERROR_BIN := $(BUILD_DIR)/bus-error.bin
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

# E8 Icarus/VPI 四值仿真构建目录。VPI 插件复用 csrc 中的内存和设备模型，
# 但不放入 CSRCS，避免它被 Verilator 当作普通 C++ 仿真源编译。
IVERILOG       ?= iverilog
VVP            ?= vvp
IVERILOG_VPI   ?= iverilog-vpi
IVERILOG_DIR   := $(BUILD_DIR)/iverilog
IVERILOG_SIM   := $(IVERILOG_DIR)/npc.vvp
IVERILOG_VPI_SO := $(IVERILOG_DIR)/npc_vpi.vpi
IVERILOG_VPI_SRCS := $(abspath iverilog/vpi_memory.cpp) \
                     $(abspath csrc/memory.cpp) \
                     $(abspath csrc/device.cpp) \
                     $(abspath csrc/runtime.cpp)

VSRCS         := $(shell find $(abspath vsrc) -type f \( -name '*.v' -o -name '*.sv' \) | sort)
CSRCS         := $(shell find $(abspath csrc) -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' \) | sort)

VERILATOR_BASE_FLAGS := --cc --exe --build --trace \
                        --top-module $(TOPNAME) \
                        -Wall -Wno-DECLFILENAME \
                        -CFLAGS "-std=c++17 -O2 -Wall -Wextra -I$(abspath csrc/include)" \
                        -LDFLAGS "-ldl"
VERILATOR_FLAGS := $(VERILATOR_BASE_FLAGS) --Mdir $(OBJ_DIR)

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

$(DELAY_BIN): $(VSRCS) $(CSRCS) Makefile
	@mkdir -p $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_BASE_FLAGS) --Mdir $(DELAY_OBJ_DIR) \
		-GBUS_READ_DELAY=2 -GBUS_WRITE_DELAY=3 $(VSRCS) $(CSRCS)

run: $(BIN)
	$(BIN) $(RUN_ARGS)


$(IVERILOG_VPI_SO): $(IVERILOG_VPI_SRCS) $(shell find $(abspath csrc/include) -type f) Makefile
	@mkdir -p $(IVERILOG_DIR)
	@cd $(IVERILOG_DIR) && $(IVERILOG_VPI) --name=npc_vpi \
		-I$(abspath csrc/include) $(IVERILOG_VPI_SRCS)

$(IVERILOG_SIM): $(VSRCS) Makefile
	@mkdir -p $(IVERILOG_DIR)
	$(IVERILOG) -g2012 -D__ICARUS__ -s iverilog_top -o $@ $(VSRCS)

$(DIRECTED_ELF): tests/minirv-directed.S tests/linker.ld
	@mkdir -p $(BUILD_DIR)
	$(RISCV_CC) -march=rv32e_zicsr -mabi=ilp32e -fno-pic -fno-pie \
		-nostdlib -nostartfiles -static -mno-relax -Wl,--build-id=none \
		-Wl,-T,$(abspath tests/linker.ld) -o $@ $<

$(DIRECTED_BIN): $(DIRECTED_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(BUS_ERROR_ELF): tests/bus-error.S tests/linker.ld
	@mkdir -p $(BUILD_DIR)
	$(RISCV_CC) -march=rv32e_zicsr -mabi=ilp32e -fno-pic -fno-pie \
		-nostdlib -nostartfiles -static -mno-relax -Wl,--build-id=none \
		-Wl,-T,$(abspath tests/linker.ld) -o $@ $<

$(BUS_ERROR_BIN): $(BUS_ERROR_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

test-minirv: $(BIN) $(DIRECTED_BIN)
	$(BIN) --image $(DIRECTED_BIN) --max-cycles 1000 $(if $(filter-out 0,$(ITRACE)),--itrace)

test-diff: $(BIN) $(DIRECTED_BIN)
	@test -f $(NEMU_REF) || { echo "missing NEMU reference: $(NEMU_REF)"; exit 1; }
	$(BIN) --image $(DIRECTED_BIN) --max-cycles 1000 --diff $(NEMU_REF) 		$(if $(filter-out 0,$(ITRACE)),--itrace)


test-delayed: $(DELAY_BIN) $(DIRECTED_BIN)
	@test -f $(NEMU_REF) || { echo "missing NEMU reference: $(NEMU_REF)"; exit 1; }
	$(DELAY_BIN) --image $(DIRECTED_BIN) --max-cycles 2000 --diff $(NEMU_REF)

test-itrace: $(BIN) $(DIRECTED_BIN)
	@output=`$(BIN) --image $(DIRECTED_BIN) --max-cycles 1000 --itrace`; \
		status=$$?; printf '%s\n' "$$output"; test $$status -eq 0 && \
		printf '%s\n' "$$output" | grep -q \
		  '0x80000000: 0x800000b7  lui x1, 0x80000' && \
		printf '%s\n' "$$output" | grep -q 'jalr x6' && \
		printf '%s\n' "$$output" | grep -q 'ebreak'

test-bus-error: $(BIN) $(BUS_ERROR_BIN)
	@set +e; output=`$(BIN) --image $(BUS_ERROR_BIN) --max-cycles 100 2>&1`; \
		status=$$?; set -e; printf '%s\n' "$$output"; \
		test $$status -ne 0; \
		printf '%s\n' "$$output" | grep -q \
		  'SimpleBus access error before pc=0x80000004 cause=0x1'

# E8 四值 RTL 仿真：Icarus 通过 VPI 加载裸镜像并替代 Verilator 的 DPI-C。
test-iverilog: $(IVERILOG_SIM) $(IVERILOG_VPI_SO) $(DIRECTED_BIN)
	@cd $(abspath .) && $(VVP) -M$(abspath $(IVERILOG_DIR)) -mnpc_vpi \
		$(abspath $(IVERILOG_SIM)) +img=$(abspath $(DIRECTED_BIN))

sim:
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@$(MAKE) run MAX_CYCLES=$(MAX_CYCLES) IMG=$(IMG) WAVE=$(WAVE) ITRACE=$(ITRACE) DIFF=$(DIFF)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run test-minirv test-diff test-delayed test-itrace test-bus-error test-iverilog sim clean

include ../Makefile
