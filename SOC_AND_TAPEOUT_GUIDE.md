# MiniRV 项目框架与流片准备指南

更新日期：2026-09-11

本文用于两件事：

1. 帮助只熟悉 C 语言的读者快速理解当前 MiniRV/NPC/ysyxSoC 项目；
2. 按“一生一芯”v26.07 当前讲义整理从功能检查、综合、网表仿真到后端物理设计的后续路线。

本文只记录和解释流程。当前仓库已经完成 E8 前端 lint、Icarus/VPI RTL 四值仿真、
ECC 综合，以及短网表功能仿真；尚未执行 ECOS Studio 后端设计和签核，不能把本文当成
已经通过完整流片验收的证明。

更详细的 NPC C++ 入门说明见 [`npc/README.md`](npc/README.md)，实际进度见
[`PROGRESS.md`](PROGRESS.md)。

---

## 1. 先看讲义的哪些位置

| 目的 | 讲义位置 | 你要重点理解的内容 |
| --- | --- | --- |
| 理解 CPU 如何接入 SoC | E7“接入 SoC” | SimpleBus、ysyxSoC、Flash 启动和 PSRAM |
| 理解 UART/GPIO/CSR | E7“访问真实的串口控制器”“接入 NVBoard”“添加简单的控制状态寄存器” | UART、GPIO、`mvendorid/marchid/mcycle` |
| 学习综合 | E6“性能评测入门”→“通过 EDA 工具评估 NPC 的频率” | ECC、Yosys、ICsprout55 PDK、综合报告和网表 |
| 做流片前 RTL 检查 | E8“前端准备工作” | 地址空间、下降沿、锁存器、lint、复位和四值仿真 |
| 验证综合网表 | E8“网表仿真” | `_sim` 网表、标准单元行为模型、Verilator/iverilog |
| 做后端物理设计 | E8“后端物理设计” | ECOS Studio、Floorplan、签核包 |
| 申请答辩 | E9“提交入学答辩申请” | 当期必做题、材料和申请要求 |

官方页面：

- E6：`https://ysyx.oscc.cc/docs/2607/e/6.html`
- E7：`https://ysyx.oscc.cc/docs/2607/e/7.html`
- E8：`https://ysyx.oscc.cc/docs/2607/e/8.html`
- E9：`https://ysyx.oscc.cc/docs/2607/e/9.html`

**最容易误解的一点：综合是在 E6 中讲的。** E8 开头默认你已经使用 ECC 完成 NPC
综合并获得网表，然后才继续做网表检查和后端物理设计。

讲义及工具版本可能更新。开始综合或报名之前，应再次核对官网和当期通知，不能只照抄
本文中的日期和版本。

---

## 2. 当前项目到底实现了什么

正式硬件只实现讲义规定的 8 条 MiniRV 指令：

```text
add  addi  lui  lw  lbu  sw  sb  jalr
```

为了完成后续章节，还保留：

- `ebreak`：仿真环境用它取得 AM 程序退出码；
- `CSRRS rd, csr, x0`：只用于读取 `mvendorid`、`marchid`、`mcycle/mcycleh` 和
  `cycle/cycleh`。

MiniRV 使用 RV32E 的 16 个通用寄存器，即 `x0~x15`。AM 编译时出现
`-march=rv32e_zicsr -mabi=ilp32e`，主要是为了使用 16 寄存器 ABI；复杂指令会由
MiniRV 工具展开成上述 8 条基础指令，并不代表 RTL 实现了完整 RV32E。

当前已经形成的功能闭环是：

- NPC：MiniRV、SimpleBus、主存/MMIO、itrace、DiffTest、good/bad trap；
- AM：`minirv-npc` 和 `minirv-ysyxsoc`；
- SoC：SPI Flash XIP、bootloader、PSRAM、UART 16550、GPIO、CSR/计时；
- NVBoard：默认由统一的 `npc/soc` 仿真入口打开；
- 退出：SoC 仿真支持关闭窗口和 `Ctrl-C` 清理资源后退出。

没有完成的部分：

- `minirvEMU`；
- 真实 FPGA 板上验证；
- 按用户要求跳过的耗时 SoC 性能评测；
- ECOS Studio 后端物理设计和签核；
- 长时间的 E8 网表/AM 性能回归。

---

## 3. 从程序到 CPU 的整体框架

### 3.1 软件构建路径

