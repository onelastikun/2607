// NPC 的主存模型和裸二进制镜像加载器。
#include "memory.h"

#include <array>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace npc {

// vector 同时提供连续存储和自动资源管理，初始内容全部清零。
Memory::Memory() : bytes_(kPmemSize, 0) {}

std::size_t Memory::load_image(const std::string &path) {
  if (path.empty()) {
    // 未指定镜像时装入最小自检程序，便于单独执行 `make run`。
    const std::array<std::uint32_t, 4> program = {
        0x00100093u,  // 将 x1 置为 1
        0x00208113u,  // x2 = x1 + 2，预期结果为 3
        0x00000513u,  // a0 = 0，表示 good trap
        0x00100073u,  // 执行 ebreak 结束客户程序
    };
    for (std::size_t i = 0; i < program.size(); ++i) {
      store_word(kPmemBase + static_cast<std::uint32_t>(i * 4), program[i]);
    }
    return program.size() * sizeof(program[0]);
  }

  // ate 让文件指针先位于末尾，可以在读取前检查镜像大小。
  std::ifstream input(path, std::ios::binary | std::ios::ate);
  if (!input) throw std::runtime_error("cannot open image: " + path);
  const auto end = input.tellg();
  if (end < 0 || static_cast<std::uint64_t>(end) > bytes_.size()) {
    throw std::runtime_error("invalid or oversized image: " + path);
  }
  const auto size = static_cast<std::size_t>(end);
  input.seekg(0, std::ios::beg);
  if (size != 0 && !input.read(reinterpret_cast<char *>(bytes_.data()), size)) {
    throw std::runtime_error("failed to read image: " + path);
  }
  return size;
}

std::uint32_t Memory::read(std::uint32_t address, std::uint8_t length) {
  if (length == 0 || length > 4 || !contains(address, length)) {
    report_bad_access("read", address, length);
    return 0;
  }
  const auto offset = static_cast<std::size_t>(address - kPmemBase);
  // RISC-V 使用小端序：低地址字节放到返回值的低位。
  std::uint32_t value = 0;
  for (std::uint8_t i = 0; i < length; ++i) {
    value |= static_cast<std::uint32_t>(bytes_[offset + i]) << (i * 8);
  }
  return value;
}

void Memory::write(std::uint32_t address, std::uint32_t value,
                   std::uint8_t mask) {
  // 总线写掩码允许 sb/sh/sw 共用同一个 32 位写数据接口。
  for (std::uint8_t i = 0; i < 4; ++i) {
    if ((mask & (1u << i)) == 0) continue;
    const auto byte_address = address + i;
    if (!contains(byte_address, 1)) {
      report_bad_access("write", byte_address, 1);
      return;
    }
    bytes_[byte_address - kPmemBase] =
        static_cast<std::uint8_t>(value >> (i * 8));
  }
}

// 使用 64 位中间值，防止 address+length 在 32 位上溢后误判为合法。
bool Memory::contains(std::uint32_t address, std::uint8_t length) const {
  if (address < kPmemBase) return false;
  const auto offset = static_cast<std::uint64_t>(address) - kPmemBase;
  return offset + length <= bytes_.size();
}

void Memory::store_word(std::uint32_t address, std::uint32_t value) {
  const auto offset = static_cast<std::size_t>(address - kPmemBase);
  for (std::uint8_t i = 0; i < 4; ++i) {
    bytes_[offset + i] = static_cast<std::uint8_t>(value >> (i * 8));
  }
}

// 记录第一次越界信息，主循环会在当前周期结束后统一终止仿真。
void Memory::report_bad_access(const char *operation, std::uint32_t address,
                               std::uint8_t length) {
  if (!checks_enabled_) return;
  std::ostringstream message;
  message << "memory " << operation << " out of range: addr=0x" << std::hex
          << std::setw(8) << std::setfill('0') << address << std::dec
          << " len=" << static_cast<unsigned>(length);
  faulted_ = true;
  fault_message_ = message.str();
}

}  // 命名空间 npc
