# E8 后端流程复核记录

更新日期：2026-09-13

## 1. 首次失败原因

2026 年 9 月 11 日第一次运行 ECOS Studio Floorplan 时，工具报告：

```text
Cell area must be greater than 0!
```

当时工作空间中的数据库统计为：

```text
instance_num = 0
cell_area    = 0
```

根因是导入了旧综合网表。该网表的顶层是 `minirv_core`，而 ECOS Studio 配置的顶层是
`ysyx_25100265`，顶层设置和网表不匹配，导致工具没有读到有效的标准单元实例。

## 2. 正确输入

之后重新导入当前 ECC 生成的综合网表：

```text
/home/onelastikun/to_test/ysyx-workbench/ecc/npc/runs/default/Synthesis_yosys/output/npc_Synthesis.v.gz
```

并确认：

```text
Top Module : ysyx_25100265
Clock      : clock
PDK        : ics55 / ICsprout55
```

当前仓库综合网表的 SHA-256：

```text
0982bc6bb2bb339c8db623c4e4decf4a60f357c26d237ff6170bdde82d45055c
```

可用以下命令检查顶层：

```bash
gzip -cd ecc/npc/runs/default/Synthesis_yosys/output/npc_Synthesis.v.gz \\
  | grep '^module ' | head -1
```

## 3. ECOS Studio 实际结果

工作空间位置：

```text
/home/onelastikun/to_test/project/npc_2607/ysyx_ws
```

完整 flow 已成功完成：

```text
Floorplan       Success
fixFanout       Success
place           Success
CTS             Success
legalization    Success
route           Success
drc             Success
lvs             Success
filler          Success
RCX             Success
sta             Success
Harden          Success
```

ECOS Studio 总检查结果：

```text
passed     = 31
blocked    = 0
attention  = 0
unavailable= 0
```

### 版图和规模

```text
Die：179 um × 179 um
Die Area：32041 um²
Core：175 um × 175 um
利用率：0.3
Instance：12391
IO Pin：173
Net：3785
```

### DRC/LVS

```text
DRC violations：0
LVS violations：0
LVS：173 个 IO、4508 个实例、3785 条网络，网表与 DEF 差异均为 0
```

### RCX/STA

```text
RCX：9 个配置角、9 个 SPEF，均成功解析
STA：13 个配置角，均有报告
Setup WNS：1.107 ns
Setup TNS：0 ns
Setup violation：0
Hold WNS：0.088 ns
Hold TNS：0 ns
Hold violation：0
最差报告频率：53 MHz（MAX_125/RCworst）
```

### Harden 输出

```text
/home/onelastikun/to_test/project/npc_2607/ysyx_ws/Harden_ecc/output/npc_2607_Harden.gds
/home/onelastikun/to_test/project/npc_2607/ysyx_ws/Harden_ecc/output/npc_2607_Harden.lef
/home/onelastikun/to_test/project/npc_2607/ysyx_ws/Harden_ecc/output/npc_2607_Harden.lib
```

## 4. 当前结论和待办

当前 E8 后端 flow 已实际跑通，且 Floorplan、布局布线、DRC、LVS、RCX、STA 和 Harden
均有成功结果。以上结果是 ECOS Studio 工作空间的结果，不是单纯的综合估算。

当前未在工作空间中发现导出的 `Signoff Package` 压缩包。导出签核包仍需在 ECOS Studio
中执行 `File -> Export Signoff Package`，并保存工作空间、签核包和报告。

还需要注意：

- `50 MHz` 是本次 ECOS Studio 工作空间的目标频率设置；
- `53 MHz` 是该工作空间 STA 报告中的最差结果；
- 之前 ECC 综合报告中的 `158 MHz` 是综合阶段估算值，不能代替后端 STA；
- 当前没有真实 FPGA 板上验证结果；
- 运行路径在仓库外，不能把外部工作空间误当作 Git 已提交内容。
