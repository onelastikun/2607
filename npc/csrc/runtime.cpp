// RTL 与 C++ 运行时之间的 DPI-C 边界。
#include "runtime.h"

#include <cstdint>
#include <iomanip>
#include <iostream>

namespace {

// DPI-C 要求导出普通 C 函数；这些非拥有型指针把回调转发到 C++ 对象。
// 对象由 main 创建并在仿真结束后销毁，这里不能 delete 它们。
npc::Memory *g_memory = nullptr;
npc::DeviceMap *g_devices = nullptr;
npc::RunState *g_state = nullptr;

}  // 匿名命名空间

namespace npc {

void bind_runtime(Memory &memory, DeviceMap &devices, RunState &state) {
  g_memory = &memory;
  g_devices = &devices;
  g_state = &state;
}

}  // 命名空间 npc

// 总线从设备统一调用此入口：先匹配 MMIO，未命中时再访问主存。
extern "C" std::uint32_t pmem_read(std::uint32_t address,
                                    std::uint8_t length) {
  std::uint32_t value = 0;
  if (g_devices != nullptr && g_devices->read(address, length, value)) {
    return value;
  }
  return g_memory == nullptr ? 0 : g_memory->read(address, length);
}

// 写掩码沿总线路径原样传入，设备和主存分别解释每个字节使能位。
extern "C" void pmem_write(std::uint32_t address, std::uint32_t data,
                           std::uint8_t mask) {
  if (g_devices != nullptr && g_devices->write(address, data, mask)) return;
  if (g_memory != nullptr) g_memory->write(address, data, mask);
}

// ebreak 不直接结束宿主进程，只记录状态，由 main 统一决定退出码。
extern "C" void npc_ebreak(std::uint32_t pc, std::uint32_t code) {
  if (g_state == nullptr) return;
  g_state->halted = true;
  g_state->pc = pc;
  g_state->code = code;
}

// cause 的低三位依次表示 Lite 响应、主设备协议和互联内部错误。
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

// 非法指令属于架构执行错误，与总线响应错误分开报告。
extern "C" void npc_abort(std::uint32_t pc, std::uint32_t inst) {
  if (g_state == nullptr) return;
  g_state->aborted = true;
  g_state->pc = pc;
  std::cerr << "illegal instruction at pc=0x" << std::hex << std::setw(8)
            << std::setfill('0') << pc << ": 0x" << std::setw(8) << inst
            << std::dec << '\n';
}
