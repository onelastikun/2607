# ysyxSoC 平台复用 NPC 的启动、异常和软件除法代码，只替换板级运行时与计时器。
AM_SRCS := riscv/npc/start.S \
           riscv/ysyxsoc/trm.c \
           riscv/ysyxsoc/ioe.c \
           riscv/ysyxsoc/timer.c \
           riscv/npc/input.c \
           riscv/npc/cte.c \
           riscv/npc/trap.S \
           platform/dummy/vme.c \
           platform/dummy/mpe.c

CFLAGS    += -fdata-sections -ffunction-sections
LDSCRIPTS += $(AM_HOME)/scripts/linker.ld
LDFLAGS   += --defsym=_pmem_start=0x80000000 --defsym=_entry_offset=0x0
LDFLAGS   += --gc-sections -e _start

# 当前仿真器按 CPU:SoC=2:1 驱动，SoC 时钟按 UART 标准基准取 1.8432 MHz。
YSYXSOC_CPU_FREQ ?= 3686400
CFLAGS += -DYSYXSOC_CPU_FREQ=$(YSYXSOC_CPU_FREQ)

MAINARGS_MAX_LEN = 64
MAINARGS_PLACEHOLDER = the_insert-arg_rule_in_Makefile_will_insert_mainargs_here
CFLAGS += -DMAINARGS_MAX_LEN=$(MAINARGS_MAX_LEN) -DMAINARGS_PLACEHOLDER=$(MAINARGS_PLACEHOLDER)

SOC_ELF := $(IMAGE).soc.elf
SOC_BIN := $(IMAGE).soc.bin

# mainargs 写入 ELF 副本，避免破坏原始 ELF 中只能匹配一次的占位字符串。
$(SOC_ELF): $(IMAGE).elf
	@cp $< $@
	@python $(AM_HOME)/tools/insert-arg.py $@ $(MAINARGS_MAX_LEN) \
		$(MAINARGS_PLACEHOLDER) "$(mainargs)"

# ysyxSoC 的 bootloader 从 Flash 固定偏移读取 ELF，并将 PT_LOAD 段搬到 PSRAM。
$(SOC_BIN): $(SOC_ELF)
	@echo + PACK "->" $(shell realpath --relative-to . $@)
	@cd $(YSYXSOC_HOME)/ready-to-run/minirv && \
		bash gen.sh $(abspath $(SOC_ELF)) $(abspath $(SOC_BIN))

image: image-dep
	@$(OBJDUMP) -d $(IMAGE).elf > $(IMAGE).txt

soc-image: $(SOC_BIN)

YSYXSOC_RUN_FLAGS ?= MAX_CYCLES=500000000
run: soc-image
	$(MAKE) -C $(NPC_HOME)/soc run IMG=$(SOC_BIN) $(YSYXSOC_RUN_FLAGS)

.PHONY: soc-image