```text
AM/C 程序
   │
   │  RV32E ABI 编译 + MiniRV 工具展开
   ▼
MiniRV ELF
   ├──────────────────────────┐
   │                          │
   │ minirv-npc               │ minirv-ysyxsoc
   ▼                          ▼
裸二进制 .bin             ELF 写入 Flash 模板
   │                          │
   ▼                          ▼
NPC 主存模型              .soc.bin SPI Flash 镜像
```

### 3.2 NPC 功能验证路径

```text
npc/vsrc/top.sv
  ├─ minirv_core
  │    ├─ minirv_decode
  │    └─ minirv_regfile
  ├─ minirv_simple_bus_master
  └─ simple_bus_pmem
       └─ DPI-C → C++ Memory/DeviceMap
```

NPC 路径的作用是快速验证 CPU：镜像直接装入宿主机主存数组，不需要经过 SPI Flash
boot，因此运行速度比完整 SoC 仿真快得多。DiffTest、itrace 和总线延迟测试都优先在
这条路径完成。

### 3.3 ysyxSoC 功能路径

```text
SimTop（官方 ysyxSoC 仿真顶层）
  └─ NPC.sv（只解决官方固定模块名）
       └─ ysyx_25100265（正式 CPU 顶层）
            ├─ minirv_core
            │    ├─ minirv_decode
            │    └─ minirv_regfile
            └─ minirv_simple_bus_master
                 └─ SimpleBus → 官方 ysyxSoC
                      ├─ SPI Flash
                      ├─ PSRAM
                      ├─ UART 16550
                      └─ APB GPIO
```

C++ 和 NVBoard 位于整个 SoC RTL 的外面，只负责加载 Flash 镜像、驱动时钟、显示引脚、
记录波形和处理仿真退出。它们不是 CPU，也不能进入综合文件列表。

---

## 4. 目录和模块职责

### 4.1 CPU RTL

| 文件 | 作用 | 是否属于正式 NPC 综合输入 |
| --- | --- | :---: |
| `npc/vsrc/minirv_regfile.sv` | 16 个通用寄存器，组合读、上升沿写回，`x0` 恒为 0 | 是 |
| `npc/vsrc/minirv_decode.sv` | 8 条指令、只读 CSR、立即数、访存控制和下一 PC | 是 |
| `npc/vsrc/minirv_core.sv` | 保存 PC、周期数和提交状态，用 `step` 控制提交 | 是 |
| `npc/vsrc/soc/minirv_simple_bus_master.sv` | 将核心取指/访存请求转换为 SimpleBus 请求/响应状态机 | 是 |
| `npc/vsrc/soc/ysyx_25100265.sv` | 学号命名的正式 CPU 顶层，复位地址 `0x30000000` | 是，且是顶层 |
| `npc/vsrc/soc/NPC.sv` | 适配官方 ready-to-run 文件所要求的固定模块名 `NPC` | 否 |
| `npc/vsrc/top.sv` | NPC Verilator 测试顶层，含仿真 DPI | 否 |
| `npc/vsrc/simple_bus_pmem.sv` | NPC 主存/MMIO 行为模型，含 DPI-C | 否 |

**正式综合对象是 `ysyx_25100265`，不是 `top`、`NPC` 或 `SimTop`。**

### 4.2 SoC 仿真专用部分

| 路径 | 作用 | 是否综合进个人 NPC |
| --- | --- | :---: |
| `ysyxSoC/` | 官方 SoC、Flash/PSRAM/UART 和总线结构 | 否 |
| `npc/soc/vsrc/mygpio_top_apb.sv` | E7 GPIO 作业在当前仿真中的 overlay 实现 | 否 |
| `npc/soc/vsrc/uart_apb_monitor.sv` | 旁路观察 UART APB 写事务并打印字符 | 否 |
| `npc/soc/constr/SimTop.nxdc` | NVBoard 仿真引脚绑定 | 否 |
| `npc/soc/csrc/` | SoC/NVBoard C++ 仿真器 | 否 |

E8 当前流程只要求对个人 NPC 进行综合和后端物理设计。流片所用 SoC 由项目方提供，
所以不要把 ysyxSoC、GPIO、NVBoard 或 UART monitor 合入个人 NPC 网表。

### 4.3 AM 平台

