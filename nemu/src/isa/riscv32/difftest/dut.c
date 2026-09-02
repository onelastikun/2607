/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
***************************************************************************************/

#include <isa.h>
#include <cpu/difftest.h>
#include "../local-include/reg.h"

bool isa_difftest_checkregs(CPU_state *ref_r, vaddr_t pc) {
  bool matched = difftest_check_reg("pc", pc, ref_r->pc, cpu.pc);
  for (int i = 0; i < MUXDEF(CONFIG_RVE, 16, 32); i++) {
    matched &= difftest_check_reg(reg_name(i), pc, ref_r->gpr[i], cpu.gpr[i]);
  }
  return matched;
}

void isa_difftest_attach() {
}
