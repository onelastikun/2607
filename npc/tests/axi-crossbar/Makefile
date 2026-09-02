TOPNAME       := axi4_interconnect_4x4
BUILD_DIR     := $(abspath build)
OBJ_DIR       := $(BUILD_DIR)/obj_dir
BIN           := $(OBJ_DIR)/V$(TOPNAME)
VERILATOR     ?= verilator
export CCACHE_DISABLE ?= 1

VSRCS := $(abspath ../../vsrc/axi4_interconnect_4x4.sv)
CSRCS := $(abspath main.cpp)

$(BIN): $(VSRCS) $(CSRCS) Makefile
	@mkdir -p $(BUILD_DIR)
	$(VERILATOR) --cc --exe --build --top-module $(TOPNAME) --Mdir $(OBJ_DIR) \
		-Wall -Wno-DECLFILENAME $(VSRCS) $(CSRCS) \
		-CFLAGS "-std=c++17 -O2 -Wall -Wextra"

run: $(BIN)
	$(BIN)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: run clean
