#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "types.h"

namespace npc {

// Byte-addressed little-endian physical memory used by the simulation adapter.
class Memory {
 public:
  Memory();

  std::size_t load_image(const std::string &path);
  std::uint32_t read(std::uint32_t address, std::uint8_t length);
  void write(std::uint32_t address, std::uint32_t value, std::uint8_t mask);

  const std::uint8_t *data() const { return bytes_.data(); }
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

}  // namespace npc