| 文件 | 作用 |
| --- | --- |
| `abstract-machine/scripts/minirv-ysyxsoc.mk` | 组合 MiniRV ISA 和 ysyxSoC 平台，并把默认目标设为 `run` |
| `abstract-machine/scripts/platform/ysyxsoc.mk` | 链接到 PSRAM、插入 `mainargs`、生成 Flash 镜像并调用 SoC 仿真器 |
| `abstract-machine/am/src/riscv/ysyxsoc/trm.c` | UART 初始化、`putch()` 和 `halt()` |
| `abstract-machine/am/src/riscv/ysyxsoc/timer.c` | 读取 `mcycle/mcycleh` 并换算 AM uptime |
| `abstract-machine/am/src/riscv/ysyxsoc/ioe.c` | 注册 AM 设备访问处理函数 |

---

## 5. 一条指令是怎样执行的

### 5.1 普通计算指令

```text
FETCH_REQ：IFU 发出 reqValid 和 PC
    ↓
FETCH_RESP：等待 io_ifu_respValid
    ↓
译码 ADD/ADDI/LUI/JALR/CSR/EBREAK
    ↓
core_step=1
    ↓
时钟上升沿更新 PC、寄存器和提交计数
```

### 5.2 Load/Store

```text
取指响应到达
    ↓
译码产生地址、读写方向、数据和掩码
    ↓
LOAD_REQ/STORE_REQ 发出 LSU reqValid
    ↓
LOAD_RESP/STORE_RESP 等待 io_lsu_respValid
    ↓
core_step=1，完成写回或确认写事务结束
```

`reqValid` 表示“发起一次请求”，`respValid` 表示“请求已经完成”。等待响应期间
`core_step=0`，因此 PC 和寄存器不能提前改变。这就是 Flash、PSRAM 或 APB 外设出现多周期
延迟时，CPU 仍能保持正确的原因。

字节访问在 `minirv_simple_bus_master.sv` 中根据地址低两位调整 byte lane：

- `SB`：移动写数据和写掩码；
- `LBU`：把目标 byte lane 移回结果低 8 位；
- `LW/SW`：使用完整 32 位数据和 `4'b1111` 写掩码。

---

## 6. SoC 为什么从 Flash 启动

CPU 复位后从 `0x30000000` 取指，这是 ysyxSoC 的 SPI Flash XIP 窗口。完整启动过程是：

```text
CPU 复位
  ↓
从 0x30000000 执行官方 bootloader
  ↓
bootloader 在 Flash 固定位置找到嵌入的 ELF
  ↓
解析 ELF 的 PT_LOAD 段
  ↓
把代码和数据搬到 0x80000000 开始的 PSRAM
  ↓
跳转到 AM 程序入口
```

所以 `minirv-ysyxsoc` 比 `minirv-npc` 慢很多。大型 `am-tests` 会把音频、视频等数据也
链接进 ELF，即使 `mainargs` 只选择其中一个测试，Flash 镜像和搬运量也不会因此缩小。
长时间停留在启动阶段不一定表示 CPU 错误；应结合超时日志中的 PC、指令数和波形判断。

---

## 7. C++ 仿真器的最小理解

如果只学过 C，可以先采用下面的对应关系：

| C++ | 可以先近似理解成 C |
| --- | --- |
| `namespace npc::soc` | 给全局名称统一增加前缀 |
| `class Simulator` | 数据结构加一组操作它的函数 |
| 构造函数 | `simulator_init()` |
| 析构函数 | 自动调用的 `simulator_destroy()` |
| `std::unique_ptr<T>` | 具有唯一所有权且自动释放的指针 |
| `std::vector<uint8_t>` | 自动分配和释放的动态字节数组 |
| 引用 `T &` | 不能为空、使用时省略 `*` 的指针参数 |
| `try/catch` | 把深层错误统一交给入口处理 |

`npc/soc/csrc/` 的调用关系：

1. `options.cpp` 解析 `--image/--wave/--max-cycles/--gpio/--headless`；
2. `flash_image.cpp` 将 Flash 镜像读入动态数组；
3. `runtime.cpp` 实现 Flash、UART、提交和 trap 的 DPI 回调；
4. `simulator.cpp` 创建 `VSimTop`，驱动 CPU/SoC 双时钟、VCD 和 NVBoard；
5. `main.cpp` 只编排生命周期并决定最终退出码。

