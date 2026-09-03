#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "types.h"

namespace npc {

// 仿真器中的字节寻址、小端物理内存模型。
// RTL 总线从设备最终通过 DPI-C 调用这里，而 CPU 核心本身不依赖 C++ 内存。
class Memory {
 public:
  Memory();

  // 把裸二进制镜像装入物理内存起始位置，返回实际装入的字节数。
  std::size_t load_image(const std::string &path);
  // length 表示从 address 开始读取的字节数，合法范围为 1~4。
  std::uint32_t read(std::uint32_t address, std::uint8_t length);
  // mask 位 i 为 1 时，只写入 address+i 对应的那个字节。
  void write(std::uint32_t address, std::uint32_t value, std::uint8_t mask);

  // DiffTest 初始化时需要直接复制镜像内容到参考模型。
  const std::uint8_t *data() const { return bytes_.data(); }
  // 复位阶段可能出现组合求值，复位结束后再启用越界检查以减少误报。
  void enable_checks() { checks_enabled_ = true; }
  bool faulted() const { return faulted_; }
  const std::string &fault_message() const { return fault_message_; }

 private:
  bool contains(std::uint32_t address, std::uint8_t length) const;
  void store_word(std::uint32_t address, std::uint32_t value);
  void report_bad_access(const char *operation, std::uint32_t address,
                         std::uint8_t length);

  std::vector<std::uint8_t> bytes_;
  bool checks_enabled_ = false;
  bool faulted_ = false;
  std::string fault_message_;
};

}  // 命名空间 npc
