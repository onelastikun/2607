# MiniRV 接入 ysyxSoC

本目录使用 `ysyxSoC/ready-to-run/minirv/ElaborateTop.v`，把学号顶层
`ysyx_25100265` 通过 SimpleBus 接入 ysyxSoC，并使用 Verilator 驱动 `SimTop`。

## 结构

- `../vsrc/soc/ysyx_25100265.sv`：符合学号命名的 CPU SimpleBus 顶层；
- `../vsrc/soc/NPC.sv`：适配 ready-to-run 文件固定使用的 `NPC` 模块名；
- `../vsrc/soc/minirv_simple_bus_master.sv`：取指和 LSU 请求状态机；
- `csrc/flash_image.cpp`：外部 SPI Flash 镜像；
- `csrc/simulator.cpp`：统一驱动双时钟、波形和 NVBoard；
- `constr/SimTop.nxdc`：开关、LED、数码管和 UART 引脚绑定；
- ysyxSoC 官方 16550 模型在 `__UART_TO_CONSOLE__` 配置下直接输出 UART 字符，
  当前不再维护额外的 UART APB 旁路监视器。

仿真使用 `PDK_BEHAV` 行为级 PAD，不需要也不会加载流片 PDK。

## 使用

`minirv-ysyxsoc` 默认直接打开 NVBoard，不再维护单独的 NVBoard 子工程。例如：

```bash
cd /home/onelastikun/to_test/ysyx-workbench
source .envrc
make -C am-kernels/tests/am-tests ARCH=minirv-ysyxsoc mainargs=t
```

不写目标时会自动完成编译、Flash 打包并打开 NVBoard。程序 good trap 后会保留最后的
LED 和数码管状态。关闭 NVBoard 窗口或按 `Ctrl-C` 均可退出；`Ctrl-C` 会先关闭
VCD、NVBoard 和 Verilator，再以状态码 130 结束。

也可以直接运行指定镜像：

```bash
make -C npc/soc run IMG=/absolute/path/program.soc.bin
```

可选参数：

```bash
make -C npc/soc run GPIO=0x1234
make -C npc/soc run WAVE=build/soc.vcd
make -C npc/soc run HEADLESS=1 MAX_CYCLES=500000000
```

`HEADLESS=1` 仅用于自动测试；普通运行默认打开 NVBoard。

SoC 从 SPI XIP 地址 `0x30000000` 启动，bootloader 解析 Flash 中嵌入的 ELF，
把可加载段搬运到 `0x80000000` 起始的 PSRAM 后跳转执行。因此完整启动比 NPC
直连主存慢很多；默认 hello 在当前双时钟配置下约需要 3.1 亿个 CPU 周期。

## AM 架构与短回归

SoC AM 程序统一使用讲义规定的 `ARCH=minirv-ysyxsoc`。MiniRV 工具链会把
普通 C 编译产生的指令替换为 8 条 MiniRV 基础指令，再把 ELF 嵌入官方 Flash 模板，
由 bootloader 搬运到 PSRAM。运行时已完成
16550 初始化与轮询输出；`AM_TIMER_UPTIME` 从 `mcycle/mcycleh` 读取周期并按
3.6864 MHz CPU 频率换算为微秒。可执行短功能回归：

```bash
source .envrc
make -C npc/soc test-runtime
```

该测试检查 `mvendorid`、`marchid`、周期计时、UART 输出和 good trap，不包含耗时
性能评测。官方 MiniRV hello 的完整启动回归仍可用 `make -C npc/soc test-hello` 手动执行。

## GPIO 寄存器与实验

`vsrc/mygpio_top_apb.sv` 替换 ysyxSoC 中留空的同名教学模块，寄存器遵循讲义：

| 偏移 | 访问 | 功能 |
| ---: | :---: | --- |
| `0x0` | 读写 | 低 16 位控制 GPIO/LED 输出 |
| `0x4` | 只读 | 低 16 位读取 GPIO/拨码输入 |
| `0x8` | 读写 | 8 个 4 位十六进制数位，并译码到 8 个七段管端口 |

短回归把流水灯、密码锁和申请编号数码管显示合并在一个程序中，并分别检查密码
正确和错误两种输入：

```bash
source .envrc
make -C npc/soc test-gpio
```

仿真器会输出最终 `gpio_out`、反向解码得到的 `gpio_digits` 和 LED 变化次数，避免
只检查软件是否 good trap、却遗漏 APB 外设和引脚实际没有变化的问题。

## Ctrl-C 回归

```bash
source .envrc
make -C npc/soc test-sigint
```

信号处理函数只设置退出标志，资源清理由正常的 C++ 析构流程完成，避免在异步信号
上下文中调用 SDL、iostream 或 Verilator。