`Ctrl-C` 的 signal handler 只设置一个标志，不直接调用 SDL、iostream 或 Verilator。
主循环看到标志后正常离开作用域，`Simulator` 析构函数再关闭 VCD、NVBoard 并调用
Verilator 的 `final()`。这就是 C++ RAII 在本项目中的实际用途。

---

## 8. 当前版本的使用方法

先进入根目录并加载本仓库环境：

```bash
cd /home/onelastikun/to_test/ysyx-workbench
source .envrc
```

### 8.1 快速验证 CPU

```bash
make -C npc test-minirv
make -C npc test-diff
make -C npc test-delayed
make -C npc test-bus-error
make -C npc test-itrace
```

### 8.2 运行 NPC AM 程序

```bash
make -C am-kernels/tests/am-tests \
  ARCH=minirv-npc run ALL=dummy \
  NPC_RUN_FLAGS='MAX_CYCLES=100000000'
```

需要波形时显式加入 `WAVE`：

```bash
make -C am-kernels/tests/am-tests \
  ARCH=minirv-npc run ALL=dummy \
  NPC_RUN_FLAGS='MAX_CYCLES=100000000 WAVE=build/wave.vcd'
```

不传 `WAVE` 就不会打开 VCD 记录。建议只对短失败用例记录波形。

### 8.3 运行 ysyxSoC/NVBoard

在 AM 程序目录中，`minirv-ysyxsoc` 的默认目标就是 `run`：

```bash
make ARCH=minirv-ysyxsoc mainargs=h \
  YSYXSOC_RUN_FLAGS='MAX_CYCLES=0'
```

这会构建程序、生成 `.soc.bin`、启动统一的 SoC 仿真器并打开 NVBoard。

需要 SoC 波形：

```bash
make ARCH=minirv-ysyxsoc mainargs=h \
  YSYXSOC_RUN_FLAGS='MAX_CYCLES=0 WAVE=build/soc.vcd'
```

自动测试或无图形环境：

```bash
make ARCH=minirv-ysyxsoc mainargs=h \
  YSYXSOC_RUN_FLAGS='HEADLESS=1 MAX_CYCLES=500000000'
```

程序 good trap 后，图形模式会保留最后的 LED 和数码管状态。关闭 NVBoard 窗口或按
`Ctrl-C` 退出；`Ctrl-C` 返回码为 130。

当前工作区中的平台 Makefile 可能带有用户自定义的默认周期数或波形路径。为了让测试
可复现，建议像上面这样显式写出 `NPC_RUN_FLAGS` 或 `YSYXSOC_RUN_FLAGS`。

### 8.4 SoC 短回归

```bash
make -C npc/soc test-runtime
make -C npc/soc test-gpio
make -C npc/soc test-hello
make -C npc/soc test-sigint
```

这些是功能测试，不代表综合频率、面积、功耗或后端签核达标。

---

## 9. 当前代码距离 E8 还有多远

| E8 检查项 | 当前状态 | 还要做什么 |
| --- | --- | --- |
| 开放 NPC 地址空间 | 结构上已满足 | 正式顶层不做地址过滤，所有 IFU/LSU 请求都从 SimpleBus 发出；综合前再人工复核 |
| 去除下降沿触发 | 当前 CPU RTL 未发现 `negedge` | 合并最终改动后重新搜索和 lint |
| 去除锁存器 | 组合逻辑已有默认赋值 | 必须通过完整 lint 和综合网表确认没有 `LAT*` 单元 |
| 新版命名要求 | 顶层已为 `ysyx_25100265` | 当前新版方案不要求把所有文件合并或给内部模块统一加学号前缀 |
| `SYNTHESIS` 隔离 | 正式顶层 DPI 已隔离 | 综合日志中确认没有 DPI、系统任务或黑盒残留 |
| Verilator 静态检查 | 已通过 `make -C npc lint-synthesis` | 仅保留已确认无功能影响的 `DECLFILENAME` 抑制，其他 warning/error 仍需处理 |
| 复位和四值仿真 | 短 MiniRV RTL 测试已通过 | 需要时再用更长的 AM 程序观察 X 传播 |
| ECC 综合 | 已完成 | 复核报告、网表和综合 warning；源文件变更后需重新运行 |
| Verilator 网表仿真 | 短门级测试已通过 | 可按当期要求补充更长程序回归 |
| iverilog 网表仿真 | 短门级四值测试已通过 | 可按当期要求补充更长程序回归 |
| ECOS Studio 后端 | 未执行 | 从 Floorplan 开始完成布局布线并导出签核包 |

