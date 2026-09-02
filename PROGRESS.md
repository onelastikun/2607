# E 阶段进度记录

更新日期：2026-09-02

## 当前阶段

E4：MiniRV/RV32E 定向自检已通过，NEMU RV32E 参考模型接口已构建，正在接入 NPC DiffTest。

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

## 下一步

在 NPC 中动态加载 NEMU 共享库，按每条提交指令比较 PC 和 16 个通用寄存器。
