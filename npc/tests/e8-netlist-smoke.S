.section .text.entry
.global _start

_start:
  # 验证基本算术和 SRAM 读写路径；只使用 MiniRV 的 8 条基础指令。
  lui  x1, %hi(scratch)
  addi x1, x1, %lo(scratch)
  lui  x2, 0x12345
  addi x2, x2, 0x678
  sw   x2, 0(x1)
  lw   x3, 0(x1)
  addi x4, x0, 0x5a
  sb   x4, 1(x1)
  lbu  x5, 1(x1)
  add  x6, x3, x5

  # JALR 必须跳过失败出口，才能写入成功魔数。
  lui  x7, %hi(success)
  addi x7, x7, %lo(success)
  jalr x0, 0(x7)

fail:
  lui  x8, 0xa0000
  lui  x9, 0xdead
  addi x9, x9, 0
  sw   x9, 0(x8)
  ebreak

success:
  # 将计算结果写入退出寄存器；外部模型会检查它，避免测试只验证“没有崩溃”。
  lui  x8, 0xa0000
  sw   x6, 0(x8)
  ebreak

.section .bss
.align 4
scratch:
  .space 4
