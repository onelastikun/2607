// MiniRV 核心：保存 PC 和寄存器等架构状态，并定义清晰的指令提交边界。
// 存储器时序由外部总线主设备负责；只有 step=1 时当前指令才真正提交。
module minirv_core #(
  parameter logic [31:0] RESET_VECTOR = 32'h8000_0000,
  parameter logic [31:0] MVENDORID = 32'h7973_7978,
  parameter logic [31:0] MARCHID = 32'd0
) (
  input  logic         clock,
  input  logic         reset,
  input  logic         step,
  output logic [31:0]  imem_addr,
  input  logic [31:0]  imem_rdata,
  output logic         dmem_read,
  output logic [2:0]   dmem_len,
  output logic [31:0]  dmem_addr,
  input  logic [31:0]  dmem_rdata,
  output logic         dmem_write,
  output logic [31:0]  dmem_wdata,
  output logic [3:0]   dmem_wmask,
  output logic         is_ebreak,
  output logic         illegal,
  output logic [31:0]  trap_code,
  output logic [63:0]  instruction_count,
  output logic [31:0]  pc,
  output logic [31:0]  inst,
  output logic         commit_valid,
  output logic [31:0]  commit_pc,
  output logic [31:0]  commit_inst,
  output logic [511:0] gpr_state
);

  // pc_reg 是本模块直接保存的核心状态，其余信号由组合译码产生。
  logic [31:0] pc_reg;
  logic [63:0] cycle_count;
  logic [31:0] next_pc;
  logic [31:0] rs1_value;
  logic [31:0] rs2_value;
  logic [31:0] rd_value;
  logic        rd_write;
  logic        regfile_write;
  logic [3:0]  rs1_idx;
  logic [3:0]  rs2_idx;
  logic [3:0]  rd_idx;

  // MiniRV 沿用 RV32E 的 x0~x15，因此这里只取寄存器编号的低 4 位；
  // 编号最高位是否合法由 minirv_decode 单独检查，不能仅靠截断忽略。
  assign pc = pc_reg;
  assign inst = imem_rdata;
  assign imem_addr = pc_reg;
  assign rs1_idx = inst[18:15];
  assign rs2_idx = inst[23:20];
  assign rd_idx = inst[10:7];
  assign regfile_write = rd_write && step;

  // 寄存器堆负责组合读取和提交时写回。
  minirv_regfile u_regfile (
    .clock(clock),
    .reset(reset),
    .rs1_idx(rs1_idx),
    .rs2_idx(rs2_idx),
    .rd_idx(rd_idx),
    .rd_write(regfile_write),
    .rd_value(rd_value),
    .rs1_value(rs1_value),
    .rs2_value(rs2_value),
    .a0_value(trap_code),
    .gpr_state(gpr_state)
  );

  // 译码器是纯组合模块，根据当前指令计算下一 PC、写回值和访存请求。
  minirv_decode #(
    .MVENDORID(MVENDORID), .MARCHID(MARCHID)
  ) u_decode (
    .pc(pc_reg), .cycle_count(cycle_count),
    .inst(inst),
    .rs1_value(rs1_value),
    .rs2_value(rs2_value),
    .dmem_rdata(dmem_rdata),
    .next_pc(next_pc),
    .rd_write(rd_write),
    .rd_value(rd_value),
    .dmem_read(dmem_read),
    .dmem_len(dmem_len),
    .dmem_addr(dmem_addr),
    .dmem_write(dmem_write),
    .dmem_wdata(dmem_wdata),
    .dmem_wmask(dmem_wmask),
    .is_ebreak(is_ebreak),
    .illegal(illegal)
  );

  // step 是唯一提交使能：等待取指、load 或 store 响应时，PC 和寄存器均不前进。
  // commit_* 锁存“刚刚完成”的指令，供 itrace 和 DiffTest 在同一边界观察。
  always_ff @(posedge clock) begin
    if (reset) begin
      pc_reg <= RESET_VECTOR;
      cycle_count <= 64'd0;
      instruction_count <= 64'd0;
      commit_valid <= 1'b0;
      commit_pc <= 32'd0;
      commit_inst <= 32'd0;
    end else begin
      // mcycle 统计核心时钟周期，等待总线的周期也必须计入。
      cycle_count <= cycle_count + 64'd1;
      commit_valid <= 1'b0;
      if (step) begin
        pc_reg <= next_pc;
        instruction_count <= instruction_count + 64'd1;
        commit_valid <= 1'b1;
        commit_pc <= pc_reg;
        commit_inst <= inst;
      end
    end
  end

endmodule
