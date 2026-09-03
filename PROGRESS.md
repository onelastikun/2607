# E 阶段进度记录

更新日期：2026-09-03

## 当前阶段

E7 已完成到“接入 SoC”标题之前：NPC 通过 4x4 AXI 互联访问主存和 MMIO，RV32I/RV32E 官方测试、AM 回归、MicroBench 和 NVBoard 软件接入均已验证。尚未初始化或接入 `ysyxSoC`。

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

## NVBoard 接入

已完成：

- 新增独立 NVBoard 平台目录，复用同一 MiniRV 核心，不复制 CPU 实现；
- NVBoard 顶层、板级字节存储器、十六进制七段数码管译码器按功能拆分；
- CPU 核心在板级环境中不依赖 DPI-C；
- 支持 PC、指令、提交状态、周期数、访存状态和任意 RV32E 寄存器观察；
- 支持拨码开关到 LED 的直接回显检查；
- 非法指令和 `ebreak` 有明确 LED 状态；
- 添加约束文件、自动引脚绑定、独立 Makefile 和使用说明。

验证结果：

- NVBoard、SDL2、SDL2_image、SDL2_ttf 和 Verilator 全量构建：通过；
- Verilator `-Wall` 与 C++ `-Wall/-Wextra`：无警告；
- `SDL_VIDEODRIVER=dummy make smoke` 运行 100 周期并正常退出；
- 尚未声明物理 FPGA 板上验证。

## E7 AXI4-Lite 总线基线

已完成：

- MiniRV 核心新增 `step` 提交使能，等待总线期间 PC、寄存器和提交状态保持不变；
- 新增独立 AXI4-Lite 主设备状态机，串行处理取指、load 和 store；
- 五个通道分别遵守 valid/ready 握手，地址、写数据和写响应可独立等待；
- 新增带可配置读写延迟的 AXI4-Lite 物理内存/MMIO 从设备；
- 串口和计时器访问已通过总线事务到达 C++ 设备模块，CPU 核心不直接调用 DPI-C；
- C++ DiffTest 改为仅在 `commit_valid` 时推进参考模型；
- AM 默认周期上限调整为总线多周期执行所需范围。

验证结果：

- 114 条定向指令逐条 DiffTest：通过，630 总线周期完成；
- AM CPU tests 35 项：全部通过；
- AM hello 串口：通过；
- AM timer smoke：通过；
- MicroBench test：10 项全部通过，65899655 总线周期完成；
- NVBoard 复用核心重新构建并完成 100 周期 smoke：通过；
- AXI4-Lite 基线相对直连 MicroBench 的 8368310 周期约慢 7.87 倍，作为后续优化基线。

## E7 总线性能优化

已完成：

- 取指响应周期直接向译码器提供指令，非访存指令在响应握手周期提交；
- load 在读数据握手周期直接写回，去除独立 COMMIT 空闲状态；
- store 在写响应握手周期直接提交；
- 在握手正确性已经由延迟从设备验证后，将 NPC 实例的额外人工读写延迟设为 0；
- 保持 valid 在 ready 前稳定、AW/W 独立完成和单 outstanding 约束不变。

验证结果：

- 114 条定向 DiffTest：从 630 周期降至 378 周期；
- MicroBench test：从 65899655 周期降至 39453684 周期，减少约 40.13%；
- 优化后相对原直连基线为约 4.71 倍周期，符合当前串行总线/非流水核心结构预期；
- AM CPU tests 35 项：全部通过；
- MicroBench 10 项：全部通过。

## E7 多主多从 AXI 互联

已完成：

- 新增支持最多 4 个主设备和 4 个从设备的 AXI 互联模块；
- 转发 AR/AW 的 ID、LEN、SIZE、BURST 字段和 WLAST/RLAST；
- 将 2 位主设备编号附加到下游 ID，高位 ID 用于无全局顺序表的响应路由；
- 按地址高位将主存、MMIO、扩展窗口和默认窗口译码到 4 个目标；
- 每个目标对读地址和写地址分别进行固定优先级仲裁；
- AW 握手后记录写目标，确保无 ID 的 W 通道只能前往对应从设备；
- R/B 响应恢复原始主设备 ID，并仅向被选中的响应通道传播 ready；
- 当前明确裁剪为单拍事务，接口保留 AXI4 burst 字段供接入 SoC 前继续扩展。

