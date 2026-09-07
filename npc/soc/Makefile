TOPNAME       := SimTop
BUILD_DIR     := $(abspath build)
OBJ_DIR       := $(BUILD_DIR)/obj_dir
BIN           := $(OBJ_DIR)/V$(TOPNAME)
WORKBENCH_HOME := $(abspath ../..)
YSYXSOC_HOME  ?= $(WORKBENCH_HOME)/ysyxSoC
AM_HOME       ?= $(WORKBENCH_HOME)/abstract-machine
RUNTIME_TEST  := $(WORKBENCH_HOME)/npc/tests/soc-runtime-smoke
GPIO_TEST     := $(WORKBENCH_HOME)/npc/tests/soc-gpio-smoke
VERILATOR     ?= verilator
export CCACHE_DISABLE ?= 1

SOC_RTL       := $(YSYXSOC_HOME)/ready-to-run/minirv/ElaborateTop.v
PERIP_VSRCS_ALL := $(shell find $(YSYXSOC_HOME)/perip -type f \
                      \( -name '*.v' -o -name '*.sv' \) | sort)
# 官方 GPIO 文件是留给学生实现的空骨架，仿真时用当前仓库的同名 overlay 替换。
PERIP_VSRCS   := $(filter-out $(YSYXSOC_HOME)/perip/gpio/mygpio_top_apb.v,$(PERIP_VSRCS_ALL))
CPU_VSRCS     := $(abspath ../vsrc/minirv_regfile.sv) \
                 $(abspath ../vsrc/minirv_decode.sv) \
                 $(abspath ../vsrc/minirv_core.sv) \
                 $(abspath ../vsrc/soc/minirv_simple_bus_master.sv) \
                 $(abspath ../vsrc/soc/ysyx_25100265.sv) \
                 $(abspath ../vsrc/soc/NPC.sv)
MONITOR_VSRCS := $(shell find $(abspath vsrc) -name '*.sv' | sort)
CSRCS         := $(shell find $(abspath csrc) -name '*.cpp' | sort)
INCLUDE_DIRS  := $(sort $(dir $(PERIP_VSRCS)))
INCLUDE_FLAGS := $(addprefix -I,$(INCLUDE_DIRS))
VSRCS         := $(SOC_RTL) $(PERIP_VSRCS) $(CPU_VSRCS) $(MONITOR_VSRCS)

IMG           ?= $(YSYXSOC_HOME)/ready-to-run/minirv/hello-minirv-ysyxsoc.bin
MAX_CYCLES    ?= 100000000
WAVE          ?=
GPIO          ?= 0
RUN_ARGS      := --image $(abspath $(IMG)) --max-cycles $(MAX_CYCLES) --gpio $(GPIO)
ifneq ($(strip $(WAVE)),)
RUN_ARGS      += --wave $(abspath $(WAVE))
endif

$(BIN): $(VSRCS) $(CSRCS) Makefile
	@mkdir -p $(BUILD_DIR)
	$(VERILATOR) --cc --exe --build --no-timing --trace --top-module $(TOPNAME) \
		--Mdir $(OBJ_DIR) -DPDK_BEHAV -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		-Wno-DECLFILENAME -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-STMTDLY \
		$(INCLUDE_FLAGS) $(VSRCS) $(CSRCS) \
		-CFLAGS "-std=c++17 -O2 -Wall -Wextra -I$(abspath csrc/include)" \
		-LDFLAGS "-ldl"

all: $(BIN)

run: $(BIN)
	$(BIN) $(RUN_ARGS)

test-runtime: $(BIN)
	$(MAKE) -C $(RUNTIME_TEST) ARCH=minirv-ysyxsoc soc-image
	@output=`$(BIN) --image $(RUNTIME_TEST)/build/soc-runtime-smoke-minirv-ysyxsoc.soc.bin \
		--max-cycles 500000000 --gpio 0`; status=$$?; \
		printf '%s\n' "$$output"; test $$status -eq 0; \
		printf '%s\n' "$$output" | grep -q 'SoC CSR/timer smoke passed'; \
		printf '%s\n' "$$output" | grep -q 'SoC GOOD TRAP'

test-gpio: $(BIN)
	$(MAKE) -C $(GPIO_TEST) ARCH=minirv-ysyxsoc soc-image
	@accepted=`$(BIN) --image $(GPIO_TEST)/build/soc-gpio-smoke-minirv-ysyxsoc.soc.bin \
		--max-cycles 500000000 --gpio 0x0265`; status=$$?; \
		printf '%s\n' "$$accepted"; test $$status -eq 0; \
		printf '%s\n' "$$accepted" | grep -q 'gpio_out=0x600d'; \
		printf '%s\n' "$$accepted" | grep -q 'gpio_digits=0x25100265'; \
		rejected=`$(BIN) --image $(GPIO_TEST)/build/soc-gpio-smoke-minirv-ysyxsoc.soc.bin \
		--max-cycles 500000000 --gpio 0`; status=$$?; \
		printf '%s\n' "$$rejected"; test $$status -eq 0; \
		printf '%s\n' "$$rejected" | grep -q 'gpio_out=0xdead'; \
		printf '%s\n' "$$rejected" | grep -q 'gpio_digits=0x25100265'

test-hello: $(BIN)
	@output=`$(BIN) --image $(YSYXSOC_HOME)/ready-to-run/minirv/hello-minirv-ysyxsoc.bin \
		--max-cycles 500000000 --gpio 0`; status=$$?; \
		printf '%s\n' "$$output"; test $$status -eq 0; \
		printf '%s\n' "$$output" | grep -q 'Hello, AbstractMachine!'; \
		printf '%s\n' "$$output" | grep -q 'SoC GOOD TRAP'

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run test-runtime test-gpio test-hello clean
