// E8 四值仿真的最小顶层。
// Icarus 通过 VPI 加载 +img=FILE 指定的裸镜像，并由 top.sv 中的 ebreak 逻辑结束仿真。
`ifdef __ICARUS__
module iverilog_top;
  logic clock;
  logic reset;

  logic [63:0] instruction_count;
  logic [31:0] pc;
  logic [31:0] inst;
  logic        commit_valid;
  logic [31:0] commit_pc;
  logic [31:0] commit_inst;
  logic [511:0] gpr_state;

  top u_top (
    .clock(clock),
    .reset(reset),
    .instruction_count(instruction_count),
    .pc(pc),
    .inst(inst),
    .commit_valid(commit_valid),
    .commit_pc(commit_pc),
    .commit_inst(commit_inst),
    .gpr_state(gpr_state)
  );

  initial begin
    clock = 1'b0;
    reset = 1'b1;
    if ($test$plusargs("WAVE")) begin
      $dumpfile("build/iverilog.vcd");
      $dumpvars(0, iverilog_top);
    end
    #10 reset = 1'b0;
  end

  always #1 clock = ~clock;
endmodule
`endif
