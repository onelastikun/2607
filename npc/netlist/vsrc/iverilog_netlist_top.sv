`ifdef __ICARUS__
// Icarus 门级四值仿真的时钟和复位驱动。
module iverilog_netlist_top;
  logic clock;
  logic reset;
  logic test_passed;
  logic test_failed;

  netlist_top u_top (
    .clock(clock), .reset(reset),
    .test_passed(test_passed), .test_failed(test_failed)
  );

  initial begin
    clock = 1'b0;
    reset = 1'b1;
    if ($test$plusargs("WAVE")) begin
      $dumpfile("build/netlist/iverilog-netlist.vcd");
      $dumpvars(0, iverilog_netlist_top);
    end
    #10 reset = 1'b0;
    #20000 begin
      $display("NETLIST TIMEOUT");
      $fatal(1);
    end
  end

  always #1 clock = ~clock;
endmodule
`endif
