// ready-to-run/minirv 生成文件固定实例化名为 NPC，使用薄封装连接正式学号顶层。
module NPC (
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

  ysyx_25100265 u_cpu (.*);

endmodule
