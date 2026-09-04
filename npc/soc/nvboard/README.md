# ysyxSoC NVBoard 接入

本目录直接以官方 `SimTop` 为顶层，把 SoC 的 GPIO、七段数码管和 UART 引脚连接到
NVBoard。C++ 入口复用无界面 SoC 仿真器的 Flash 和 DPI 运行时，并按 2:1 驱动
CPU 时钟与 SoC 外设时钟。

```bash
source .envrc
make -C npc/soc/nvboard
make -C npc/soc/nvboard smoke
make -C npc/soc/nvboard test-gpio
make -C npc/soc/nvboard run IMG=/absolute/path/program.soc.bin
```

`smoke` 使用 SDL dummy 驱动运行 100 个 CPU 周期，只检查软件接入、引脚绑定和启动
流程，不声称完成物理 FPGA 板上验证。交互运行时，16 个拨码开关映射到 GPIO 输入，
16 个 LED、8 个数码管和 UART 终端显示 SoC 的真实外设引脚输出。

`test-gpio` 在 SDL dummy 驱动下完整启动短 GPIO 镜像并等待 good trap，用于验证
Flash、PSRAM、CPU、GPIO 和 NVBoard 引脚绑定的联合功能。由于当前没有物理 FPGA
开发板，结论仅为 NVBoard 软件仿真通过，尚无真实板上验证。
