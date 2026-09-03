// NVBoard 演示专用的小型字节寻址存储器，不参与 NPC 的 AXI 仿真。
// 指令口组合读取，数据口支持组合读和带字节掩码的时序写。
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

  // 对外仍使用完整物理地址，内部通过减去 BASE 得到数组下标。
  localparam logic [31:0] BASE = 32'h8000_0000;
  logic [7:0] memory [0:SIZE-1];
  logic [31:0] imem_offset;
  logic [31:0] dmem_offset;
  integer i;

  assign imem_offset = imem_addr - BASE;
  assign dmem_offset = dmem_addr - BASE;
  // 四个连续字节按 RISC-V 小端序拼成 32 位指令或数据。
  assign imem_rdata = {memory[imem_offset + 3], memory[imem_offset + 2],
                       memory[imem_offset + 1], memory[imem_offset]};
  assign dmem_rdata = dmem_read
                    ? {memory[dmem_offset + 3], memory[dmem_offset + 2],
                       memory[dmem_offset + 1], memory[dmem_offset]}
                    : 32'd0;

  // 内置程序不断执行 x1=x1+1，便于从 LED/数码管观察核心持续运行。
  initial begin
    for (i = 0; i < SIZE; i = i + 1) memory[i] = 8'd0;
    // 依次为：x1=0；x1=x1+1；跳回上一条指令。
    {memory[3], memory[2], memory[1], memory[0]} = 32'h0000_0093;
    {memory[7], memory[6], memory[5], memory[4]} = 32'h0010_8093;
    {memory[11], memory[10], memory[9], memory[8]} = 32'hffdff06f;
  end

  // 写掩码每一位控制一个字节，行为与 NPC 主存总线一致。
  always_ff @(posedge clock) begin
    if (dmem_write) begin
      if (dmem_wmask[0]) memory[dmem_offset] <= dmem_wdata[7:0];
      if (dmem_wmask[1]) memory[dmem_offset + 1] <= dmem_wdata[15:8];
      if (dmem_wmask[2]) memory[dmem_offset + 2] <= dmem_wdata[23:16];
      if (dmem_wmask[3]) memory[dmem_offset + 3] <= dmem_wdata[31:24];
    end
  end

endmodule
