# E 阶段进度记录

更新日期：2026-09-02

## 当前阶段

E6：AM uptime 和 MicroBench test 已通过；准备进行 NVBoard 与外部标准测试。

## 已完成

- 建立 NPC 的 Verilator 自动构建流程；
- 建立 C++ 仿真主循环；
- 实现时钟、同步复位和周期推进；
- 支持通过 `--wave` 按需生成 VCD 波形；
- 添加复位和周期计数的自检；
- 保留讲义要求的 `make sim` tracer 调用；
- 禁用只读宿主缓存目录中的 ccache，避免沙箱内构建失败。

## 验证结果

- `make -C npc run CYCLES=17`：通过；
- `make -C npc run CYCLES=5 WAVE=build/e3-smoke.vcd`：通过，成功生成非空 VCD；
- `npc/build/obj_dir/Vtop --cycles 0`：通过；
- Verilator 版本：5.048；
- GCC/G++ 版本：15.2.0；
- `make sim` 暂未执行：根 Makefile 中学号和姓名仍为示例值，避免生成错误身份的 tracer 提交。

## E4 最小 CPU 闭环

已完成：

- PC 复位到 `0x80000000`；
- 通过 DPI-C 从 128 MiB 物理内存取指；
- 支持命令行加载二进制镜像；
- 实现 16 个 RV32E 通用寄存器，并保持 `x0=0`；
- 实现 `addi`、`add` 和 `ebreak`；
- 区分 good trap、bad trap、非法指令和超时；
- 输出原始指令轨迹；
- 对外导出提交 PC、提交指令和寄存器状态；
- 默认内置最小自检程序。

验证结果：

- 内置 `addi/add/ebreak` 程序：4 周期 good trap，`x2=3`；
- 开启 itrace 和 VCD：通过；
- 非零 `a0` 的 `ebreak`：正确报告 bad trap 并返回失败；
- `0xffffffff`：正确报告非法指令并返回失败。

## E4 RV32E 指令扩展

已完成：

- U/J/B/I/S/R 六类立即数和数据通路；
- `lui`、`auipc`、`jal`、`jalr`；
- 六种条件分支；
- `lb/lh/lw/lbu/lhu`；
- `sb/sh/sw`；
- RV32I 基础整数立即数和寄存器 ALU 指令；
- `fence` 单核空操作语义；
- RV32E 高寄存器编号合法性检查；
- 完整地址、按字节小端内存读写和写掩码；
- 只读一次的 load 数据路径，避免 MMIO 重复副作用；
- 可自动编译运行的 RV32E 汇编定向测试。

验证结果：

- `make -C npc clean && make -C npc test-rv32e`：通过；
- 定向测试覆盖算术、逻辑、移位、比较、全部分支、跳转、带符号/无符号加载、三种存储、`x0` 和 `fence`；
- 定向程序 114 条指令后 good trap；
- Verilator `-Wall` 构建无警告。

## NEMU 参考模型基线

已完成：

- 新增 `riscv32e-ref_defconfig`，构建 16 寄存器 RV32E 共享参考模型；
- 实现 NEMU 的 DiffTest 内存复制、寄存器复制、参考执行和异常注入接口；
- 实现 RISC-V 寄存器/PC 比较；
- 成功生成 `nemu/build/riscv32-nemu-interpreter-so`。

环境情况：

- 官方测试和 AM/NVBoard 仓库的 GitHub 下载已重试两次；当前网络分别出现 TLS 中断和 443 连接超时；
- 该网络问题不阻止继续使用本地 NEMU 接入 DiffTest；后续在需要官方测试时再次重试。

## NEMU ISA 与 NPC DiffTest

已完成：

- 在 NEMU 中实现与 MiniRV 对应的 RV32E 基础整数指令；
- NPC 支持通过 `--diff REF_SO` 动态加载参考模型；
- 初始化时同步程序镜像、PC 和寄存器；
- 每条 DUT 提交后驱动 NEMU 执行一条指令；
- 比较下一 PC 和 16 个通用寄存器；
- 不一致时报告提交 PC、寄存器名、参考值和 DUT 值；
- Makefile 新增 `test-diff` 自动回归目标。

验证结果：

- `make -C npc clean && make -C npc test-diff`：通过；
- DUT 与 NEMU 对 114 条 RV32E 定向测试逐条一致；
- DUT 和 NEMU 均在 `0x800001e0` 报告 good trap；
- Verilator `-Wall` 构建无警告。

## 模块化与 KISS 重构

根据开发约束完成职责拆分：

- RTL：`top` 仅保留 DPI 平台适配，核心状态、组合译码/执行和寄存器堆分别位于独立模块；
- CPU 核心改用明确的指令/数据存储器端口，不再直接依赖 DPI-C，为后续总线替换保留简单边界；
- C++：命令行、物理内存、DPI 运行时、仿真驱动、DiffTest 和主流程分别维护；
- `main.cpp` 只负责对象生命周期、执行循环和退出状态；
- 各模块添加职责和关键边界注释，避免无意义逐行注释和过度抽象；
- `AGENTS.md` 已加入模块化、必要注释和 KISS 原则。

回归结果：

- 干净构建及 114 条指令 DiffTest：通过；
- 内置程序、itrace 和 VCD：通过；
- bad trap 与非法指令错误路径：通过；
- Verilator 和 C++ `-Wall/-Wextra`：无警告。

## AM、TRM 与 CPU 测试

已完成：

- 从本机已有官方 Git 对象创建干净的 `am-kernels` ics2026 和 `nvboard` master 工作副本，未复制原工作区中的未提交实现；
- AM `minirv-npc` 的 `run` 目标接入 NPC 镜像参数；
- TRM `putch()` 通过 `0xa00003f8` 串口 MMIO 输出；
- TRM `halt()` 通过 `a0 + ebreak` 传递退出码；
- C++ 侧新增独立 `DeviceMap` 模块，当前提供串口和 64 位微秒计时器 MMIO；
- 完成 KLIB 字符串、内存和基础格式化输出函数；
- `.envrc` 统一禁用不可写宿主缓存目录中的 ccache。

验证结果：

- `dummy`：通过；
- `hello`：正确输出正文和 `mainargs=KISS-NPC` 后 good trap；
- AM CPU tests 除故意返回失败的 `wrong` 外共 35 项全部通过；
- 覆盖长整数、除法、排序、字符串、格式化、非对齐访问和复杂 C 程序。

## AM 时钟与 MicroBench

已完成：

- AM `AM_TIMER_UPTIME` 读取 `0xa0000048` 起始的 64 位微秒计数；
- 使用“高-低-高”读取顺序避免 32 位 CPU 观察到撕裂的 64 位计数；
- `AM_TIMER_CONFIG.has_rtc=false`，不虚报未实现的墙上时钟能力；
- 新增有限运行的 `am-timer-smoke`，验证计数单调且至少推进 1000 微秒；
- 完成 MicroBench `test` 数据集回归。

验证结果：

- `am-timer-smoke`：29026 周期后 good trap；
- AM 自带 RTC 测试为无限循环，曾连续观察到 uptime 从 1 秒递增到 54 秒，随后由测试上限主动终止；
- MicroBench 10 个项目全部通过，8368310 周期后 good trap；
- MicroBench 输出 `PASS`，测得总运行时间约 444.823 ms（宿主机环境数据，仅作本次验证记录）。

## 下一步

完成 NVBoard 接入；继续获取并运行 `riscv-tests`/`riscv-arch-test` 官方测试。