验证结果：

- 独立 crossbar 测试通过；
- 覆盖 4 路地址译码、两个主设备竞争同一目标、读 ID 扩展/恢复、写地址先于写数据和 B 响应路由；
- Verilator `-Wall` 与 C++ `-Wall/-Wextra`：无警告。

## E7 系统互联实际接入

已完成：

- 新增 Lite 主设备到单拍 AXI4 的元数据适配器，生成固定 ID、LEN=0、SIZE=4B、INCR burst 和 WLAST；
- 新增 AXI4 到 Lite 从设备适配器，保存 ARID/AWID 并恢复 RID/BID；
- NPC CPU 接入 4x4 互联的主设备槽 0，其余 3 个槽保持可扩展且被运行时检查为静默；
- 主存窗口 `0x8...` 路由到从设备 0，MMIO 窗口 `0xa...` 路由到从设备 1；
- 扩展窗口和默认窗口接入错误从设备，返回 SLVERR/DECERR 而不是误访问宿主内存；
- 总线元数据、非活动主设备响应和从设备协议裁剪错误统一汇总到 NPC abort；
- 新增非法总线窗口定向测试，并区分总线响应错误与非法指令错误。

验证结果：

- 114 条定向 DiffTest：通过，381 周期完成；
- 独立 4x4 crossbar 测试：通过；
- AM CPU tests 35 项：全部通过；
- hello 串口与 timer smoke：通过，证明主存和 MMIO 分目标路由有效；
- MicroBench 10 项：全部通过，41482917 周期完成；
- 完整互联相对优化后的单从设备路径增加约 5.14% 周期，相对直连基线约 4.96 倍；
- 访问 `0xc0000000` 的 bus-error 测试正确返回失败并报告总线响应错误；
- Verilator 与 C++ 严格警告构建：通过。

## 官方 RV32I 测试

已完成：

- 使用本机官方 fork 的 `riscv-tests` 源码，按 `ARCH=riscv32e-npc` 编译并执行原始 RV32E 指令；
- 通过官方 `TEST_ISA=i` 测试集合运行 38 项 RV32I 整数测试；
- 排除 `fence_i` 和 `ma_data`：前者当前设计未实现 I-cache fence 语义，后者依赖非对齐/异常环境，不纳入当前 MiniRV 裁剪集合；
- 所有 38 项均通过，包括算术、逻辑、移位、比较、分支、跳转、加载和存储。

验证命令：

```bash
make -C riscv-tests clean
make -C riscv-tests ARCH=riscv32e-npc TEST_ISA=i EXCLUDE_TEST='fence_i ma_data' run
```

结果：`test list [38 item(s)]`，全部 `PASS`。

DiffTest 验证命令：

```bash
make -C riscv-tests clean
make -C riscv-tests ARCH=riscv32e-npc TEST_ISA=i \
  EXCLUDE_TEST='fence_i ma_data' \
  NPC_DIFF="$PWD/nemu/build/riscv32-nemu-interpreter-so" run
```

结果：38 项全部 `PASS`，未发现 DUT/参考模型状态不一致。

环境情况：

- `riscv-tests` 已通过 GitHub codeload 归档获取到当前工作区，但作为外部测试依赖不纳入根仓库提交。

## 官方 RV32E 架构测试

已完成：

- 按 `init.sh` 指定来源初始化 `NJU-ProjectN/riscv-arch-test-am` main 分支，当前外部仓库提交为 `7553ed696e6b`；
- 使用完整的官方 RV32E E 扩展 37 项架构测试，而不是此前网络中断后形成的不完整文件集合；
- 使用 `ARCH=riscv32e-npc` 编译原始 RV32E 指令；`ARCH=minirv-npc` 会经过 MiniRV 工具链的指令替换层，不能用于验证被替换掉的目标指令；
- 37 项测试在 NPC 上全部 good trap；
- 37 项测试启用 NEMU 逐指令 DiffTest 后再次全部通过；
- `riscv-arch-test/` 作为外部测试依赖由根仓库忽略，不提交其源码、Git 元数据或构建产物。

验证命令：

