include $(AM_HOME)/scripts/isa/riscv.mk
include $(AM_HOME)/scripts/platform/ysyxsoc.mk

# MiniRV 包装器会把复杂 RV32E 指令展开成讲义要求的最小指令集合。
export PATH := $(PATH):$(abspath $(AM_HOME)/tools/minirv)
CC = minirv-gcc
AS = minirv-gcc
CXX = minirv-g++

COMMON_CFLAGS += -march=rv32e_zicsr -mabi=ilp32e
LDFLAGS       += -melf32lriscv

AM_SRCS += riscv/npc/libgcc/div.S \
           riscv/npc/libgcc/muldi3.S \
           riscv/npc/libgcc/multi3.c \
           riscv/npc/libgcc/ashldi3.c \
           riscv/npc/libgcc/unused.c
