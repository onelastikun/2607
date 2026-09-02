#include "device.h"

#include <cstdio>

namespace npc {
namespace {

constexpr std::uint32_t kRtcAddress = 0xa0000048u;
constexpr std::uint32_t kSerialAddress = 0xa00003f8u;

}  // namespace

DeviceMap::DeviceMap() : boot_time_(std::chrono::steady_clock::now()) {}

bool DeviceMap::read(std::uint32_t address, std::uint8_t length,
                     std::uint32_t &value) const {
  if ((address != kRtcAddress && address != kRtcAddress + 4) || length != 4) {
    return false;
  }

  const auto elapsed = std::chrono::steady_clock::now() - boot_time_;
  const auto micros = static_cast<std::uint64_t>(
      std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count());
  value = address == kRtcAddress ? static_cast<std::uint32_t>(micros)
                                 : static_cast<std::uint32_t>(micros >> 32);
  return true;
}

bool DeviceMap::write(std::uint32_t address, std::uint32_t value,
                      std::uint8_t mask) const {
  if (address != kSerialAddress) return false;
  if ((mask & 0x1u) != 0) {
    std::putchar(static_cast<unsigned char>(value));
    std::fflush(stdout);
  }
  return true;
}

bool DeviceMap::is_mmio(std::uint32_t address) {
  return address == kSerialAddress || address == kRtcAddress ||
         address == kRtcAddress + 4;
}

}  // namespace npc
