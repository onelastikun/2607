.section .text.entry
.global _start

_start:
  lui  x1, 0xc0000
  lw   x2, 0(x1)
  addi x10, x0, 0
  ebreak
