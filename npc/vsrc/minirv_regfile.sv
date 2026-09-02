// RV32E register file: 16 architectural registers with x0 hard-wired to zero.
module minirv_regfile (
  input  logic         clock,
  input  logic         reset,
  input  logic [3:0]   rs1_idx,
  input  logic [3:0]   rs2_idx,
  input  logic [3:0]   rd_idx,
  input  logic         rd_write,
  input  logic [31:0]  rd_value,
  output logic [31:0]  rs1_value,
  output logic [31:0]  rs2_value,
  output logic [31:0]  a0_value,
  output logic [511:0] gpr_state
);

  logic [31:0] gpr [0:15];
  integer i;

  assign rs1_value = gpr[rs1_idx];
  assign rs2_value = gpr[rs2_idx];
  assign a0_value = gpr[10];

  genvar gi;
  generate
    for (gi = 0; gi < 16; gi = gi + 1) begin : gen_gpr_state
      assign gpr_state[gi * 32 +: 32] = gpr[gi];
    end
  endgenerate

  always_ff @(posedge clock) begin
    if (reset) begin
      for (i = 0; i < 16; i = i + 1) begin
        gpr[i] <= 32'd0;
      end
    end else begin
      if (rd_write && (rd_idx != 4'd0)) begin
        gpr[rd_idx] <= rd_value;
      end
      gpr[0] <= 32'd0;
    end
  end

endmodule
