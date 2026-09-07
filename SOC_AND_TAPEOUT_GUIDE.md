# E7 SoC 代码导读与后续流片准备

更新日期：2026-09-07

本文是 `npc/README.md` 的 SoC 补充说明。前者系统讲解 NPC 的 C++ 仿真器和
MiniRV/AXI 代码；本文重点解释新加入的 ysyxSoC 仿真、AM 平台、GPIO、NVBoard，
以及后续参加流片前需要由你亲自完成和确认的工作。

官方讲义：

- E7：`https://ysyx.oscc.cc/docs/2607/e/7.html`
- E8：`https://ysyx.oscc.cc/docs/2607/e/8.html`

## 1. 当前完成到了哪里

已经完成 E7 的功能实现：

- CPU 只实现 8 条 MiniRV 指令，以及 E7 要求的只读 CSR 和仿真 `ebreak`；
- CPU 从 SoC 的 `0x30000000` SPI XIP 地址启动；
- 官方 bootloader 从 Flash 中找到 ELF，并把可加载段搬到 `0x80000000` PSRAM；
- CPU 在 PSRAM 中运行 AM 程序；
- UART 16550 可初始化并输出；
- `mvendorid`、`marchid`、`mcycle/mcycleh` 可读；
- AM uptime 由 `mcycle` 换算；
- GPIO 支持 LED 输出、拨码输入和 8 位十六进制数码管；
- NVBoard 已连接 GPIO、数码管和 UART；
- 仿真 DPI 已由 `SYNTHESIS` 宏隔离，不进入综合网表。

按用户要求，`minirvEMU` 暂缓，也没有执行耗时的 SoC MicroBench、archbench、频率扫描和性能优化评测。
这不影响当前功能结论，但不能把“功能通过”写成“性能达标”。

## 2. SoC RTL 分层

### 2.1 `ysyx_25100265.sv`

这是正式学号命名的 CPU 顶层，职责只有三项：

1. 实例化已经验证过的 `minirv_core`；
2. 实例化 SimpleBus 主设备适配器；
3. 在非综合仿真中把提交、非法指令和 `ebreak` 通知 C++。

复位向量改为 `0x30000000`，因为接入 SoC 后第一条指令不再来自 NPC 主存，而是来自
SPI Flash XIP 窗口。`MARCHID` 默认值是十进制 `25100265`。

DPI 代码位于：

```systemverilog
`ifndef SYNTHESIS
  // import 和回调
`endif
```

这样 Verilator 可以观察 good trap，而综合工具定义 `SYNTHESIS` 后只看到纯硬件逻辑。
后续提交 RTL 给综合流程时，要继续保持这个边界，不能让文件 I/O、DPI 或测试路径进入
CPU 的可综合部分。

### 2.2 `minirv_simple_bus_master.sv`

核心原来的接口近似“请求后马上得到数据”，SoC 的 SimpleBus 则是：

- 主设备发出一个请求脉冲；
- 从设备可能等待很多周期；
- 完成时返回 `respValid` 和读数据。

适配器使用六个简单状态：

```text
FETCH_REQ  -> FETCH_RESP
LOAD_REQ   -> LOAD_RESP
STORE_REQ  -> STORE_RESP
```

只有收到对应 `respValid` 才让 `core_step=1`，因此 Flash、PSRAM、APB 外设无论等待
多少周期，CPU 都不会提前提交指令。

对于非对齐到 32 位数据通道低位的字节/半字访问，适配器根据地址低两位移动写数据、
写掩码和读响应。这是“地址中的字节位置”和“总线字节 lane”之间的转换，不是改变
程序的小端序语义。

### 2.3 `mygpio_top_apb.sv`

GPIO 是独立 APB 从设备，寄存器如下：

| 偏移 | 方向 | 说明 |
| ---: | :---: | --- |
| `0x0` | 读写 | 低 16 位连接 LED/GPIO 输出 |
| `0x4` | 只读 | 低 16 位连接拨码/GPIO 输入 |
| `0x8` | 读写 | 8 个 4 位十六进制数字 |

