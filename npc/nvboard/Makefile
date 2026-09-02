TOPNAME       := nvboard_top
BUILD_DIR     := $(abspath build)
OBJ_DIR       := $(BUILD_DIR)/obj_dir
BIN           := $(BUILD_DIR)/$(TOPNAME)
NXDC          := constr/nvboard_top.nxdc
AUTO_BIND     := $(BUILD_DIR)/auto_bind.cpp
VERILATOR     ?= verilator
export CCACHE_DISABLE ?= 1

VSRCS := $(abspath ../vsrc/minirv_core.sv) \
         $(abspath ../vsrc/minirv_decode.sv) \
         $(abspath ../vsrc/minirv_regfile.sv) \
         $(shell find $(abspath vsrc) -name '*.sv' | sort)
CSRCS := $(shell find $(abspath csrc) -name '*.cpp' | sort) $(AUTO_BIND)

include $(NVBOARD_HOME)/scripts/nvboard.mk

$(AUTO_BIND): $(NXDC)
	@mkdir -p $(BUILD_DIR)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $< $@

$(BIN): $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE)
	$(VERILATOR) --cc --exe --build --top-module $(TOPNAME) --Mdir $(OBJ_DIR) \
		-Wall -Wno-DECLFILENAME $(VSRCS) $(CSRCS) $(NVBOARD_ARCHIVE) \
		-CFLAGS "-std=c++17 -O2 -Wall -Wextra $(shell sdl2-config --cflags) -I$(NVBOARD_HOME)/usr/include" \
		-LDFLAGS "$(shell sdl2-config --libs) -lSDL2_image -lSDL2_ttf" \
		-o $(BIN)

all: $(BIN)

run: $(BIN)
	$(BIN)

smoke: $(BIN)
	SDL_VIDEODRIVER=dummy $(BIN) --cycles 100

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run smoke clean
