# E 阶段进度记录

更新日期：2026-09-02

## 当前阶段

E4：最小 CPU 执行闭环已通过，准备扩展完整 MiniRV/RV32E 指令。

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

## 下一步

扩展算术、逻辑、移位、分支、跳转、加载和存储指令，并增加定向指令自检。
