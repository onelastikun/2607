TOPNAME        := SimTop
WORKBENCH_HOME := $(abspath ../../..)
YSYXSOC_HOME   ?= $(WORKBENCH_HOME)/ysyxSoC
NVBOARD_HOME   ?= $(WORKBENCH_HOME)/nvboard
GPIO_TEST      := $(WORKBENCH_HOME)/npc/tests/soc-gpio-smoke
BUILD_DIR      := $(abspath build)
OBJ_DIR        := $(BUILD_DIR)/obj_dir
BIN            := $(BUILD_DIR)/soc-nvboard
AUTO_BIND      := $(BUILD_DIR)/auto_bind.cpp
NXDC           := constr/SimTop.nxdc
VERILATOR      ?= verilator
export CCACHE_DISABLE ?= 1

SOC_RTL := $(YSYXSOC_HOME)/ready-to-run/minirv/ElaborateTop.v
PERIP_VSRCS_ALL := $(shell find $(YSYXSOC_HOME)/perip -type f \
                     \( -name '*.v' -o -name '*.sv' \) | sort)
PERIP_VSRCS := $(filter-out $(YSYXSOC_HOME)/perip/gpio/mygpio_top_apb.v,$(PERIP_VSRCS_ALL))
CPU_VSRCS := $(WORKBENCH_HOME)/npc/vsrc/minirv_regfile.sv \
             $(WORKBENCH_HOME)/npc/vsrc/minirv_decode.sv \
             $(WORKBENCH_HOME)/npc/vsrc/minirv_core.sv \
             $(WORKBENCH_HOME)/npc/vsrc/soc/minirv_simple_bus_master.sv \
             $(WORKBENCH_HOME)/npc/vsrc/soc/ysyx_25100265.sv \
             $(WORKBENCH_HOME)/npc/vsrc/soc/NPC.sv
LOCAL_VSRCS := $(WORKBENCH_HOME)/npc/soc/vsrc/mygpio_top_apb.sv \
               $(WORKBENCH_HOME)/npc/soc/vsrc/uart_apb_monitor.sv
VSRCS := $(SOC_RTL) $(PERIP_VSRCS) $(CPU_VSRCS) $(LOCAL_VSRCS)
CSRCS := csrc/main.cpp \
         $(WORKBENCH_HOME)/npc/soc/csrc/flash_image.cpp \
         $(WORKBENCH_HOME)/npc/soc/csrc/runtime.cpp \
         $(AUTO_BIND)
INCLUDE_DIRS := $(sort $(dir $(PERIP_VSRCS)))
INCLUDE_FLAGS := $(addprefix -I,$(INCLUDE_DIRS))

include $(NVBOARD_HOME)/scripts/nvboard.mk

$(AUTO_BIND): $(NXDC)
	@mkdir -p $(BUILD_DIR)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $< $@

$(BIN): $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE) Makefile
	$(VERILATOR) --cc --exe --build --no-timing --top-module $(TOPNAME) \
		--Mdir $(OBJ_DIR) -DPDK_BEHAV -Wall -Wno-fatal -Wno-TIMESCALEMOD \
		-Wno-DECLFILENAME -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-STMTDLY \
		$(INCLUDE_FLAGS) $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE) \
		-CFLAGS "-std=c++17 -O2 -Wall -Wextra $(shell sdl2-config --cflags) \
		-I$(NVBOARD_HOME)/usr/include -I$(WORKBENCH_HOME)/npc/soc/csrc/include" \
		-LDFLAGS "$(shell sdl2-config --libs) -lSDL2_image -lSDL2_ttf" \
		-o $(BIN)

all: $(BIN)

IMG ?= $(YSYXSOC_HOME)/ready-to-run/minirv/hello-minirv-ysyxsoc.bin
run: $(BIN)
	$(BIN) --image $(abspath $(IMG))

test-gpio: $(BIN)
	$(MAKE) -C $(GPIO_TEST) ARCH=minirv-ysyxsoc soc-image
	@output=`SDL_VIDEODRIVER=dummy $(BIN) \
		--image $(GPIO_TEST)/build/soc-gpio-smoke-minirv-ysyxsoc.soc.bin \
		--cycles 500000000`; status=$$?; \
		printf '%s\n' "$$output"; test $$status -eq 0; \
		printf '%s\n' "$$output" | grep -q 'NVBoard SoC halted, code=0'

# dummy 视频驱动只验证 NVBoard/SoC/引脚绑定能启动，不运行完整的 Flash boot。
smoke: $(BIN)
	SDL_VIDEODRIVER=dummy $(BIN) --image $(abspath $(IMG)) --cycles 100

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run smoke test-gpio clean
