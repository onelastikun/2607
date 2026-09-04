#include "flash_image.h"

#include <fstream>
#include <stdexcept>

namespace npc::soc {

void FlashImage::load(const std::string &path) {
  std::ifstream input(path, std::ios::binary | std::ios::ate);
  if (!input) throw std::runtime_error("cannot open SoC image: " + path);
  const auto end = input.tellg();
  if (end < 0) throw std::runtime_error("cannot determine SoC image size");
  bytes_.resize(static_cast<std::size_t>(end));
  input.seekg(0, std::ios::beg);
  if (!bytes_.empty() &&
      !input.read(reinterpret_cast<char *>(bytes_.data()), bytes_.size())) {
    throw std::runtime_error("failed to read SoC image: " + path);
  }
}

std::uint32_t FlashImage::read_word(std::uint32_t address) const {
  if (static_cast<std::uint64_t>(address) + 4 > bytes_.size()) {
    throw std::runtime_error("SPI flash read out of range at address " +
                             std::to_string(address));
  }
  std::uint32_t value = 0;
  for (unsigned i = 0; i < 4; ++i) {
    value |= static_cast<std::uint32_t>(bytes_[address + i]) << (i * 8);
  }
  return value;
}

}  // 命名空间 npc::soc