APB 访问只在 `PSEL && PENABLE` 的 access 阶段完成；写入尊重 `PSTRB` 字节掩码。
数码管寄存器保存的是 8 个十六进制数位，组合译码函数再生成 8 路段码。状态寄存器
只在时钟沿更新，读数据和段码均为组合逻辑。

## 3. SoC C++ 代码导读（面向只熟悉 C 的读者）

目录：`npc/soc/csrc/`。

### 3.1 先把 C++ 看成“带资源自动管理的 C”

本目录没有模板元编程、继承框架或复杂运算符重载，只使用了几项基础 C++ 能力：

- `namespace npc::soc`：相当于给函数名统一加前缀，防止重名；
- `class`：把数据和操作这些数据的函数放在一起；
- 构造函数：对象创建时完成初始化；
- 析构函数：离开作用域时自动释放波形和 DUT；
- `std::unique_ptr<T>`：只能有一个所有者的指针，析构时自动 `delete`；
- `std::string`：自动管理长度和内存的字符串；
- `std::array<T, N>`：固定长度数组，大小仍在编译期确定；
- `try/catch`：把文件读取、越界等错误统一交给入口处理。

读代码时可以把：

```cpp
npc::soc::Simulator simulator(options);
```

理解为 C 风格的：

```c
Simulator simulator;
simulator_init(&simulator, &options);
```

区别是 C++ 构造函数自动执行初始化，作用域结束时析构函数又自动清理资源。

### 3.2 `main.cpp`：只负责编排

主流程依次执行：

1. 解析参数；
2. 读取 Flash 镜像；
3. 绑定 DPI 运行时状态；
4. 创建仿真器并复位；
5. 循环推进时钟；
6. 根据 abort、timeout、bad trap 或 good trap 返回不同状态。

`main` 不解析 SPI、不实现 GPIO，也不直接操作 Verilator 内部状态。这样出错时可以按
模块定位，而不是在一个超长函数里混合调试。

### 3.3 `FlashImage`：封装 Flash 文件

`flash_image.cpp` 把二进制文件读入 `std::vector<uint8_t>`。可以把 vector 理解成会
自动扩容和释放的字节数组。`read_word()` 检查地址和长度，再按小端序组合 32 位数据。

RTL Flash 模型调用 C 函数：

```cpp
extern "C" void flash_read(int address, int *data);
```

`extern "C"` 的意思不是“函数用 C 编写”，而是要求编译器使用 C 的符号命名规则，
这样 SystemVerilog DPI 才能按固定名字找到它。

### 3.4 `RunState` 与 DPI 回调

`RunState` 是普通结构体，保存：

- 是否 halt/abort；
- 退出码和 PC；
- 最近提交指令；
- 指令总数；
- UART 输出。

`runtime.cpp` 中的全局指针只负责让 DPI 的 C 接口找到当前仿真对象。CPU 调用
`npc_commit()`、`npc_ebreak()`、`npc_abort()` 后，只更新 `RunState`，真正的退出策略
仍由 `main.cpp` 决定。

### 3.5 `Simulator`：双时钟和可观测性

`Simulator::step()` 每个仿真时间量翻转 CPU 时钟，每两个时间量翻转 SoC 时钟，所以
CPU:SoC 为 2:1。只有 CPU 时钟变高时才累计一个 CPU 周期。

仿真器还观察 GPIO 输出变化，并把 8 路段码反向解码为 32 位十六进制数。这样测试能
确认“APB 事务真的到达 GPIO 引脚”，而不是只看软件最后执行了 `ebreak`。

### 3.6 为什么 UART 还有一个 APB monitor

`uart_apb_monitor.sv` 通过 `bind` 旁路观察已经到达 16550 的 APB 写事务，并调用
`soc_uart_write()` 把字符打印到宿主终端。它不产生 ready、不修改寄存器，也不替代
UART。NVBoard 版本同时连接真实串行 TX 引脚，因此软件终端和引脚路径可以分别验证。

