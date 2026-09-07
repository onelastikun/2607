.section .text.entry
.global _start

_start:
  # 构造 scratch 地址，只使用 LUI 和 ADDI。
  lui  x1, %hi(scratch)
  addi x1, x1, %lo(scratch)

  # SW/LW：写入后读回，再与相反数相加，结果应为 0。
  lui  x2, 0x12345
  addi x2, x2, 0x678
  sw   x2, 0(x1)
  lw   x3, 0(x1)
  lui  x4, 0xedcbb
  addi x4, x4, -0x678
  add  x10, x3, x4

  # SB/LBU：修改第 1 字节并零扩展读回，再抵消为 0。
  addi x5, x0, 170
  sb   x5, 1(x1)
  lbu  x6, 1(x1)
  addi x7, x0, -170
  add  x10, x6, x7

  # JALR：跳到完成标签；跳转失败会执行 bad trap。
  lui  x5, %hi(finish)
  addi x5, x5, %lo(finish)
  jalr x6, 0(x5)
  addi x10, x0, 1
  ebreak

finish:
  ebreak

.section .bss
.align 4
scratch:
  .space 4
