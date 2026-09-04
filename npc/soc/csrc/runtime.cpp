// ysyxSoC 外部 Flash、UART 观察器和 CPU 事件使用的 DPI-C 回调。
#include "runtime.h"

#include <cstdio>
#include <iomanip>
#include <iostream>

namespace {

const npc::soc::FlashImage *g_flash = nullptr;
npc::soc::RunState *g_state = nullptr;

}  // 匿名命名空间

namespace npc::soc {

void bind_runtime(const FlashImage &flash, RunState &state) {
  g_flash = &flash;
  g_state = &state;
}

}  // 命名空间 npc::soc

extern "C" void flash_read(int address, int *data) {
  if (data == nullptr || g_flash == nullptr) return;
  try {
    *data = static_cast<int>(g_flash->read_word(
        static_cast<std::uint32_t>(address)));
  } catch (const std::exception &error) {
    if (g_state != nullptr) g_state->aborted = true;
    std::cerr << "flash error: " << error.what() << '\n';
    *data = 0;
  }
}

extern "C" void soc_uart_write(unsigned char ch) {
  if (g_state != nullptr) g_state->uart_output.push_back(static_cast<char>(ch));
  std::putchar(ch);
  std::fflush(stdout);
}

extern "C" void npc_commit(std::uint32_t pc, std::uint32_t instruction) {
  if (g_state == nullptr) return;
  g_state->last_pc = pc;
  g_state->last_instruction = instruction;
  ++g_state->instruction_count;
}

extern "C" void npc_ebreak(std::uint32_t pc, std::uint32_t code) {
  if (g_state == nullptr) return;
  g_state->halted = true;
  g_state->pc = pc;
  g_state->code = code;
}

extern "C" void npc_abort(std::uint32_t pc, std::uint32_t instruction) {
  if (g_state == nullptr) return;
  g_state->aborted = true;
  g_state->pc = pc;
  std::cerr << "SoC illegal instruction at pc=0x" << std::hex
            << std::setw(8) << std::setfill('0') << pc << ": 0x"
            << std::setw(8) << instruction << std::dec << '\n';
}
