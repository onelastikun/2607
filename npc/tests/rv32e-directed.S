.section .text.entry
.global _start

_start:
  addi x10, x0, 0

  # U-type and immediate arithmetic.
  lui   x5, 0x12345
  li    x6, 0x12345000
  bne   x5, x6, fail
  addi  x5, x5, 0x678
  li    x6, 0x12345678
  bne   x5, x6, fail
  addi  x5, x0, -8
  slti  x6, x5, -7
  beq   x6, x0, fail
  sltiu x6, x5, 1
  bne   x6, x0, fail
  xori  x6, x5, -1
  li    x7, 7
  bne   x6, x7, fail
  ori   x6, x0, 0x55
  andi  x6, x6, 0x0f
  li    x7, 5
  bne   x6, x7, fail
  slli  x6, x7, 4
  srli  x6, x6, 2
  li    x7, 20
  bne   x6, x7, fail
  li    x5, -16
  srai  x6, x5, 2
  li    x7, -4
  bne   x6, x7, fail

  # Register-register ALU operations.
  li    x5, 13
  li    x6, 5
  add   x7, x5, x6
  li    x8, 18
  bne   x7, x8, fail
  sub   x7, x5, x6
  li    x8, 8
  bne   x7, x8, fail
  sll   x7, x6, x6
  li    x8, 160
  bne   x7, x8, fail
  slt   x7, x6, x5
  beq   x7, x0, fail
  li    x9, -1
  sltu  x7, x9, x5
  bne   x7, x0, fail
  xor   x7, x5, x6
  li    x8, 8
  bne   x7, x8, fail
  srl   x7, x8, x6
  bne   x7, x0, fail
  sra   x7, x9, x6
  bne   x7, x9, fail
  or    x7, x5, x6
  li    x8, 13
  bne   x7, x8, fail
  and   x7, x5, x6
  li    x8, 5
  bne   x7, x8, fail

  # All six conditional branches.
  li    x5, -1
  li    x6, 1
  beq   x5, x5, 1f
  j     fail
1:
  bne   x5, x6, 2f
  j     fail
2:
  blt   x5, x6, 3f
  j     fail
3:
  bge   x6, x5, 4f
  j     fail
4:
  bltu  x6, x5, 5f
  j     fail
5:
  bgeu  x5, x6, 6f
  j     fail
6:

  # AUIPC/JAL return-address relationship.
  auipc x5, 0
  addi  x5, x5, 12
  jal   x6, 7f
7:
  bne   x5, x6, fail

  # JALR target and link.
  lla   x5, 8f
  jalr  x6, 0(x5)
  j     fail
8:
  beq   x6, x0, fail

  # Loads, stores, sign extension and little endian layout.
  lla   x5, scratch
  li    x6, 0x80ff7f01
  sw    x6, 0(x5)
  lb    x7, 0(x5)
  li    x8, 1
  bne   x7, x8, fail
  lb    x7, 1(x5)
  li    x8, 127
  bne   x7, x8, fail
  lb    x7, 2(x5)
  li    x8, -1
  bne   x7, x8, fail
  lbu   x7, 2(x5)
  li    x8, 255
  bne   x7, x8, fail
  lh    x7, 2(x5)
  li    x8, 0xffff80ff
  bne   x7, x8, fail
  lhu   x7, 2(x5)
  li    x8, 0x80ff
  bne   x7, x8, fail
  lw    x7, 0(x5)
  bne   x7, x6, fail
  li    x6, 0x55
  sb    x6, 1(x5)
  lbu   x7, 1(x5)
  bne   x7, x6, fail
  li    x6, 0x1234
  sh    x6, 2(x5)
  lhu   x7, 2(x5)
  bne   x7, x6, fail

  # x0 must stay zero; FENCE is accepted as a no-op.
  addi  x0, x0, 1
  bne   x0, x10, fail
  fence

pass:
  addi  x10, x0, 0
  ebreak

fail:
  addi  x10, x0, 1
  ebreak

.section .bss
.align 4
scratch:
  .space 16
