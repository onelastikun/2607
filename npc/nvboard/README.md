# MiniRV NVBoard 接入

该目录只负责 NVBoard 平台适配，复用 `npc/vsrc` 中的 MiniRV 核心、译码和寄存器堆。
板级顶层不包含 DPI-C，使用 64 KiB 字节寻址存储器运行内置递增程序。

## 构建与运行

```bash
source ../../.envrc
make
make run                 # 交互窗口，持续运行
make smoke               # SDL dummy 驱动下运行 100 周期后退出
```

## 开关与显示

- `SW14=1`：LED 直接回显全部拨码开关，用于检查板级绑定；
- `SW15=1`：`SW3..SW0` 选择 `x0..x15`，LED 和数码管显示寄存器值；
- `SW15=0`：`SW6..SW4` 选择 PC、当前指令、提交信息、周期数、退出码或访存信息；
- 非法指令时 LED 显示 `0xdead`，执行 `ebreak` 时显示 `0xbeef`。

当前已完成软件构建和无窗口 smoke test；没有物理 FPGA 板上验证结论。
