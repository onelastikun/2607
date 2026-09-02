// Simulation top: keeps DPI-C and host-specific behavior outside the CPU core.
module top (
  input  logic         clock,
  input  logic         reset,
  output logic [63:0]  cycle_count,
  output logic [31:0]  pc,
  output logic [31:0]  inst,
  output logic         commit_valid,
  output logic [31:0]  commit_pc,
  output logic [31:0]  commit_inst,
  output logic [511:0] gpr_state
);

  import "DPI-C" function int unsigned pmem_read(
    input int unsigned addr,
    input byte unsigned len
  );
  import "DPI-C" function void pmem_write(
    input int unsigned addr,
    input int unsigned data,
    input byte unsigned mask
  );
  import "DPI-C" function void npc_ebreak(
    input int unsigned trap_pc,
    input int unsigned code
  );
  import "DPI-C" function void npc_abort(
    input int unsigned abort_pc,
    input int unsigned abort_inst
  );

  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
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

  // The DPI adapter is intentionally thin so it can later be replaced by a bus.
  assign imem_rdata = pmem_read(imem_addr, 8'd4);
  assign dmem_rdata = dmem_read
                    ? pmem_read(dmem_addr, {5'd0, dmem_len})
                    : 32'd0;

  minirv_core u_core (
    .clock(clock),
    .reset(reset),
    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),
    .dmem_read(dmem_read),
    .dmem_len(dmem_len),
    .dmem_addr(dmem_addr),
    .dmem_rdata(dmem_rdata),
    .dmem_write(dmem_write),
    .dmem_wdata(dmem_wdata),
    .dmem_wmask(dmem_wmask),
    .is_ebreak(is_ebreak),
    .illegal(illegal),
    .trap_code(trap_code),
    .cycle_count(cycle_count),
    .pc(pc),
    .inst(inst),
    .commit_valid(commit_valid),
    .commit_pc(commit_pc),
    .commit_inst(commit_inst),
    .gpr_state(gpr_state)
  );

  always_ff @(posedge clock) begin
    if (!reset) begin
      if (dmem_write) pmem_write(dmem_addr, dmem_wdata, {4'd0, dmem_wmask});
      if (illegal) npc_abort(pc, inst);
      if (is_ebreak) npc_ebreak(pc, trap_code);
    end
  end

endmodule
