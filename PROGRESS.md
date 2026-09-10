# E 阶段进度记录

更新日期：2026-09-07

## 当前目标

正式实现只面向讲义规定的 MiniRV，不实现完整 RV32E。`minirvEMU` 按用户要求暂缓。
E7 的 NPC、AM、SimpleBus 和 ysyxSoC 功能接入保留；E8 只总结，不执行物理设计。

## MiniRV 指令范围

硬件只支持：

```text
add  addi  lui  lw  lbu  sw  sb  jalr
```

另保留：

- `ebreak`：仿真结束；
- `CSRRS rd, csr, x0`：读取 E7 要求的只读 CSR。

已删除此前额外实现的分支、JAL、AUIPC、字节符号加载、半字访问、移位、比较、逻辑、
减法、FENCE 等完整 RV32E 指令。

## NPC 与验证

已完成：

- Verilator 构建、时钟、复位和可选 VCD；
- 镜像加载、物理内存和 MMIO；
- MiniRV 寄存器堆、译码、执行和提交；
- good trap、bad trap、非法指令、总线错误和超时；
- MiniRV itrace；
- NEMU 参考模型只保留 8 条 MiniRV 指令；
- SimpleBus 主设备、NPC 主存/MMIO 从端和可配置响应延迟。

定向测试 `npc/tests/minirv-directed.S` 只包含 MiniRV 指令，覆盖 8 条基础指令。

验证结果：

```text
make -C npc test-minirv  通过，18 条指令
make -C npc test-diff    通过，与 NEMU 一致
make -C npc test-itrace  通过
make -C npc test-bus-error 通过
```

## AM

正式架构：

```text
ARCH=minirv-npc
ARCH=minirv-ysyxsoc
```

不再提供或使用额外的 `riscv32e-ysyxsoc` 快速路径。

AM CPU tests 使用 MiniRV 工具链编译。由于复杂指令会展开为较长的 MiniRV 序列，完整
测试需要显式给出足够周期：

```bash
make -C am-kernels/tests/cpu-tests \
  ARCH=minirv-npc run \
  NPC_RUN_FLAGS='MAX_CYCLES=100000000'
```

结果：35 个正常测试通过，`wrong` 按测试设计返回失败。

## ysyxSoC

已完成：

- `ysyx_25100265` CPU 顶层；
- `0x30000000` SPI Flash XIP 启动；
- bootloader 将 ELF 搬到 `0x80000000` PSRAM；
- SimpleBus 取指和访存；
- UART 16550；
- `mvendorid/marchid/mcycle/mcycleh`；
- AM uptime；
- GPIO LED、输入和 8 位数码管；
- SoC NVBoard 软件接入；
- `SYNTHESIS` 条件隔离仿真 DPI。

SoC 自建测试统一改为 `ARCH=minirv-ysyxsoc`。

## SimpleBus 对齐（2026-09-07）

已删除此前误加的 AXI4/AXI4-Lite 主设备、适配器、4x4 互联、错误从设备及其独立测试。
NPC 顶层现为：

```text
minirv_core -> minirv_simple_bus_master -> simple_bus_pmem
```

SoC 继续使用同一个 SimpleBus 主设备，ysyxSoC 内部总线转换由官方框架负责。

## 删除的额外内容

根据用户要求已删除或收缩：

- `abstract-machine/scripts/riscv32e-ysyxsoc.mk`；
- 完整 RV32E RTL 译码；
- 完整 RV32E NEMU 指令实现；
- 原生 RV32E 定向测试；
- 原生 RV32E SoC 快速回归路径；
- 文档中将完整 RV32E 作为正式目标的说明。

上游 Abstract Machine 自带的 `riscv32e-npc.mk` 和 `riscv32e-nemu.mk` 没有删除，但
本项目正式流程不使用它们。


## minirv-ysyxsoc 与 NVBoard 合并（2026-09-07）

- 删除 `npc/soc/nvboard/` 的重复 Makefile 和 C++ 入口；
- `npc/soc` 现在是唯一的 ysyxSoC 仿真入口，并默认初始化 NVBoard；
- `make ARCH=minirv-ysyxsoc` 会自动编译、打包并打开 NVBoard；
- 自动回归通过 `--headless` 复用同一个可执行文件；
- `MAX_CYCLES=0` 表示交互运行不设超时；
- good trap 后保留最后的 LED/数码管状态，直到用户关闭窗口。
- 支持捕获 `Ctrl-C`，正常关闭 VCD、NVBoard 和 Verilator，并返回状态码 130。

## 当前限制

- `minirvEMU` 暂缓；
- 没有真实 FPGA 板上验证；
- 耗时 SoC 性能评测按用户要求跳过；
- GPIO 仍通过仓库 overlay 进入仿真，流片前需纳入正式综合文件列表；
- E8 综合、STA、PPA、DFT、布局布线和签核尚未执行。

## E8 前端仿真适配（2026-09-10）

已完成当前仓库可执行的 Icarus/VPI 基础路径：

- `simple_bus_pmem.sv` 在 Icarus 下使用 `$pmem_read/$pmem_write`，Verilator 继续使用 DPI-C；
- `top.sv` 在 Icarus 下使用 `$display/$fatal/$finish` 报告 trap；
- 新增 `npc/vsrc/iverilog_top.sv` 作为时钟、复位和可选 VCD 顶层；
- 新增 `npc/iverilog/vpi_memory.cpp`，通过 VPI 注册访存系统任务并加载 `+img=FILE`；
- 新增 `make -C npc test-iverilog`；
- `minirv-directed.bin` 已通过 Icarus 四值仿真，输出 `GOOD TRAP`；
- Icarus 的 constant-select `sorry` 提示符合讲义说明，可忽略。

当前仍未完成：

- 用 Icarus 跑完完整 AM/microbench 长程序；
- ECC 综合和两种综合网表仿真；
- ECOS Studio 后端物理设计、STA、DRC/LVS 和签核包。
