// MiniRV 寄存器堆：沿用 RV32E 的 x0~x15，共 16 个 32 位架构寄存器。
// 两个读端口为组合逻辑，单个写端口在时钟上升沿更新；x0 始终保持为 0。
module ysyx_25100265_minirv_regfile (
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

  // 使用数组表达寄存器堆，索引值就是 RISC-V 寄存器编号。
  logic [31:0] gpr [0:15];
  integer i;

  // 组合读不需要等待时钟，译码模块可以立即取得两个源操作数。
  assign rs1_value = gpr[rs1_idx];
  assign rs2_value = gpr[rs2_idx];
  assign a0_value = gpr[10];

  // 将寄存器数组展平为总线，供 C++ DiffTest 和 NVBoard 调试读取。
  // 第 gi 个寄存器位于 gpr_state[gi*32 +: 32]。
  genvar gi;
  generate
    for (gi = 0; gi < 16; gi = gi + 1) begin : gen_gpr_state
      assign gpr_state[gi * 32 +: 32] = gpr[gi];
    end
  endgenerate

  // 所有架构状态只在此时序块中修改，避免多处驱动同一寄存器。
  always_ff @(posedge clock) begin
    if (reset) begin
      for (i = 0; i < 16; i = i + 1) begin
        gpr[i] <= 32'd0;
      end
    end else begin
      if (rd_write && (rd_idx != 4'd0)) begin
        gpr[rd_idx] <= rd_value;
      end
      // 即使错误控制信号尝试写 x0，也在每个周期再次强制其为 0。
      gpr[0] <= 32'd0;
    end
  end

endmodule