因此，现在可以说“E7 功能闭环已建立”，但还不能说“已经具备流片签核结果”。

---

## 10. 正式流片准备的执行顺序

以下步骤应由你在重新核对当期讲义后依次完成。不要跳过失败步骤继续向后。

### 10.1 固化一个可复现版本

1. 用 `git status` 检查工作区；
2. 确认学号、姓名、顶层名和当前分支正确；
3. 把确定要保留的修改按功能提交，不提交 build、VCD、PDK 或工具包；
4. 记录 Git commit、讲义日期、工具版本和测试命令；
5. 从干净构建目录重新跑 NPC 和 SoC 短回归。

建议至少保存：

```text
Git commit
Verilator 版本
RISC-V 工具链版本
ECC 版本
ICsprout55 PDK commit/版本
ECOS Studio 版本
所有回归命令和退出码
```

### 10.2 按 E8 完成前端检查

#### A. 地址空间

检查正式顶层以下逻辑，确保没有把“未知地址”直接吞掉或在 CPU 内部返回固定数据：

```text
ysyx_25100265
  └─ minirv_simple_bus_master
```

NPC 仿真中的 `simple_bus_pmem.sv` 可以做主存/MMIO范围检查，因为它是外部设备模型；
该检查不能被误移入正式 CPU 顶层。

#### B. 时钟和锁存器

- CPU 内部只使用 `posedge clock`；
- `always_comb` 或 `always @(*)` 给所有输出完整默认值；
- 一个寄存器只能由一个时序块驱动；
- 在综合网表中搜索 ICsprout55 的 `LAT*` 单元。

#### C. 静态检查

按 E8 对最终综合文件执行 Verilator `--lint-only -Wall`：

```bash
make -C npc \
  VERILATOR=/home/onelastikun/verilator/bin/verilator \
  lint-synthesis
```

该目标只检查个人 NPC 的综合 file list，不会把 SoC、NVBoard、主存模型或 C++ 仿真器
带入综合视角。当前内部模块名带学号而源文件保留功能命名，因此只抑制已确认无功能影响的
`DECLFILENAME` 提示；其他 warning 或 error 仍会使检查失败，不能用大量 `-Wno-*` 隐藏问题。

#### D. 复位和四值仿真

使用 iverilog 单独仿真 NPC，而不是整个 ysyxSoC。重点检查：

- 冷启动和再次拉高复位后的 PC；
- 总线状态机是否回到取指请求状态；
- 控制状态中的 X 是否会影响请求、写使能或下一 PC；
- 未复位的数据寄存器是否会通过控制路径传播；
- 短 MiniRV/AM 程序能否到达 good trap。

### 10.3 按 E6 使用 ECC 综合 NPC

截至本文更新日期，讲义使用：

- ECC `v0.1.0-alpha.10`；
- ICsprout55 PDK；
- oss-cad-suite 中的 Yosys 和相关插件；
- ECC flow preset：`syn_sta`。

实际执行前再次以官网版本为准。

#### 正式综合文件列表

```text
npc/vsrc/minirv_regfile.sv
npc/vsrc/minirv_decode.sv
npc/vsrc/minirv_core.sv
npc/vsrc/soc/minirv_simple_bus_master.sv
npc/vsrc/soc/ysyx_25100265.sv
```

ECC 关键配置概念：

```text
design.name      = 自己的工程名
design.top       = ysyx_25100265
design.rtl       = 上述五个 RTL 文件
design.clock_port= clock
flow.preset      = syn_sta
pdk.root         = ICsprout55 PDK 的绝对路径
```

目标频率先采用讲义示例或当期要求，不要一开始盲目设置得很高。综合成功后至少检查：

```text
<project>/runs/default/Synthesis_yosys/report/post_synthesis/qor_summary.rpt
<project>/runs/default/Synthesis_yosys/report/post_synthesis/power.rpt
<project>/runs/default/Synthesis_yosys/log/Synthesis.log
<project>/runs/default/Synthesis_yosys/output/<project>_Synthesis.v.gz
<project>/runs/default/Synthesis_yosys/output/<project>_Synthesis_sim.v.gz
```

其中：

