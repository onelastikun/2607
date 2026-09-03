#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace npc {

// NPC 物理内存从 0x80000000 开始，大小为 128 MiB。
// 这两个常量由镜像加载、DPI-C 内存访问和 DiffTest 共同使用。
constexpr std::uint32_t kPmemBase = 0x80000000u;
constexpr std::size_t kPmemSize = 128u * 1024u * 1024u;

// 命令行解析后的运行配置。路径为空表示对应功能未启用。
struct Options {
  std::string image_path;  // 客户程序的裸二进制镜像路径
  std::string wave_path;   // VCD 波形输出路径
  std::string diff_path;   // NEMU DiffTest 共享库路径
  std::uint64_t max_cycles = 100;  // 防止客户程序失控的总线周期上限
  bool itrace = false;             // 是否打印逐条提交轨迹
};

// DPI-C 回调和仿真主循环共享的结束状态。
// halted 表示客户程序主动执行 ebreak；aborted 表示仿真器发现错误。
struct RunState {
  bool halted = false;
  bool aborted = false;
  std::uint32_t code = 0;  // ebreak 时 a0 中携带的退出码
  std::uint32_t pc = 0;    // 结束或出错时对应的客户 PC
};

}  // 命名空间 npc
