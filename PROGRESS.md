# E 阶段进度记录

更新日期：2026-09-02

## 当前阶段

E3：数字电路仿真闭环已通过，准备进入 E4 最小 CPU 闭环。

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

## 下一步

在 E3 闭环通过后，实现 MiniRV CPU 的 PC、取指、`addi`、寄存器堆与 `ebreak` 最小闭环。
