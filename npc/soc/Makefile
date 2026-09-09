TOPNAME        := SimTop
BUILD_DIR      := $(abspath build)
OBJ_DIR        := $(BUILD_DIR)/obj_dir
BIN            := $(OBJ_DIR)/V$(TOPNAME)
WORKBENCH_HOME := $(abspath ../..)
YSYXSOC_HOME   ?= $(WORKBENCH_HOME)/ysyxSoC
NVBOARD_HOME   ?= $(WORKBENCH_HOME)/nvboard
AM_HOME        ?= $(WORKBENCH_HOME)/abstract-machine
RUNTIME_TEST   := $(WORKBENCH_HOME)/npc/tests/soc-runtime-smoke
GPIO_TEST      := $(WORKBENCH_HOME)/npc/tests/soc-gpio-smoke
AUTO_BIND      := $(BUILD_DIR)/auto_bind.cpp
NXDC           := constr/SimTop.nxdc
VERILATOR      ?= verilator
export CCACHE_DISABLE ?= 1

SOC_RTL := $(YSYXSOC_HOME)/ready-to-run/minirv/ElaborateTop.v
PERIP_VSRCS_ALL := $(shell find $(YSYXSOC_HOME)/perip -type f \
                      \( -name '*.v' -o -name '*.sv' \) | sort)
# 官方 GPIO 文件是留给学生实现的空骨架，使用当前仓库的同名实现替换。
PERIP_VSRCS := $(filter-out $(YSYXSOC_HOME)/perip/gpio/mygpio_top_apb.v,$(PERIP_VSRCS_ALL))
CPU_VSRCS := $(abspath ../vsrc/minirv_regfile.sv) \
             $(abspath ../vsrc/minirv_decode.sv) \
             $(abspath ../vsrc/minirv_core.sv) \
             $(abspath ../vsrc/soc/minirv_simple_bus_master.sv) \
             $(abspath ../vsrc/soc/ysyx_25100265.sv) \
             $(abspath ../vsrc/soc/NPC.sv)
LOCAL_VSRCS := $(shell find $(abspath vsrc) -name '*.sv' | sort)
CSRCS := $(shell find $(abspath csrc) -name '*.cpp' | sort) $(AUTO_BIND)
INCLUDE_DIRS := $(sort $(dir $(PERIP_VSRCS)))
INCLUDE_FLAGS := $(addprefix -I,$(INCLUDE_DIRS))
VSRCS := $(SOC_RTL) $(PERIP_VSRCS) $(CPU_VSRCS) $(LOCAL_VSRCS)

include $(NVBOARD_HOME)/scripts/nvboard.mk

IMG        ?= $(YSYXSOC_HOME)/ready-to-run/minirv/hello-minirv-ysyxsoc.bin
MAX_CYCLES ?= 0
WAVE       ?=
GPIO       ?= 0
HEADLESS   ?= 0
RUN_ARGS   := --image $(abspath $(IMG)) --max-cycles $(MAX_CYCLES) --gpio $(GPIO)
ifneq ($(strip $(WAVE)),)
RUN_ARGS += --wave $(abspath $(WAVE))
endif
ifneq ($(HEADLESS),0)
RUN_ARGS += --headless
endif

$(AUTO_BIND): $(NXDC)
	@mkdir -p $(BUILD_DIR)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $< $@

$(BIN): $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE) Makefile
	@mkdir -p $(BUILD_DIR)
	$(VERILATOR) --cc --exe --build --no-timing --trace --top-module $(TOPNAME) \
		--Mdir $(OBJ_DIR) -DPDK_BEHAV -Wall -Wno-fatal -D__UART_TO_CONSOLE__ -Wno-TIMESCALEMOD \
		-Wno-DECLFILENAME -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-STMTDLY \
		$(INCLUDE_FLAGS) $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE) \
		-CFLAGS "-std=c++17 -O2 -Wall -Wextra $(shell sdl2-config --cflags) \
		-I$(NVBOARD_HOME)/usr/include -I$(abspath csrc/include)" \
		-LDFLAGS "$(shell sdl2-config --libs) -lSDL2_image -lSDL2_ttf -ldl"

all: $(BIN)

# 默认运行直接打开 NVBoard；自动回归使用 HEADLESS=1。
run: $(BIN)
	$(BIN) $(RUN_ARGS)

test-runtime: $(BIN)
	$(MAKE) -C $(RUNTIME_TEST) ARCH=minirv-ysyxsoc soc-image
	@output=`$(BIN) --headless \
		--image $(RUNTIME_TEST)/build/soc-runtime-smoke-minirv-ysyxsoc.soc.bin \
		--max-cycles 500000000 --gpio 0`; status=$$?; \
		printf '%s\n' "$$output"; test $$status -eq 0; \
		printf '%s\n' "$$output" | grep -q 'SoC CSR/timer smoke passed'; \
		printf '%s\n' "$$output" | grep -q 'SoC GOOD TRAP'

test-gpio: $(BIN)
	$(MAKE) -C $(GPIO_TEST) ARCH=minirv-ysyxsoc soc-image
	@accepted=`$(BIN) --headless \
		--image $(GPIO_TEST)/build/soc-gpio-smoke-minirv-ysyxsoc.soc.bin \
		--max-cycles 500000000 --gpio 0x0265`; status=$$?; \
		printf '%s\n' "$$accepted"; test $$status -eq 0; \
		printf '%s\n' "$$accepted" | grep -q 'gpio_out=0x600d'; \
		printf '%s\n' "$$accepted" | grep -q 'gpio_digits=0x25100265'; \
		rejected=`$(BIN) --headless \
		--image $(GPIO_TEST)/build/soc-gpio-smoke-minirv-ysyxsoc.soc.bin \
		--max-cycles 500000000 --gpio 0`; status=$$?; \
		printf '%s\n' "$$rejected"; test $$status -eq 0; \
		printf '%s\n' "$$rejected" | grep -q 'gpio_out=0xdead'; \
		printf '%s\n' "$$rejected" | grep -q 'gpio_digits=0x25100265'

test-hello: $(BIN)
	@output=`$(BIN) --headless \
		--image $(YSYXSOC_HOME)/ready-to-run/minirv/hello-minirv-ysyxsoc.bin \
		--max-cycles 500000000 --gpio 0`; status=$$?; \
		printf '%s\n' "$$output"; test $$status -eq 0; \
		printf '%s\n' "$$output" | grep -q 'Hello, AbstractMachine!'; \
		printf '%s\n' "$$output" | grep -q 'SoC GOOD TRAP'


test-sigint: $(BIN)
	@set +e; \
		SDL_VIDEODRIVER=dummy $(BIN) --image $(abspath $(IMG)) --max-cycles 0 \
			>$(BUILD_DIR)/sigint.log 2>&1 & pid=$$!; \
		sleep 1; kill -INT $$pid; wait $$pid; status=$$?; set -e; \
		cat $(BUILD_DIR)/sigint.log; \
		test $$status -eq 130; \
		grep -q '收到 Ctrl-C' $(BUILD_DIR)/sigint.log

# smoke 只检查统一后的 NVBoard/SoC 可执行文件能够完成构建。
smoke: $(BIN)
	@echo 'PASS: ysyxSoC NVBoard simulator built'

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run test-runtime test-gpio test-hello test-sigint smoke clean
