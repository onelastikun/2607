// MiniRV core state and commit boundary. Memory timing is provided externally.
module minirv_core (
  input  logic         clock,
  input  logic         reset,
  input  logic         step,
  output logic [31:0]  imem_addr,
  input  logic [31:0]  imem_rdata,
  output logic         dmem_read,
  output logic [2:0]   dmem_len,
  output logic [31:0]  dmem_addr,
  input  logic [31:0]  dmem_rdata,
  output logic         dmem_write,
  output logic [31:0]  dmem_wdata,
  output logic [3:0]   dmem_wmask,
  output logic         is_ebreak,
  output logic         illegal,
  output logic [31:0]  trap_code,
  output logic [63:0]  instruction_count,
  output logic [31:0]  pc,
  output logic [31:0]  inst,
  output logic         commit_valid,
  output logic [31:0]  commit_pc,
  output logic [31:0]  commit_inst,
  output logic [511:0] gpr_state
);

  localparam logic [31:0] RESET_VECTOR = 32'h8000_0000;

  logic [31:0] pc_reg;
  logic [31:0] next_pc;
  logic [31:0] rs1_value;
  logic [31:0] rs2_value;
  logic [31:0] rd_value;
  logic        rd_write;
  logic        regfile_write;
  logic [3:0]  rs1_idx;
  logic [3:0]  rs2_idx;
  logic [3:0]  rd_idx;

  assign pc = pc_reg;
  assign inst = imem_rdata;
  assign imem_addr = pc_reg;
  assign rs1_idx = inst[18:15];
  assign rs2_idx = inst[23:20];
  assign rd_idx = inst[10:7];
  assign regfile_write = rd_write && step;

  minirv_regfile u_regfile (
    .clock(clock),
    .reset(reset),
    .rs1_idx(rs1_idx),
    .rs2_idx(rs2_idx),
    .rd_idx(rd_idx),
    .rd_write(regfile_write),
    .rd_value(rd_value),
    .rs1_value(rs1_value),
    .rs2_value(rs2_value),
    .a0_value(trap_code),
    .gpr_state(gpr_state)
  );

  minirv_decode u_decode (
    .pc(pc_reg),
    .inst(inst),
    .rs1_value(rs1_value),
    .rs2_value(rs2_value),
    .dmem_rdata(dmem_rdata),
    .next_pc(next_pc),
    .rd_write(rd_write),
    .rd_value(rd_value),
    .dmem_read(dmem_read),
    .dmem_len(dmem_len),
    .dmem_addr(dmem_addr),
    .dmem_write(dmem_write),
    .dmem_wdata(dmem_wdata),
    .dmem_wmask(dmem_wmask),
    .is_ebreak(is_ebreak),
    .illegal(illegal)
  );

  always_ff @(posedge clock) begin
    if (reset) begin
      pc_reg <= RESET_VECTOR;
      instruction_count <= 64'd0;
      commit_valid <= 1'b0;
      commit_pc <= 32'd0;
      commit_inst <= 32'd0;
    end else begin
      commit_valid <= 1'b0;
      if (step) begin
        pc_reg <= next_pc;
        instruction_count <= instruction_count + 64'd1;
        commit_valid <= 1'b1;
        commit_pc <= pc_reg;
        commit_inst <= inst;
      end
    end
  end

endmodule
