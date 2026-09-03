// NPC simulation top using an AXI4-Lite master and delayed memory/MMIO slave.
module top (
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
  logic        bus_error;
  logic        lite_bus_error;
  logic        master_protocol_error;
  logic        fabric_error;

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

  logic        axi_arvalid;
  logic        axi_arready;
  logic [31:0] axi_araddr;
  logic [3:0]  axi_arid;
  logic [7:0]  axi_arlen;
  logic [2:0]  axi_arsize;
  logic [1:0]  axi_arburst;
  logic        axi_rvalid;
  logic        axi_rready;
  logic [31:0] axi_rdata;
  logic [1:0]  axi_rresp;
  logic [3:0]  axi_rid;
  logic        axi_rlast;
  logic        axi_awvalid;
  logic        axi_awready;
  logic [31:0] axi_awaddr;
  logic [3:0]  axi_awid;
  logic [7:0]  axi_awlen;
  logic [2:0]  axi_awsize;
  logic [1:0]  axi_awburst;
  logic        axi_wvalid;
  logic        axi_wready;
  logic [31:0] axi_wdata;
  logic [3:0]  axi_wstrb;
  logic        axi_wlast;
  logic        axi_bvalid;
  logic        axi_bready;
  logic [1:0]  axi_bresp;
  logic [3:0]  axi_bid;

  assign bus_error = lite_bus_error || master_protocol_error || fabric_error;

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
    .bus_error(lite_bus_error)
  );

  axi_lite_master_to_axi4 u_master_adapter (
    .lite_arvalid(arvalid), .lite_arready(arready), .lite_araddr(araddr),
    .lite_rvalid(rvalid), .lite_rready(rready), .lite_rdata(rdata),
    .lite_rresp(rresp), .lite_awvalid(awvalid), .lite_awready(awready),
    .lite_awaddr(awaddr), .lite_wvalid(wvalid), .lite_wready(wready),
    .lite_wdata(wdata), .lite_wstrb(wstrb), .lite_bvalid(bvalid),
    .lite_bready(bready), .lite_bresp(bresp),
    .axi_arvalid(axi_arvalid), .axi_arready(axi_arready),
    .axi_araddr(axi_araddr), .axi_arid(axi_arid), .axi_arlen(axi_arlen),
    .axi_arsize(axi_arsize), .axi_arburst(axi_arburst),
    .axi_rvalid(axi_rvalid), .axi_rready(axi_rready), .axi_rdata(axi_rdata),
    .axi_rresp(axi_rresp), .axi_rid(axi_rid), .axi_rlast(axi_rlast),
    .axi_awvalid(axi_awvalid), .axi_awready(axi_awready),
    .axi_awaddr(axi_awaddr), .axi_awid(axi_awid), .axi_awlen(axi_awlen),
    .axi_awsize(axi_awsize), .axi_awburst(axi_awburst),
    .axi_wvalid(axi_wvalid), .axi_wready(axi_wready), .axi_wdata(axi_wdata),
    .axi_wstrb(axi_wstrb), .axi_wlast(axi_wlast), .axi_bvalid(axi_bvalid),
    .axi_bready(axi_bready), .axi_bresp(axi_bresp), .axi_bid(axi_bid),
    .protocol_error(master_protocol_error)
  );

  axi4_system_interconnect u_system_interconnect (
    .clock(clock), .reset(reset),
    .arvalid(axi_arvalid), .arready(axi_arready), .araddr(axi_araddr),
    .arid(axi_arid), .arlen(axi_arlen), .arsize(axi_arsize),
    .arburst(axi_arburst), .rvalid(axi_rvalid), .rready(axi_rready),
    .rdata(axi_rdata), .rresp(axi_rresp), .rid(axi_rid), .rlast(axi_rlast),
    .awvalid(axi_awvalid), .awready(axi_awready), .awaddr(axi_awaddr),
    .awid(axi_awid), .awlen(axi_awlen), .awsize(axi_awsize),
    .awburst(axi_awburst), .wvalid(axi_wvalid), .wready(axi_wready),
    .wdata(axi_wdata), .wstrb(axi_wstrb), .wlast(axi_wlast),
    .bvalid(axi_bvalid), .bready(axi_bready), .bresp(axi_bresp),
    .bid(axi_bid), .bus_error(fabric_error)
  );

  always_ff @(posedge clock) begin
    if (!reset && core_step) begin
      if (bus_error) npc_bus_error(pc,
          {29'd0, fabric_error, master_protocol_error, lite_bus_error});
      else if (illegal) npc_abort(pc, inst);
      if (is_ebreak && !bus_error) npc_ebreak(pc, trap_code);
    end
  end

endmodule