- `qor_summary.rpt`：频率和面积摘要；
- `power.rpt`：功耗估计；
- `Synthesis.log`：综合过程、warning 和所用策略；
- `_Synthesis_sim.v.gz`：保留原顶层向量端口，用于网表仿真；
- `_Synthesis.v.gz`：向量端口被拆成单 bit，供后端物理设计使用。

本仓库当前一次实际综合结果（2026 年 9 月 10 日）为：

```text
顶层：ysyx_25100265
综合检查：0 problems
综合网表：ecc/npc/runs/default/Synthesis_yosys/output/npc_Synthesis.v.gz
仿真网表：ecc/npc/runs/default/Synthesis_yosys/output/npc_Synthesis_sim.v.gz
综合估算频率：158 MHz
综合面积 CELLA：9185
总动态功耗估计：0.2598 mW
```

这里的 158 MHz 是综合阶段估算值，不是完成布局布线后的最终芯片频率。ECC 的网表和
报告位于本地 `ecc/npc/runs/`，默认不纳入 Git；如果修改正式 RTL，必须重新运行 ECC，
不能继续使用旧网表。

讲义提供 `AREA`、`DELAY` 和 `BALANCE` 三类 Yosys 综合策略。先让默认策略正确完成，
再通过 `YOSYS_SYNTH_STRATEGY` 比较结果；每次比较都必须记录频率、面积、功耗和功能回归，
不能只选择某个看起来最大的频率。

#### 综合后必须回答的问题

- 顶层是否真的是 `ysyx_25100265`？
- 是否只有一个时钟端口 `clock`？
- 是否有未解析模块、黑盒或未映射单元？
- 是否意外包含 DPI、`$display`、主存模型、SoC 或 NVBoard？
- 是否出现 `LAT*` 锁存器？
- 关键寄存器、SimpleBus 端口和复位逻辑是否仍存在？
- 面积和频率是否合理，是否有明显的约束错误？

### 10.4 按 E8 做网表仿真

网表仿真不能继续直接使用综合前 RTL。基本结构应变为：

```text
测试顶层/存储器模型
      ↕
ysyx_25100265 的 _Synthesis_sim 网表
      +
ICsprout55 标准单元行为级仿真模型
```

建议先做最短测试，再逐步增加：

1. 复位后第一次取指；
2. MiniRV 定向测试；
3. 一个短 AM 程序；
4. 必要时再尝试更长程序。

按照讲义分别完成：

- Verilator 二值网表功能仿真；
- iverilog 四值网表仿真。

网表中没有原来的 DPI 和容易读取的完整寄存器数组，DiffTest 调试能力会明显下降。因此
一定先把 RTL 仿真、DiffTest 和四值 RTL 仿真做扎实，再进入网表仿真。

当前仓库已经提供短门级回归：

```bash
make -C npc \
  VERILATOR=/home/onelastikun/verilator/bin/verilator \
  IVERILOG=/home/onelastikun/to_test/oss-cad-suite/bin/iverilog \
  VVP=/home/onelastikun/to_test/oss-cad-suite/bin/vvp \
  IVERILOG_VPI=/home/onelastikun/to_test/oss-cad-suite/bin/iverilog-vpi \
  test-netlist
```

该目标使用 `ecc/npc/runs/default/` 中的 ECC 输出，执行 Verilator 二值门级仿真和
Icarus 四值门级仿真。若 ECC 尚未运行，会明确报出缺少 `npc_Synthesis_sim.v.gz`。

### 10.5 按 E8 使用 ECOS Studio 做后端物理设计

截至本文更新日期，E8 指向 ECOS Studio `v0.1.0-alpha.9`。实际下载时仍应重新核对当期讲义。

创建 Backend Design 工作空间时：

1. 建立 Project 和 Workspace；
2. `START STEP` 选择 **Floorplan**，跳过 Synthesis；
3. 导入 ECC 输出中**不含 `_sim`** 的 `<project>_Synthesis.v.gz`；
4. 选择正确的 ICsprout55 PDK；
5. `Top Module Name` 填 `ysyx_25100265`；
6. `Clock Signal Name` 填 `clock`；
7. 设置或确认目标频率和 Core Utilization；
8. 运行完整后端 flow。

为什么从 Floorplan 开始：ECC 已经在前一步完成综合，ECOS Studio 这里只消费门级网表。

完成后重点查看：

- `Die Area`：最终版图面积；
- `Frequency`：包含布线影响及更悲观工作条件后的频率；
- Checklist/Sign-off details：STA、DRC、LVS 等是否达标；
- Risk Details：除无宏单元导致的 `config.macro_locations` 提示外，不应忽略其他风险。

