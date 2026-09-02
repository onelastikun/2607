#pragma once

#include <chrono>
#include <cstdint>

namespace npc {

// Minimal MMIO devices required by the pre-SoC AM environment.
class DeviceMap {
 public:
  DeviceMap();

  bool read(std::uint32_t address, std::uint8_t length,
            std::uint32_t &value) const;
  bool write(std::uint32_t address, std::uint32_t value,
             std::uint8_t mask) const;

  static bool is_mmio(std::uint32_t address);

 private:
  std::chrono::steady_clock::time_point boot_time_;
};

}  // namespace npc
