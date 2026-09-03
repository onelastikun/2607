#include "runtime.h"

#include <cstdint>
#include <iomanip>
#include <iostream>

namespace {

npc::Memory *g_memory = nullptr;
npc::DeviceMap *g_devices = nullptr;
npc::RunState *g_state = nullptr;

}  // namespace

namespace npc {

void bind_runtime(Memory &memory, DeviceMap &devices, RunState &state) {
  g_memory = &memory;
  g_devices = &devices;
  g_state = &state;
}

}  // namespace npc

extern "C" std::uint32_t pmem_read(std::uint32_t address,
                                    std::uint8_t length) {
  std::uint32_t value = 0;
  if (g_devices != nullptr && g_devices->read(address, length, value)) {
    return value;
  }
  return g_memory == nullptr ? 0 : g_memory->read(address, length);
}

extern "C" void pmem_write(std::uint32_t address, std::uint32_t data,
                           std::uint8_t mask) {
  if (g_devices != nullptr && g_devices->write(address, data, mask)) return;
  if (g_memory != nullptr) g_memory->write(address, data, mask);
}

extern "C" void npc_ebreak(std::uint32_t pc, std::uint32_t code) {
  if (g_state == nullptr) return;
  g_state->halted = true;
  g_state->pc = pc;
  g_state->code = code;
}

extern "C" void npc_bus_error(std::uint32_t pc, std::uint32_t cause) {
  if (g_state == nullptr) return;
  g_state->aborted = true;
  g_state->pc = pc;
  std::cerr << "bus response error before pc=0x" << std::hex << std::setw(8)
            << std::setfill('0') << pc << " cause=0x" << cause << std::dec
            << " (lite-response=" << (cause & 0x1u)
            << ", master-protocol=" << ((cause >> 1) & 0x1u)
            << ", fabric=" << ((cause >> 2) & 0x1u) << ")\n";
}

extern "C" void npc_abort(std::uint32_t pc, std::uint32_t inst) {
  if (g_state == nullptr) return;
  g_state->aborted = true;
  g_state->pc = pc;
  std::cerr << "illegal instruction at pc=0x" << std::hex << std::setw(8)
            << std::setfill('0') << pc << ": 0x" << std::setw(8) << inst
            << std::dec << '\n';
}
