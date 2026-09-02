#include "memory.h"

#include <array>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace npc {

Memory::Memory() : bytes_(kPmemSize, 0) {}

std::size_t Memory::load_image(const std::string &path) {
  if (path.empty()) {
    const std::array<std::uint32_t, 4> program = {
        0x00100093u,  // addi x1, x0, 1
        0x00208113u,  // addi x2, x1, 2
        0x00000513u,  // addi a0, x0, 0
        0x00100073u,  // ebreak
    };
    for (std::size_t i = 0; i < program.size(); ++i) {
      store_word(kPmemBase + static_cast<std::uint32_t>(i * 4), program[i]);
    }
    return program.size() * sizeof(program[0]);
  }

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
  std::uint32_t value = 0;
  for (std::uint8_t i = 0; i < length; ++i) {
    value |= static_cast<std::uint32_t>(bytes_[offset + i]) << (i * 8);
  }
  return value;
}

void Memory::write(std::uint32_t address, std::uint32_t value,
                   std::uint8_t mask) {
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

}  // namespace npc