## 4. AM 的 `minirv-ysyxsoc`

SoC AM 程序只使用讲义规定的 `minirv-ysyxsoc`。MiniRV 工具先借助 RV32E ABI
编译 C 程序，再把复杂指令展开为 8 条 MiniRV 指令的组合。这里的 RV32E 仅表示
16 寄存器 ABI，不表示硬件支持完整 RV32E。

程序链接到 `0x80000000`。`platform/ysyxsoc.mk` 不直接把裸 bin 交给 SoC，而是：

1. 复制 ELF；
2. 向 ELF 副本写入 `mainargs`；
3. 调用官方 `ready-to-run/minirv/gen.sh`；
4. 把 ELF 放入 Flash 模板固定偏移；
5. 运行时由 bootloader 解析 ELF program header 并搬到 PSRAM。

UART 运行时初始化 16550 的 DLAB、除数、8N1、FIFO 和中断使能。`putch()` 轮询
LSR[5]，确认发送保持寄存器为空后才写字符。

AM uptime 连续读取 `mcycleh/mcycle/mcycleh`，只有两次高位相等时才接受结果，避免
32 位 CPU 在低 32 位回绕时得到不一致的 64 位值。

## 5. 常用短回归

从仓库根目录执行：

```bash
source .envrc

# MiniRV 架构状态与 NEMU 逐指令一致
make -C npc test-diff

# SoC CSR、UART、mcycle 和 AM uptime
make -C npc/soc test-runtime

# SoC 流水灯、密码锁和 8 位数码管
make -C npc/soc test-gpio

# NVBoard 构建/启动 smoke 与完整 GPIO 镜像
make -C npc/soc/nvboard smoke
make -C npc/soc/nvboard test-gpio
```

官方 MiniRV 大镜像回归耗时明显更长，仅在改动 MiniRV 指令替换、Flash boot 或 PSRAM
路径后按需运行：

```bash
make -C npc/soc test-hello
```

## 6. 你后续参与 E 阶段流片需要亲自做什么

### 6.1 能独立解释和调试代码

流片不是只提交“能过测试”的目录。你至少应能说明：

- 8 条 MiniRV 指令如何生成立即数、写回值和下一 PC；
- load/store 的字节 lane、符号扩展和写掩码；
- AXI/SimpleBus 为什么必须等待响应；
- Flash boot、PSRAM 搬运和 AM 链接地址的关系；
- UART、GPIO 和 mcycle 的软件/硬件边界；
- C++ 仿真器如何判断一条指令提交和 good/bad trap。

建议从 `npc/README.md` 和本文开始，逐个模块对照波形及短测试阅读。

### 6.2 完成真实板上验证

当前只有 Verilator 和 NVBoard 软件验证，没有物理 FPGA 结论。你需要在具备板卡后：

- 检查时钟、复位和引脚约束；
- 验证 UART 的实际波特率和字符输出；
- 用拨码开关验证密码锁输入；
- 验证 LED 流水灯速度在人眼可见范围；
- 验证 8 个数码管的位序、段序和有效电平；
- 记录板卡型号、工具版本、bitstream 和实测现象。

当前 smoke 程序中的短延时只为仿真，不适合真实 LED 流水灯；板上程序应根据真实
CPU 频率用 mcycle 或定时器产生可见延时。

### 6.3 整理正式提交 RTL

在进入综合前需要：

- 确认正式顶层名、端口和申请编号符合当期讲义；
- 将仿真 monitor、Flash C++ 模型、NVBoard C++ 排除在综合 file list 外；
- 用 `SYNTHESIS` 宏确认 DPI 不进入网表；
- 把 GPIO 实现纳入正式 ysyxSoC 分支或物理设计 file list，不能只依赖仿真 Makefile overlay；
- 清理锁存器、多驱动、未定宽常量、组合环、未复位状态和跨时钟域风险；
- 固化 CPU/SoC 时钟频率、UART 除数和 AM 的 `YSYXSOC_CPU_FREQ`，保证三者一致。

