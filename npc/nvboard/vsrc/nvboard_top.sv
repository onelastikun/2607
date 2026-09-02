// NVBoard wrapper. SW0 selects PC (0) or x1 (1) for LEDs and displays.
module nvboard_top (
  input  logic        clock,
  input  logic        reset,
  input  logic [15:0] sw,
  output logic [15:0] led,
  output logic [7:0]  seg0,
  output logic [7:0]  seg1,
  output logic [7:0]  seg2,
  output logic [7:0]  seg3,
  output logic [7:0]  seg4,
  output logic [7:0]  seg5,
  output logic [7:0]  seg6,
  output logic [7:0]  seg7
);

  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
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
  logic [63:0] cycle_count;
  logic [31:0] pc;
  logic [31:0] inst;
  logic        commit_valid;
  logic [31:0] commit_pc;
  logic [31:0] commit_inst;
  logic [511:0] gpr_state;
  logic [31:0] display_value;

  minirv_core u_core (
    .clock(clock), .reset(reset), .step(1'b1),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_read(dmem_read), .dmem_len(dmem_len), .dmem_addr(dmem_addr),
    .dmem_rdata(dmem_rdata), .dmem_write(dmem_write),
    .dmem_wdata(dmem_wdata), .dmem_wmask(dmem_wmask),
    .is_ebreak(is_ebreak), .illegal(illegal), .trap_code(trap_code),
    .cycle_count(cycle_count), .pc(pc), .inst(inst),
    .commit_valid(commit_valid), .commit_pc(commit_pc),
    .commit_inst(commit_inst), .gpr_state(gpr_state)
  );

  nvboard_memory u_memory (
    .clock(clock), .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_read(dmem_read), .dmem_addr(dmem_addr), .dmem_rdata(dmem_rdata),
    .dmem_write(dmem_write), .dmem_wdata(dmem_wdata),
    .dmem_wmask(dmem_wmask)
  );

  always_comb begin
    if (sw[15]) begin
      // Register inspection mode: SW3..SW0 select one of the 16 RV32E GPRs.
      display_value = gpr_state[sw[3:0] * 32 +: 32];
    end else begin
      // Diagnostic mode: SW6..SW4 select a core or memory observation point.
      case (sw[6:4])
        3'd0: display_value = pc;
        3'd1: display_value = inst;
        3'd2: display_value = commit_pc;
        3'd3: display_value = commit_inst;
        3'd4: display_value = sw[7] ? cycle_count[63:32] : cycle_count[31:0];
        3'd5: display_value = trap_code;
        3'd6: display_value = dmem_addr;
        default: display_value = {23'd0, commit_valid, dmem_read, dmem_write,
                                  dmem_len, 3'd0};
      endcase
    end
  end

  // SW14 provides a direct switch/LED board sanity check.
  assign led = sw[14] ? sw
             : illegal ? 16'hdead
             : is_ebreak ? 16'hbeef
             : display_value[15:0];

  hex7seg u_seg0(.value(display_value[3:0]),   .segments(seg0));
  hex7seg u_seg1(.value(display_value[7:4]),   .segments(seg1));
  hex7seg u_seg2(.value(display_value[11:8]),  .segments(seg2));
  hex7seg u_seg3(.value(display_value[15:12]), .segments(seg3));
  hex7seg u_seg4(.value(display_value[19:16]), .segments(seg4));
  hex7seg u_seg5(.value(display_value[23:20]), .segments(seg5));
  hex7seg u_seg6(.value(display_value[27:24]), .segments(seg6));
  hex7seg u_seg7(.value(display_value[31:28]), .segments(seg7));

endmodule