```bash
make -C riscv-arch-test clean
make -C riscv-arch-test ARCH=riscv32e-npc TEST_ISA=E run

make -C riscv-arch-test clean
make -C riscv-arch-test ARCH=riscv32e-npc TEST_ISA=E \
  NPC_DIFF="$PWD/nemu/build/riscv32-nemu-interpreter-so" run
```

结果：`test list [37 item(s)]`，两次运行均全部 `PASS`。

## 总线错误诊断修正

已完成：

- 在 AXI 响应握手当周期组合呈现错误状态，避免粘滞错误到下一条指令才被报告；
- DPI-C 错误信息分别标出 Lite 响应、主设备协议和系统互联三个来源；
- `test-bus-error` 同时检查非零退出状态、故障 PC 和错误来源；
- 非法窗口 load 现在准确报告发起访问的 `0x80000004`，而不是后继指令 `0x80000008`。

验证结果：

- `make -C npc clean && make -C npc test-diff`：通过；
- `make -C npc test-bus-error`：通过，报告 `pc=0x80000004 cause=0x1`；
- `make -C npc/tests/axi-crossbar clean && make -C npc/tests/axi-crossbar run`：通过。

## 指令轨迹与统计

已完成：

- `itrace` 同时打印提交 PC、机器码、RV32E 助记符和操作数；
- 仿真器保留最近 16 条提交记录，DiffTest 首个 PC/GPR 不一致时自动输出最近轨迹；
- 将原先语义不准确的 `cycle_count` 更名为 `instruction_count`；
- 退出信息明确区分总线仿真周期和客户程序已提交指令数；
- NVBoard 诊断显示对应更新为“已提交指令数”。

验证结果：

- `make -C npc test-itrace`：通过，自动检查首条 `addi` 和最终 `ebreak` 的反汇编；
- `make -C npc test-diff`：通过，114 条指令在 381 个总线周期内完成；
- `make -C npc test-delayed`：通过，在读延迟 2 周期、写延迟 3 周期时以 636 个总线周期完成同一组 114 条 DiffTest，证明 CPU 会等待握手和响应；
- `make -C npc test-bus-error`：通过，错误退出同时报告周期数和已提交指令数；
- NPC 与 NVBoard 均在 Verilator/C++ 严格警告选项下干净构建。

## 最终全量回归（2026-09-03）

- NPC 定向 DiffTest：114 条全部通过；
- 总线错误定向测试：通过，故障 PC 和来源准确；
- AXI4 4x4 互联独立测试：通过；
- AM CPU tests：35 项全部通过；
- AM `hello`：通过，串口输出正确；
- AM timer smoke：通过，64 位 uptime 单调且超过 1 ms；
- MicroBench test：10 项全部通过，最近一次为 41531071 个总线周期、8412756 条提交指令；
- `riscv-tests`：38 项使用 `ARCH=riscv32e-npc` 和 NEMU DiffTest 全部通过；
- `riscv-arch-test`：37 项使用 `ARCH=riscv32e-npc` 和 NEMU DiffTest 全部通过；
- NVBoard：干净构建和 `SDL_VIDEODRIVER=dummy` 的 100 周期 smoke 通过；
- `git diff --check`：通过；
- `ysyxSoC/`：不存在，未开始 SoC 接入。

## 边界与限制

- 当前 CPU/总线按本阶段要求裁剪为 RV32E、32 位数据宽度、单拍事务和受控单 outstanding；不支持 AXI burst；
- 单核无 I-cache，`fence` 作为空操作；`fence.i` 未实现并从 `riscv-tests` 中明确排除；
- `ma_data` 依赖异常环境，不属于当前 MiniRV 裁剪范围；
- NVBoard 仅完成软件构建与无窗口 smoke，尚无物理 FPGA 板上验证结论；
- 根 Makefile 的 `STUID/STUNAME` 仍为示例值，因此没有执行会产生错误身份 tracer 提交的 `make sim`；讲义要求的 tracer 调用行保持原样；
- 未初始化 `ysyxSoC`，未开展 Flash/SPI/PSRAM/UART 16550、综合、STA、PDK 或物理设计工作。

## 下一步

在 E7“接入 SoC”前停止，等待用户审查和确认后续范围。