### 6.4 重新执行当期要求的功能回归

讲义、仓库分支和提交要求可能更新。正式报名/提交前应重新查看官网和群内通知，至少
重新运行 ISA/DiffTest、AM、SoC 启动、UART、GPIO、综合 lint 等功能回归。当前按用户
要求跳过的长性能评测，如果当期流片验收明确要求，则仍需要由你补跑并保存结果。

### 6.5 身份、Git 和提交记录

根 `Makefile` 中的 `STUID/STUNAME` 是用户自己的未提交修改，本次实现没有代为提交。
你需要确认身份准确后，按讲义要求运行 tracer/提交命令，检查每个阶段提交可复现，且
不要把 build、波形、PDK、第三方大仓库或密钥提交到 Git。

## 7. E8 物理设计与流片准备摘要（只总结，尚未执行）

下面是进入 E8 后的建议顺序。本仓库目前没有运行这些步骤，也没有 PPA、DRC/LVS 或
签核结论。

### 7.1 固化可综合 RTL 和约束

- 明确顶层、时钟、复位、输入输出延迟和 false/multicycle path；
- 确认没有 DPI、initial 测试逻辑、不可综合系统任务和仿真专用模块；
- 统一复位极性、时钟域和配置寄存器默认值；
- 对 CDC/RDC 风险建立清单。

### 7.2 逻辑综合与网表检查

- 使用讲义指定的 `yosys-sta`/统一工艺库和脚本；
- 执行 RTL 到门级网表的综合；
- 检查未映射单元、锁存器、多驱动、常量传播和意外删除逻辑；
- 对比综合前后的寄存器、存储结构、面积和关键路径；
- 不自行换成讲义未要求的流程来替代验收工具。

### 7.3 静态时序分析与 PPA

- 检查 setup/hold、最大组合路径、扇出和时钟不确定度；
- 区分真实关键路径与约束错误造成的假违例；
- 优化时优先改长组合链、译码扇出、比较/移位/加法路径和寄存器边界；
- 同时记录频率、面积和功耗估计，避免只追求某一个数字；
- 每次优化后重新跑功能等价/门级回归，防止 PPA 改动破坏架构行为。

### 7.4 DFT、ATPG 与可测性

- 理解 scan chain、测试模式、测试时钟和测试复位；
- 确认时钟门控、异步复位、存储器和黑盒单元的 DFT 处理方式；
- 生成并检查 ATPG pattern、覆盖率和未覆盖故障；
- 保证测试模式不会改变正常功能模式的时序和接口。

### 7.5 布局布线与时钟树

- 按 flow 的 stage/snapshot 管理 floorplan、placement、CTS、routing；
- 规划宏单元、IO、电源网络、拥塞和利用率；
- CTS 后重新处理 setup/hold、时钟偏斜和插入延时；
- 布线后检查串扰、天线效应、过渡时间、最大电容和电源完整性。

### 7.6 签核与流片前检查

- RTL 仿真、综合网表仿真和带延时后仿真结果一致；
- STA 在规定 PVT corner 下收敛；
- DRC、LVS、ERC 等物理检查通过；
- 版图、网表、约束、PDK 版本和脚本快照可追溯；
- 关键配置寄存器、复位值、时钟频率、UART 和外设地址形成最终文档；
- 按当期一生一芯流程在指定 ysyxSoC 分支提交，并完成代码审查和材料归档。

## 8. 当前明确限制

- 没有执行耗时 SoC 性能评测；
- 没有真实 FPGA 板上验证；
- SoC 外部生成 RTL/外设在 Verilator 下有较多上游 warning，当前使用 `-Wno-fatal`；
- CPU 自身的 `SYNTHESIS` lint 已通过，但尚未运行正式综合和 STA；
- GPIO 通过当前仓库 overlay 进入仿真，流片前要纳入正式综合 file list；
- E8、PDK、DFT、ATPG、布局布线和签核均未执行。
