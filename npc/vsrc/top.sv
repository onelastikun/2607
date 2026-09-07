// NPC 仿真顶层：MiniRV 核心通过讲义规定的 SimpleBus 访问主存和 MMIO。
// 顶层只负责模块连接和仿真事件上报，不在 CPU 核心中直接调用 DPI-C。
module top #(
  parameter int BUS_READ_DELAY = 0,
  parameter int BUS_WRITE_DELAY = 0
) (
  input  logic         clock,
  input  logic         reset,
  output logic [63:0]  instruction_count,
  output logic [31:0]  pc,
  output logic [31:0]  inst,
  output logic         commit_valid,
  output logic [31:0]  commit_pc,
  output logic [31:0]  commit_inst,
  output logic [511:0] gpr_state
);

  import "DPI-C" function void npc_ebreak(
    input int unsigned trap_pc,
    input int unsigned code
  );
  import "DPI-C" function void npc_abort(
    input int unsigned abort_pc,
    input int unsigned abort_inst
  );
  import "DPI-C" function void npc_bus_error(
    input int unsigned fault_pc,
    input int unsigned cause
  );

  logic        core_step;
  logic [31:0] core_imem_addr;
  logic [31:0] fetched_inst;
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

  logic        ifu_req_valid;
  logic [31:0] ifu_addr;
  logic        ifu_resp_valid;
  logic [31:0] ifu_rdata;
  logic        lsu_req_valid;
  logic [31:0] lsu_addr;
  logic [1:0]  lsu_size;
  logic        lsu_wen;
  logic [31:0] lsu_wdata;
  logic [3:0]  lsu_wmask;
  logic        lsu_resp_valid;
  logic [31:0] lsu_rdata;
  logic        bus_error;

  minirv_core u_core (
    .clock(clock), .reset(reset), .step(core_step),
    .imem_addr(core_imem_addr), .imem_rdata(fetched_inst),
    .dmem_read(dmem_read), .dmem_len(dmem_len), .dmem_addr(dmem_addr),
    .dmem_rdata(dmem_rdata), .dmem_write(dmem_write),
    .dmem_wdata(dmem_wdata), .dmem_wmask(dmem_wmask),
    .is_ebreak(is_ebreak), .illegal(illegal), .trap_code(trap_code),
    .instruction_count(instruction_count), .pc(pc), .inst(inst),
    .commit_valid(commit_valid), .commit_pc(commit_pc),
    .commit_inst(commit_inst), .gpr_state(gpr_state)
  );

  // NPC 与 ysyxSoC 复用同一个 SimpleBus 主设备，避免维护两套 CPU 总线逻辑。
  minirv_simple_bus_master u_master (
    .clock(clock), .reset(reset), .core_pc(core_imem_addr),
    .core_inst(fetched_inst),
    .core_dmem_read(dmem_read), .core_dmem_len(dmem_len),
    .core_dmem_addr(dmem_addr), .core_dmem_rdata(dmem_rdata),
    .core_dmem_write(dmem_write), .core_dmem_wdata(dmem_wdata),
    .core_dmem_wmask(dmem_wmask), .core_step(core_step),
    .io_ifu_reqValid(ifu_req_valid), .io_ifu_addr(ifu_addr),
    .io_ifu_respValid(ifu_resp_valid), .io_ifu_rdata(ifu_rdata),
    .io_lsu_reqValid(lsu_req_valid), .io_lsu_addr(lsu_addr),
    .io_lsu_size(lsu_size), .io_lsu_wen(lsu_wen),
    .io_lsu_wdata(lsu_wdata), .io_lsu_wmask(lsu_wmask),
    .io_lsu_respValid(lsu_resp_valid), .io_lsu_rdata(lsu_rdata)
  );

  simple_bus_pmem #(
    .READ_DELAY(BUS_READ_DELAY), .WRITE_DELAY(BUS_WRITE_DELAY)
  ) u_bus_target (
    .clock(clock), .reset(reset),
    .ifu_reqValid(ifu_req_valid), .ifu_addr(ifu_addr),
    .ifu_respValid(ifu_resp_valid), .ifu_rdata(ifu_rdata),
    .lsu_reqValid(lsu_req_valid), .lsu_addr(lsu_addr),
    .lsu_size(lsu_size), .lsu_wen(lsu_wen),
    .lsu_wdata(lsu_wdata), .lsu_wmask(lsu_wmask),
    .lsu_respValid(lsu_resp_valid), .lsu_rdata(lsu_rdata),
    .bus_error(bus_error)
  );

  // 总线错误优先于非法指令和 ebreak，避免把失败访问误报为正常结束。
  always_ff @(posedge clock) begin
    if (!reset && core_step) begin
      if (bus_error) npc_bus_error(pc, 32'd1);
      else if (illegal) npc_abort(pc, inst);
      else if (is_ebreak) npc_ebreak(pc, trap_code);
    end
  end

endmodule
