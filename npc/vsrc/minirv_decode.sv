// Pure combinational decoder and execute path for the MiniRV/RV32E subset.
// Sequential architectural state is intentionally kept out of this module.
module minirv_decode (
  input  logic [31:0] pc,
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

  logic rs1_high;
  logic rs2_high;
  logic rd_high;
  logic [31:0] imm_i;
  logic [31:0] imm_s;
  logic [31:0] imm_b;
  logic [31:0] imm_u;
  logic [31:0] imm_j;
  logic branch_taken;

  always_comb begin
    rs1_high = inst[19];
    rs2_high = inst[24];
    rd_high = inst[11];
    imm_i = {{20{inst[31]}}, inst[31:20]};
    imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25],
             inst[11:8], 1'b0};
    imm_u = {inst[31:12], 12'b0};
    imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20],
             inst[30:21], 1'b0};

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
    branch_taken = 1'b0;

    case (inst[6:0])
      7'b0110111: begin  // LUI
        if (rd_high) illegal = 1'b1;
        else begin rd_write = 1'b1; rd_value = imm_u; end
      end
      7'b0010111: begin  // AUIPC
        if (rd_high) illegal = 1'b1;
        else begin rd_write = 1'b1; rd_value = pc + imm_u; end
      end
      7'b1101111: begin  // JAL
        if (rd_high) illegal = 1'b1;
        else begin
          rd_write = 1'b1;
          rd_value = pc + 32'd4;
          next_pc = pc + imm_j;
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
      7'b1100011: begin  // Conditional branches
        if (rs1_high || rs2_high) illegal = 1'b1;
        else begin
          case (inst[14:12])
            3'b000: branch_taken = (rs1_value == rs2_value);                  // BEQ
            3'b001: branch_taken = (rs1_value != rs2_value);                  // BNE
            3'b100: branch_taken = ($signed(rs1_value) < $signed(rs2_value)); // BLT
            3'b101: branch_taken = ($signed(rs1_value) >= $signed(rs2_value));// BGE
            3'b110: branch_taken = (rs1_value < rs2_value);                   // BLTU
            3'b111: branch_taken = (rs1_value >= rs2_value);                  // BGEU
            default: illegal = 1'b1;
          endcase
          if (branch_taken && !illegal) next_pc = pc + imm_b;
        end
      end
      7'b0000011: begin  // Loads
        if (rd_high || rs1_high) illegal = 1'b1;
        else begin
          dmem_addr = rs1_value + imm_i;
          dmem_read = 1'b1;
          rd_write = 1'b1;
          case (inst[14:12])
            3'b000: begin dmem_len = 3'd1; rd_value = {{24{dmem_rdata[7]}}, dmem_rdata[7:0]}; end
            3'b001: begin dmem_len = 3'd2; rd_value = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]}; end
            3'b010: begin dmem_len = 3'd4; rd_value = dmem_rdata; end
            3'b100: begin dmem_len = 3'd1; rd_value = {24'd0, dmem_rdata[7:0]}; end
            3'b101: begin dmem_len = 3'd2; rd_value = {16'd0, dmem_rdata[15:0]}; end
            default: begin dmem_read = 1'b0; rd_write = 1'b0; illegal = 1'b1; end
          endcase
        end
      end
      7'b0100011: begin  // Stores
        if (rs1_high || rs2_high) illegal = 1'b1;
        else begin
          dmem_addr = rs1_value + imm_s;
          dmem_wdata = rs2_value;
          dmem_write = 1'b1;
          case (inst[14:12])
            3'b000: dmem_wmask = 4'b0001;
            3'b001: dmem_wmask = 4'b0011;
            3'b010: dmem_wmask = 4'b1111;
            default: begin dmem_write = 1'b0; illegal = 1'b1; end
          endcase
        end
      end
      7'b0010011: begin  // Immediate ALU operations
        if (rd_high || rs1_high) illegal = 1'b1;
        else begin
          rd_write = 1'b1;
          case (inst[14:12])
            3'b000: rd_value = rs1_value + imm_i;
            3'b010: rd_value = {31'd0, ($signed(rs1_value) < $signed(imm_i))};
            3'b011: rd_value = {31'd0, (rs1_value < imm_i)};
            3'b100: rd_value = rs1_value ^ imm_i;
            3'b110: rd_value = rs1_value | imm_i;
            3'b111: rd_value = rs1_value & imm_i;
            3'b001: begin
              if (inst[31:25] == 7'b0000000) rd_value = rs1_value << inst[24:20];
              else illegal = 1'b1;
            end
            3'b101: begin
              if (inst[31:25] == 7'b0000000) rd_value = rs1_value >> inst[24:20];
              else if (inst[31:25] == 7'b0100000) rd_value = $signed(rs1_value) >>> inst[24:20];
              else illegal = 1'b1;
            end
            default: illegal = 1'b1;
          endcase
          if (illegal) rd_write = 1'b0;
        end
      end
      7'b0110011: begin  // Register ALU operations
        if (rd_high || rs1_high || rs2_high) illegal = 1'b1;
        else begin
          rd_write = 1'b1;
          case ({inst[31:25], inst[14:12]})
            10'b0000000_000: rd_value = rs1_value + rs2_value;
            10'b0100000_000: rd_value = rs1_value - rs2_value;
            10'b0000000_001: rd_value = rs1_value << rs2_value[4:0];
            10'b0000000_010: rd_value = {31'd0, ($signed(rs1_value) < $signed(rs2_value))};
            10'b0000000_011: rd_value = {31'd0, (rs1_value < rs2_value)};
            10'b0000000_100: rd_value = rs1_value ^ rs2_value;
            10'b0000000_101: rd_value = rs1_value >> rs2_value[4:0];
            10'b0100000_101: rd_value = $signed(rs1_value) >>> rs2_value[4:0];
            10'b0000000_110: rd_value = rs1_value | rs2_value;
            10'b0000000_111: rd_value = rs1_value & rs2_value;
            default: illegal = 1'b1;
          endcase
          if (illegal) rd_write = 1'b0;
        end
      end
      7'b0001111: begin  // FENCE is a no-op in this single-core model.
        if (inst[14:12] != 3'b000) illegal = 1'b1;
      end
      7'b1110011: begin
        if (inst == 32'h0010_0073) is_ebreak = 1'b1;
        else illegal = 1'b1;
      end
      default: illegal = 1'b1;
    endcase
  end

endmodule
