TOPNAME       := SimTop
BUILD_DIR     := $(abspath build)
OBJ_DIR       := $(BUILD_DIR)/obj_dir
BIN           := $(OBJ_DIR)/V$(TOPNAME)
YSYXSOC_HOME  ?= $(abspath ../../ysyxSoC)
VERILATOR     ?= verilator
export CCACHE_DISABLE ?= 1

SOC_RTL       := $(YSYXSOC_HOME)/ready-to-run/minirv/ElaborateTop.v
PERIP_VSRCS   := $(shell find $(YSYXSOC_HOME)/perip -type f \
                  \( -name '*.v' -o -name '*.sv' \) | sort)
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

test-hello: $(BIN)
	@output=`$(BIN) --image $(YSYXSOC_HOME)/ready-to-run/minirv/hello-minirv-ysyxsoc.bin \
		--max-cycles 500000000 --gpio 0`; status=$$?; \
		printf '%s\n' "$$output"; test $$status -eq 0; \
		printf '%s\n' "$$output" | grep -q 'Hello, AbstractMachine!'; \
		printf '%s\n' "$$output" | grep -q 'SoC GOOD TRAP'

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run test-hello clean
