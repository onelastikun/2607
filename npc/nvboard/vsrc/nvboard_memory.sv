// Small byte-addressed FPGA memory used only by the NVBoard demonstration.
module nvboard_memory #(
  parameter int SIZE = 64 * 1024
) (
  input  logic        clock,
  input  logic [31:0] imem_addr,
  output logic [31:0] imem_rdata,
  input  logic        dmem_read,
  input  logic [31:0] dmem_addr,
  output logic [31:0] dmem_rdata,
  input  logic        dmem_write,
  input  logic [31:0] dmem_wdata,
  input  logic [3:0]  dmem_wmask
);

  localparam logic [31:0] BASE = 32'h8000_0000;
  logic [7:0] memory [0:SIZE-1];
  logic [31:0] imem_offset;
  logic [31:0] dmem_offset;
  integer i;

  assign imem_offset = imem_addr - BASE;
  assign dmem_offset = dmem_addr - BASE;
  assign imem_rdata = {memory[imem_offset + 3], memory[imem_offset + 2],
                       memory[imem_offset + 1], memory[imem_offset]};
  assign dmem_rdata = dmem_read
                    ? {memory[dmem_offset + 3], memory[dmem_offset + 2],
                       memory[dmem_offset + 1], memory[dmem_offset]}
                    : 32'd0;

  initial begin
    for (i = 0; i < SIZE; i = i + 1) memory[i] = 8'd0;
    // addi x1,x0,0; addi x1,x1,1; jal x0,-4
    {memory[3], memory[2], memory[1], memory[0]} = 32'h0000_0093;
    {memory[7], memory[6], memory[5], memory[4]} = 32'h0010_8093;
    {memory[11], memory[10], memory[9], memory[8]} = 32'hffdff06f;
  end

  always_ff @(posedge clock) begin
    if (dmem_write) begin
      if (dmem_wmask[0]) memory[dmem_offset] <= dmem_wdata[7:0];
      if (dmem_wmask[1]) memory[dmem_offset + 1] <= dmem_wdata[15:8];
      if (dmem_wmask[2]) memory[dmem_offset + 2] <= dmem_wdata[23:16];
      if (dmem_wmask[3]) memory[dmem_offset + 3] <= dmem_wdata[31:24];
    end
  end

endmodule
