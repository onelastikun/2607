// MiniRV 的组合译码与执行数据通路。
// 正式指令范围只有 add/addi/lui/lw/lbu/sw/sb/jalr；另外保留 E7 要求的只读 CSR 和仿真 ebreak。
module ysyx_25100265_minirv_decode #(
  parameter logic [31:0] MVENDORID = 32'h7973_7978,
  parameter logic [31:0] MARCHID = 32'd0
) (
  input  logic [31:0] pc,
  input  logic [63:0] cycle_count,
  input  logic [31:0] inst,
  input  logic [31:0] rs1_value,
  input  logic [31:0] rs2_value,
  input  logic [31:0] dmem_rdata,
  output logic [31:0] next_pc,
  output logic        rd_write,
  output logic [31:0] rd_value,
  output logic        dmem_read,
  output logic [2:0]  dmem_len,
  output logic [31:0] dmem_addr,
  output logic        dmem_write,
  output logic [31:0] dmem_wdata,
  output logic [3:0]  dmem_wmask,
  output logic        is_ebreak,
  output logic        illegal
);

  // MiniRV 沿用 RV32E 的 16 个寄存器，字段 bit4 为 1 表示访问 x16~x31。
  logic rs1_high;
  logic rs2_high;
  logic rd_high;
  logic [31:0] imm_i;
  logic [31:0] imm_s;
  logic [31:0] imm_u;
  logic csr_read_valid;
  logic [31:0] csr_read_value;

  always_comb begin
    rs1_high = inst[19];
    rs2_high = inst[24];
    rd_high = inst[11];
    imm_i = {{20{inst[31]}}, inst[31:20]};
    imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    imm_u = {inst[31:12], 12'b0};

    // 默认按顺序执行且不访问寄存器/存储器，确保组合逻辑没有锁存器。
    next_pc = pc + 32'd4;
    rd_write = 1'b0;
    rd_value = 32'd0;
    dmem_read = 1'b0;
    dmem_len = 3'd0;
    dmem_addr = 32'd0;
    dmem_write = 1'b0;
    dmem_wdata = 32'd0;
    dmem_wmask = 4'b0000;
    is_ebreak = 1'b0;
    illegal = 1'b0;

    // E7 只要求读取厂商、架构和周期计数 CSR，不实现可写 CSR。
    csr_read_valid = 1'b1;
    case (inst[31:20])
      12'hf11: csr_read_value = MVENDORID;
      12'hf12: csr_read_value = MARCHID;
      12'hb00: csr_read_value = cycle_count[31:0];
      12'hb80: csr_read_value = cycle_count[63:32];
      12'hc00: csr_read_value = cycle_count[31:0];
      12'hc80: csr_read_value = cycle_count[63:32];
      default: begin
        csr_read_valid = 1'b0;
        csr_read_value = 32'd0;
      end
    endcase

    case (inst[6:0])
      7'b0110111: begin  // LUI
        if (rd_high) illegal = 1'b1;
        else begin
          rd_write = 1'b1;
          rd_value = imm_u;
        end
      end

      7'b1100111: begin  // JALR
        if (rd_high || rs1_high || (inst[14:12] != 3'b000)) illegal = 1'b1;
        else begin
          rd_write = 1'b1;
          rd_value = pc + 32'd4;
          next_pc = (rs1_value + imm_i) & 32'hffff_fffe;
        end
      end

      7'b0000011: begin  // LW / LBU
        if (rd_high || rs1_high) illegal = 1'b1;
        else begin
          dmem_addr = rs1_value + imm_i;
          case (inst[14:12])
            3'b010: begin
              dmem_read = 1'b1;
              dmem_len = 3'd4;
              rd_write = 1'b1;
              rd_value = dmem_rdata;
            end
            3'b100: begin
              dmem_read = 1'b1;
              dmem_len = 3'd1;
              rd_write = 1'b1;
              rd_value = {24'd0, dmem_rdata[7:0]};
            end
            default: illegal = 1'b1;
          endcase
        end
      end

      7'b0100011: begin  // SW / SB
        if (rs1_high || rs2_high) illegal = 1'b1;
        else begin
          dmem_addr = rs1_value + imm_s;
          dmem_wdata = rs2_value;
          case (inst[14:12])
            3'b000: begin
              dmem_write = 1'b1;
              dmem_wmask = 4'b0001;
            end
            3'b010: begin
              dmem_write = 1'b1;
              dmem_wmask = 4'b1111;
            end
            default: illegal = 1'b1;
          endcase
        end
      end

      7'b0010011: begin  // ADDI
        if (rd_high || rs1_high || (inst[14:12] != 3'b000)) illegal = 1'b1;
        else begin
          rd_write = 1'b1;
          rd_value = rs1_value + imm_i;
        end
      end

      7'b0110011: begin  // ADD
        if (rd_high || rs1_high || rs2_high ||
            (inst[31:25] != 7'b0000000) || (inst[14:12] != 3'b000)) begin
          illegal = 1'b1;
        end else begin
          rd_write = 1'b1;
          rd_value = rs1_value + rs2_value;
        end
      end

      7'b1110011: begin
        if (inst == 32'h0010_0073) begin  // EBREAK：仿真结束标记
          is_ebreak = 1'b1;
        end else if ((inst[14:12] == 3'b010) && (inst[19:15] == 5'd0) &&
                     !rd_high && csr_read_valid) begin
          // CSRRS rd, csr, x0，即 csrr 伪指令。
          rd_write = 1'b1;
          rd_value = csr_read_value;
        end else begin
          illegal = 1'b1;
        end
      end

      default: illegal = 1'b1;
    endcase
  end

endmodule
