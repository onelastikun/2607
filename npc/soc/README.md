# MiniRV 接入 ysyxSoC

本目录使用 `ysyxSoC/ready-to-run/minirv/ElaborateTop.v`，把学号顶层
`ysyx_25100265` 通过 SimpleBus 接入 ysyxSoC，并使用 Verilator 驱动 `SimTop`。

## 结构

- `../vsrc/soc/ysyx_25100265.sv`：符合学号命名的 CPU SimpleBus 顶层；
- `../vsrc/soc/NPC.sv`：适配 ready-to-run 文件固定使用的 `NPC` 模块名；
- `../vsrc/soc/minirv_simple_bus_master.sv`：取指和 LSU 请求状态机；
- `csrc/flash_image.cpp`：外部 SPI Flash 镜像；
- `csrc/simulator.cpp`：以 2:1 比例驱动 CPU 时钟和 SoC 时钟；
- `vsrc/uart_apb_monitor.sv`：旁路观察真正到达 16550 的 APB 写事务并输出字符。

仿真使用 `PDK_BEHAV` 行为级 PAD，不需要也不会加载流片 PDK。

## 使用

```bash
source ../../.envrc
make -C npc/soc run
```

默认运行 ysyxSoC 提供的 `hello-minirv-ysyxsoc.bin`。指定自定义镜像：

```bash
make -C npc/soc run IMG=/absolute/path/program.soc.bin
```

可选参数：

```bash
make -C npc/soc run MAX_CYCLES=500000000 GPIO=0x1234
make -C npc/soc run WAVE=build/soc.vcd
```

SoC 从 SPI XIP 地址 `0x30000000` 启动，bootloader 解析 Flash 中嵌入的 ELF，
把可加载段搬运到 `0x80000000` 起始的 PSRAM 后跳转执行。因此完整启动比 NPC
直连主存慢很多；默认 hello 在当前双时钟配置下约需要 3.1 亿个 CPU 周期。

## AM 架构与短回归

仓库提供两种 SoC AM 架构：

- `ARCH=minirv-ysyxsoc`：正式 MiniRV 指令替换路径；
- `ARCH=riscv32e-ysyxsoc`：不注入大型查找表，用于快速功能回归。

两者都会把 AM ELF 嵌入官方 Flash 模板，由 bootloader 搬运到 PSRAM。运行时已完成
16550 初始化与轮询输出；`AM_TIMER_UPTIME` 从 `mcycle/mcycleh` 读取周期并按
3.6864 MHz CPU 频率换算为微秒。可执行短功能回归：

```bash
source ../../.envrc
make -C npc/soc test-runtime
```

该测试检查 `mvendorid`、`marchid`、周期计时、UART 输出和 good trap，不包含耗时
性能评测。官方 MiniRV hello 的完整启动回归仍可用 `make -C npc/soc test-hello` 手动执行。
