#pragma once

#include <chrono>
#include <cstdint>

namespace npc {

// E6/E7 阶段所需的最小 MMIO 设备集合。
// 当前只模拟串口写和 64 位微秒计时器读；未命中的地址交给物理内存处理。
class DeviceMap {
 public:
  DeviceMap();

  // 命中设备时返回 true，并通过 value 返回读数据；否则返回 false。
  bool read(std::uint32_t address, std::uint8_t length,
            std::uint32_t &value) const;
  // 命中设备时返回 true。mask 的每一位对应 value 中的一个字节。
  bool write(std::uint32_t address, std::uint32_t value,
             std::uint8_t mask) const;

  // 供调试或地址分类使用，不执行实际的设备访问。
  static bool is_mmio(std::uint32_t address);

 private:
  // steady_clock 不受系统时间校准影响，适合表示单调递增的 uptime。
  std::chrono::steady_clock::time_point boot_time_;
};

}  // 命名空间 npc
