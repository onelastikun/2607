#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace npc::soc {

// ysyxSoC 外部 SPI Flash 的只读字节数组模型。
class FlashImage {
 public:
  void load(const std::string &path);
  std::uint32_t read_word(std::uint32_t address) const;
  std::size_t size() const { return bytes_.size(); }

 private:
  std::vector<std::uint8_t> bytes_;
};

}  // 命名空间 npc::soc
