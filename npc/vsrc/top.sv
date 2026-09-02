// NPC simulation top using an AXI4-Lite master and delayed memory/MMIO slave.
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

  import "DPI-C" function void npc_ebreak(
    input int unsigned trap_pc,
    input int unsigned code
  );
  import "DPI-C" function void npc_abort(
    input int unsigned abort_pc,
    input int unsigned abort_inst
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
  logic        bus_error;

  logic        arvalid;
  logic        arready;
  logic [31:0] araddr;
  logic        rvalid;
  logic        rready;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        awvalid;
  logic        awready;
  logic [31:0] awaddr;
  logic        wvalid;
  logic        wready;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        bvalid;
  logic        bready;
  logic [1:0]  bresp;

  minirv_core u_core (
    .clock(clock), .reset(reset), .step(core_step),
    .imem_addr(core_imem_addr), .imem_rdata(fetched_inst),
    .dmem_read(dmem_read), .dmem_len(dmem_len), .dmem_addr(dmem_addr),
    .dmem_rdata(dmem_rdata), .dmem_write(dmem_write),
    .dmem_wdata(dmem_wdata), .dmem_wmask(dmem_wmask),
    .is_ebreak(is_ebreak), .illegal(illegal), .trap_code(trap_code),
    .cycle_count(cycle_count), .pc(pc), .inst(inst),
    .commit_valid(commit_valid), .commit_pc(commit_pc),
    .commit_inst(commit_inst), .gpr_state(gpr_state)
  );

  minirv_axi_lite_master u_master (
    .clock(clock), .reset(reset), .core_pc(core_imem_addr),
    .core_inst(fetched_inst),
    .core_dmem_read(dmem_read), .core_dmem_len(dmem_len),
    .core_dmem_addr(dmem_addr), .core_dmem_rdata(dmem_rdata),
    .core_dmem_write(dmem_write), .core_dmem_wdata(dmem_wdata),
    .core_dmem_wmask(dmem_wmask), .core_step(core_step),
    .arvalid(arvalid), .arready(arready), .araddr(araddr),
    .rvalid(rvalid), .rready(rready), .rdata(rdata), .rresp(rresp),
    .awvalid(awvalid), .awready(awready), .awaddr(awaddr),
    .wvalid(wvalid), .wready(wready), .wdata(wdata), .wstrb(wstrb),
    .bvalid(bvalid), .bready(bready), .bresp(bresp),
    .bus_error(bus_error)
  );

  axi_lite_pmem #(.READ_DELAY(1), .WRITE_DELAY(1)) u_pmem (
    .clock(clock), .reset(reset),
    .arvalid(arvalid), .arready(arready), .araddr(araddr),
    .rvalid(rvalid), .rready(rready), .rdata(rdata), .rresp(rresp),
    .awvalid(awvalid), .awready(awready), .awaddr(awaddr),
    .wvalid(wvalid), .wready(wready), .wdata(wdata), .wstrb(wstrb),
    .bvalid(bvalid), .bready(bready), .bresp(bresp)
  );

  always_ff @(posedge clock) begin
    if (!reset && core_step) begin
      if (illegal || bus_error) npc_abort(pc, inst);
      if (is_ebreak) npc_ebreak(pc, trap_code);
    end
  end

endmodule
