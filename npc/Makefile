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

# E8 门级网表仿真输入：先在 ecc/npc 中运行 ECC，生成两种 Synthesis 网表。
NETLIST_DIR           := $(BUILD_DIR)/netlist
NETLIST_ECC_PROJECT   ?= $(abspath ../ecc/npc)
NETLIST_SIM_GZ        ?= $(NETLIST_ECC_PROJECT)/runs/default/Synthesis_yosys/output/npc_Synthesis_sim.v.gz
NETLIST_SIM_V         := $(NETLIST_DIR)/npc_Synthesis_sim.v
NETLIST_PDK_ROOT      ?= /home/onelastikun/to_test/ecc/icsprout55-pdk
NETLIST_CELL_ROOT     := $(NETLIST_PDK_ROOT)/IP/STD_cell/ics55_LLSC_H7C_V1p10C100
NETLIST_CELL_SRCS     := $(NETLIST_CELL_ROOT)/ics55_LLSC_H7CR/verilog/ics55_LLSC_H7CR.v \
                         $(NETLIST_CELL_ROOT)/ics55_LLSC_H7CL/verilog/ics55_LLSC_H7CL.v
NETLIST_OBJ_DIR       := $(NETLIST_DIR)/verilator_obj
NETLIST_BIN           := $(NETLIST_OBJ_DIR)/Vnetlist_top
NETLIST_IVL_DIR       := $(NETLIST_DIR)/iverilog
NETLIST_IVL_SIM       := $(NETLIST_IVL_DIR)/netlist.vvp
NETLIST_ELF           := $(NETLIST_DIR)/e8-netlist-smoke.elf
NETLIST_IMAGE         := $(NETLIST_DIR)/e8-netlist-smoke.bin

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


$(NETLIST_SIM_V): $(NETLIST_SIM_GZ)
	@test -f $< || { echo "missing ECC netlist: $< (run ECC first)"; exit 1; }
	@mkdir -p $(NETLIST_DIR)
	gzip -cd $< > $@

$(NETLIST_ELF): tests/e8-netlist-smoke.S tests/linker.ld
	@mkdir -p $(NETLIST_DIR)
	$(RISCV_CC) -march=rv32e_zicsr -mabi=ilp32e -fno-pic -fno-pie \
		-nostdlib -nostartfiles -static -mno-relax -Wl,--build-id=none \
		-Wl,-T,$(abspath tests/linker.ld) -o $@ $<

$(NETLIST_IMAGE): $(NETLIST_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(NETLIST_BIN): $(NETLIST_SIM_V) $(NETLIST_CELL_SRCS) \
			 netlist/vsrc/netlist_top.sv netlist/vsrc/netlist_bus_pmem.sv \
			 netlist/csrc/main.cpp csrc/memory.cpp csrc/device.cpp csrc/runtime.cpp Makefile
	@test -f $(NETLIST_SIM_GZ) || { echo "missing ECC netlist: $(NETLIST_SIM_GZ) (run ECC first)"; exit 1; }
	@mkdir -p $(NETLIST_OBJ_DIR)
	$(VERILATOR) --cc --exe --build --no-timing --trace \
		--top-module netlist_top --Mdir $(NETLIST_OBJ_DIR) \
		-D__VERILATOR__ -Dfunctional --timescale 1ns/1ns -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-PINMISSING -Wno-UNUSEDSIGNAL \
		-Wno-TIMESCALEMOD -Wno-IMPLICIT -Wno-BLKSEQ \
		-CFLAGS "-std=c++17 -O2 -Wall -Wextra -I$(abspath csrc/include)" \
		-LDFLAGS "-ldl" $(NETLIST_SIM_V) \
		netlist/vsrc/netlist_top.sv netlist/vsrc/netlist_bus_pmem.sv \
		netlist/csrc/main.cpp csrc/memory.cpp csrc/device.cpp csrc/runtime.cpp \
		$(NETLIST_CELL_SRCS)

$(NETLIST_IVL_SIM): $(NETLIST_SIM_V) $(NETLIST_CELL_SRCS) \
			 netlist/vsrc/iverilog_netlist_top.sv netlist/vsrc/netlist_top.sv \
			 netlist/vsrc/netlist_bus_pmem.sv
	@mkdir -p $(NETLIST_IVL_DIR)
	$(IVERILOG) -g2012 -D__ICARUS__ -Dfunctional -s iverilog_netlist_top \
		-o $@ netlist/vsrc/iverilog_netlist_top.sv \
		netlist/vsrc/netlist_top.sv netlist/vsrc/netlist_bus_pmem.sv \
		$(NETLIST_SIM_V) $(NETLIST_CELL_SRCS)

# 使用 ECC 生成的 *_Synthesis_sim.v.gz 做 Verilator 门级功能仿真。
test-netlist-verilator: $(NETLIST_BIN) $(NETLIST_IMAGE)
	$(NETLIST_BIN) $(NETLIST_IMAGE)

# 使用同一份门级网表做 Icarus 四值仿真，检查 X 信号传播。
test-netlist-iverilog: $(NETLIST_IVL_SIM) $(NETLIST_IMAGE) $(IVERILOG_VPI_SO)
	@$(VVP) -M$(abspath $(IVERILOG_DIR)) -mnpc_vpi \
		$(abspath $(NETLIST_IVL_SIM)) +img=$(abspath $(NETLIST_IMAGE))

test-netlist: test-netlist-verilator test-netlist-iverilog

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

.PHONY: all run test-minirv test-diff test-delayed test-itrace test-bus-error test-iverilog test-netlist-verilator test-netlist-iverilog test-netlist sim clean

include ../Makefile
