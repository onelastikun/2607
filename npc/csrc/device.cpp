// AM 所需的串口和微秒计时器 MMIO 模型。
#include "device.h"

#include <cstdio>

namespace npc {
namespace {

// 地址与 AM 的 npc 平台约定保持一致。
constexpr std::uint32_t kRtcAddress = 0xa0000048u;
constexpr std::uint32_t kSerialAddress = 0xa00003f8u;

}  // 匿名命名空间

// 构造时刻作为客户程序可见 uptime 的零点。
DeviceMap::DeviceMap() : boot_time_(std::chrono::steady_clock::now()) {}

bool DeviceMap::read(std::uint32_t address, std::uint8_t length,
                     std::uint32_t &value) const {
  if ((address != kRtcAddress && address != kRtcAddress + 4) || length != 4) {
    return false;
  }

  // 32 位 CPU 分两次读取 64 位计时器：低地址是低 32 位，高地址是高 32 位。
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
  // 串口寄存器只有最低字节有效；其余写掩码位不产生输出。
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

}  // 命名空间 npc
