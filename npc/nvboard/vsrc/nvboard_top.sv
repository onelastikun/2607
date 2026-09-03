// MiniRV 的 NVBoard 平台顶层：连接核心、演示存储器、开关、LED 和数码管。
// 板级演示直接让核心每拍 step，不包含仿真环境中的 AXI 总线和 DPI-C。
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
  logic [63:0] instruction_count;
  logic [31:0] pc;
  logic [31:0] inst;
  logic        commit_valid;
  logic [31:0] commit_pc;
  logic [31:0] commit_inst;
  logic [511:0] gpr_state;
  logic [31:0] display_value;

  // 板级核心复用 NPC 已验证的数据通路和寄存器堆。
  minirv_core u_core (
    .clock(clock), .reset(reset), .step(1'b1),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_read(dmem_read), .dmem_len(dmem_len), .dmem_addr(dmem_addr),
    .dmem_rdata(dmem_rdata), .dmem_write(dmem_write),
    .dmem_wdata(dmem_wdata), .dmem_wmask(dmem_wmask),
    .is_ebreak(is_ebreak), .illegal(illegal), .trap_code(trap_code),
    .instruction_count(instruction_count), .pc(pc), .inst(inst),
    .commit_valid(commit_valid), .commit_pc(commit_pc),
    .commit_inst(commit_inst), .gpr_state(gpr_state)
  );

  // 演示存储器内置递增程序，无需从宿主机加载镜像。
  nvboard_memory u_memory (
    .clock(clock), .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_read(dmem_read), .dmem_addr(dmem_addr), .dmem_rdata(dmem_rdata),
    .dmem_write(dmem_write), .dmem_wdata(dmem_wdata),
    .dmem_wmask(dmem_wmask)
  );

  always_comb begin
    if (sw[15]) begin
      // 寄存器观察模式：SW3..SW0 选择 x0~x15。
      display_value = gpr_state[sw[3:0] * 32 +: 32];
    end else begin
      // 诊断模式：SW6..SW4 选择 PC、指令、提交信息或访存信息。
      case (sw[6:4])
        3'd0: display_value = pc;
        3'd1: display_value = inst;
        3'd2: display_value = commit_pc;
        3'd3: display_value = commit_inst;
        3'd4: begin
          display_value = sw[7] ? instruction_count[63:32]
                                : instruction_count[31:0];
        end
        3'd5: display_value = trap_code;
        3'd6: display_value = dmem_addr;
        default: display_value = {23'd0, commit_valid, dmem_read, dmem_write,
                                  dmem_len, 3'd0};
      endcase
    end
  end

  // SW14=1 时绕过 CPU，直接把开关映射到 LED，用于确认板级引脚绑定。
  assign led = sw[14] ? sw
             : illegal ? 16'hdead
             : is_ebreak ? 16'hbeef
             : display_value[15:0];

  // 8 个数码管从低到高分别显示 display_value 的 8 个十六进制数位。
  hex7seg u_seg0(.value(display_value[3:0]),   .segments(seg0));
  hex7seg u_seg1(.value(display_value[7:4]),   .segments(seg1));
  hex7seg u_seg2(.value(display_value[11:8]),  .segments(seg2));
  hex7seg u_seg3(.value(display_value[15:12]), .segments(seg3));
  hex7seg u_seg4(.value(display_value[19:16]), .segments(seg4));
  hex7seg u_seg5(.value(display_value[23:20]), .segments(seg5));
  hex7seg u_seg6(.value(display_value[27:24]), .segments(seg6));
  hex7seg u_seg7(.value(display_value[31:28]), .segments(seg7));

endmodule
