// 学号 25100265 对应的 ysyxSoC SimpleBus CPU 顶层。
// 对外端口遵循 E 阶段 CPU 接口规范，内部复用已经通过 DiffTest 的 MiniRV 核心。
module ysyx_25100265 #(
  parameter logic [31:0] MARCHID = 32'd25100265
) (
  input  logic        clock,
  input  logic        reset,
  output logic [31:0] io_ifu_addr,
  output logic        io_ifu_reqValid,
  input  logic [31:0] io_ifu_rdata,
  input  logic        io_ifu_respValid,
  output logic [31:0] io_lsu_addr,
  output logic        io_lsu_reqValid,
  input  logic [31:0] io_lsu_rdata,
  input  logic        io_lsu_respValid,
  output logic [1:0]  io_lsu_size,
  output logic        io_lsu_wen,
  output logic [31:0] io_lsu_wdata,
  output logic [3:0]  io_lsu_wmask
);

`ifndef SYNTHESIS
`ifndef __ICARUS__
  // DPI 只服务于 Verilator 调试；综合/流片定义 SYNTHESIS 后不会进入硬件网表。
  import "DPI-C" function void npc_ebreak(
    input int unsigned trap_pc,
    input int unsigned code
  );
  import "DPI-C" function void npc_abort(
    input int unsigned abort_pc,
    input int unsigned abort_inst
  );
  import "DPI-C" function void npc_commit(
    input int unsigned commit_pc,
    input int unsigned commit_inst
  );
`endif
`endif

  logic        core_step;
  logic [31:0] core_imem_addr;
  logic [31:0] core_inst;
  logic        dmem_read;
  logic [2:0]  dmem_len;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_rdata;
  logic        dmem_write;
  logic [31:0] dmem_wdata;
  logic [3:0]  dmem_wmask;
  logic        is_ebreak;
  logic        illegal;
  logic [31:0] trap_code;
  logic [63:0] instruction_count;
  logic [31:0] pc;
  logic [31:0] inst;
  logic        commit_valid;
  logic [31:0] commit_pc;
  logic [31:0] commit_inst;
  logic [511:0] gpr_state;

  // SoC 从 0x30000000 的 SPI XIP 窗口启动，bootloader 再把程序搬到 PSRAM。
  minirv_core #(
    .RESET_VECTOR(32'h3000_0000), .MARCHID(MARCHID)
  ) u_core (
    .clock(clock), .reset(reset), .step(core_step),
    .imem_addr(core_imem_addr), .imem_rdata(core_inst),
    .dmem_read(dmem_read), .dmem_len(dmem_len), .dmem_addr(dmem_addr),
    .dmem_rdata(dmem_rdata), .dmem_write(dmem_write),
    .dmem_wdata(dmem_wdata), .dmem_wmask(dmem_wmask),
    .is_ebreak(is_ebreak), .illegal(illegal), .trap_code(trap_code),
    .instruction_count(instruction_count), .pc(pc), .inst(inst),
    .commit_valid(commit_valid), .commit_pc(commit_pc),
    .commit_inst(commit_inst), .gpr_state(gpr_state)
  );

  minirv_simple_bus_master u_bus (
    .clock(clock), .reset(reset), .core_pc(core_imem_addr), .core_inst(core_inst),
    .core_dmem_read(dmem_read), .core_dmem_len(dmem_len),
    .core_dmem_addr(dmem_addr), .core_dmem_rdata(dmem_rdata),
    .core_dmem_write(dmem_write), .core_dmem_wdata(dmem_wdata),
    .core_dmem_wmask(dmem_wmask), .core_step(core_step),
    .io_ifu_reqValid(io_ifu_reqValid), .io_ifu_addr(io_ifu_addr),
    .io_ifu_respValid(io_ifu_respValid), .io_ifu_rdata(io_ifu_rdata),
    .io_lsu_reqValid(io_lsu_reqValid), .io_lsu_addr(io_lsu_addr),
    .io_lsu_size(io_lsu_size), .io_lsu_wen(io_lsu_wen),
    .io_lsu_wdata(io_lsu_wdata), .io_lsu_wmask(io_lsu_wmask),
    .io_lsu_respValid(io_lsu_respValid), .io_lsu_rdata(io_lsu_rdata)
  );

  // unused 调试信号保留在核心边界，便于将来接入 SoC 级 itrace。
  /* verilator lint_off UNUSEDSIGNAL */
  // 综合模式不会保留仿真 trap 回调，因此这些调试状态需要显式标记为已检查；
  // 该归约信号本身会被综合优化掉，不改变 CPU 的功能逻辑。
  wire _unused_debug = &{1'b0, instruction_count, commit_valid, commit_pc,
                          commit_inst, gpr_state, is_ebreak, illegal, trap_code,
                          pc, inst};
  /* verilator lint_on UNUSEDSIGNAL */

`ifndef SYNTHESIS
`ifndef __ICARUS__
  // 提交、异常和 ebreak 通知属于仿真可观测性，不改变 CPU 架构状态。
  always_ff @(posedge clock) begin
    if (!reset && core_step) begin
      npc_commit(pc, inst);
      if (illegal) npc_abort(pc, inst);
      else if (is_ebreak) npc_ebreak(pc, trap_code);
    end
  end
`endif
`endif

endmodule
