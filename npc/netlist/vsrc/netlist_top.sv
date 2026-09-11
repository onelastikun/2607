// E8 门级仿真顶层：用 ECC 的 ysyx_25100265 网表替换 RTL CPU，
// 外部仍使用独立存储器模型，因此不会把主存误算入个人 NPC。
module netlist_top (
  input  logic clock,
  input  logic reset,
  output logic test_passed,
  output logic test_failed
);
  logic [31:0] ifu_addr;
  logic        ifu_reqValid;
  logic [31:0] ifu_rdata;
  logic        ifu_respValid;
  logic [31:0] lsu_addr;
  logic        lsu_reqValid;
  logic [31:0] lsu_rdata;
  logic        lsu_respValid;
  logic [1:0]  lsu_size;
  logic        lsu_wen;
  logic [31:0] lsu_wdata;
  logic [3:0]  lsu_wmask;

  ysyx_25100265 u_cpu (
    .clock(clock), .reset(reset),
    .io_ifu_addr(ifu_addr), .io_ifu_reqValid(ifu_reqValid),
    .io_ifu_rdata(ifu_rdata), .io_ifu_respValid(ifu_respValid),
    .io_lsu_addr(lsu_addr), .io_lsu_reqValid(lsu_reqValid),
    .io_lsu_rdata(lsu_rdata), .io_lsu_respValid(lsu_respValid),
    .io_lsu_size(lsu_size), .io_lsu_wen(lsu_wen),
    .io_lsu_wdata(lsu_wdata), .io_lsu_wmask(lsu_wmask)
  );

  netlist_bus_pmem u_memory (
    .clock(clock), .reset(reset),
    .ifu_reqValid(ifu_reqValid), .ifu_addr(ifu_addr),
    .ifu_respValid(ifu_respValid), .ifu_rdata(ifu_rdata),
    .lsu_reqValid(lsu_reqValid), .lsu_addr(lsu_addr),
    .lsu_size(lsu_size), .lsu_wen(lsu_wen),
    .lsu_wdata(lsu_wdata), .lsu_wmask(lsu_wmask),
    .lsu_respValid(lsu_respValid), .lsu_rdata(lsu_rdata),
    .test_passed(test_passed), .test_failed(test_failed)
  );

`ifdef __ICARUS__
  initial begin
    wait (test_passed || test_failed);
    if (test_passed)
      $display("NETLIST GOOD TRAP");
    else
      $display("NETLIST BAD TRAP");
    $finish;
  end
`endif
endmodule