当前环境检查：截至 2026 年 9 月 11 日，本机未发现 ECOS Studio 可执行文件或 AppImage。
`~/.local/ecos-sdk` 是嵌入式软件 SDK，提供的是 `ecos` 固件命令行工具，不是 E8 所需的
后端 Studio，不能替代 ECOS Studio。因此本仓库只能完成 ECC、综合网表仿真和文档准备，
不能伪造后端结果；安装官方工具后，应从下面的 Floorplan 步骤继续。

如果无法导出签核包：

- STA 不达标：先检查约束，再尝试降低目标频率；
- DRC/LVS 不达标：查看具体检查项，讲义建议可尝试降低利用率；
- 修改参数后创建或更新 Workspace，重新运行，不能手工删掉失败报告。

全部达到要求后，从 ECOS Studio 导出 **Signoff Package**。导出成功才表示该次工作空间
满足工具的签核包门禁，并不等同于项目方已经接收你的流片申请。

### 10.6 按当期流程参与流片

完成签核包后还应：

1. 回到 E9 和当期通知确认必做题、答辩和提交入口；
2. 核对提交的是个人 NPC 的签核包，而不是整个 ysyxSoC 仿真工程；
3. 保存 Git commit、ECC 工程、综合网表、ECOS Workspace、签核包和报告；
4. 记录顶层名、时钟名、目标频率、面积、工具和 PDK 版本；
5. 检查归档中没有个人密钥、无关第三方仓库或巨大调试波形；
6. 按项目方要求参加代码审查、答辩和最终提交流程。

E8 页面目前仍标有“待续未完”，所以真正报名时必须再看官网和群内最新通知。

---

## 11. 推荐的个人验收清单

### 功能冻结

- [ ] 8 条 MiniRV 指令定向测试通过；
- [ ] DiffTest 通过；
- [ ] 延迟 SimpleBus 测试通过；
- [ ] 非法地址测试通过；
- [ ] AM CPU tests 中正常测试通过；
- [ ] SoC Flash→PSRAM→AM 启动通过；
- [ ] UART、CSR/uptime、GPIO 和 Ctrl-C 短回归通过；
- [ ] 所有结果对应同一个明确 Git commit。

### E8 前端准备

- [x] 正式顶层开放所有 IFU/LSU 地址；
- [x] CPU 中没有下降沿触发；
- [x] Verilator `--lint-only -Wall` 已逐项处理；
- [x] 短 MiniRV RTL 四值仿真和复位通过；
- [x] 仿真专用代码均被排除或由 `SYNTHESIS` 隔离。

### 综合和网表

- [x] ECC 使用讲义当前版本和 ICsprout55 PDK；
- [x] 综合 file list 只包含个人 NPC；
- [x] 日志没有未解析模块、黑盒和意外锁存器；
- [x] QoR、功耗、日志和两种网表已生成；
- [x] Verilator 短网表仿真通过；
- [x] iverilog 短网表四值仿真通过。

### 后端和报名

- [ ] ECOS Studio 从 Floorplan 开始；
- [ ] 导入的是不含 `_sim` 的后端网表；
- [ ] Top/Clock 名称正确；
- [ ] STA、DRC、LVS 和风险检查满足当期要求；
- [ ] Signoff Package 成功导出并可追溯；
- [ ] 已重新阅读 E9 和当期通知；
- [ ] 答辩与流片申请材料已提交。

---

## 12. 本次修订相对旧文档的重要更正

1. 明确综合入口在 E6，而不是等到 E8 才开始；
2. 综合工具写为讲义当前使用的 ECC/Yosys/ICsprout55，不再写成未说明的
   `yosys-sta` 流程；
3. 明确只综合个人 NPC，排除 ysyxSoC、GPIO、NVBoard、存储器模型和 C++；
4. 删除把 DFT/ATPG 当作当前 E8 必做内容的描述，因为当前 E8 没有给出这项验收任务；
5. 明确 `_Synthesis_sim.v.gz` 用于网表仿真，`_Synthesis.v.gz` 用于后端；
6. 明确新版集成方案原则上不要求合并单文件或给所有内部模块添加学号前缀；
7. 补充当前实际 RTL/C++/AM 文件关系、运行命令和逐阶段验收清单。
