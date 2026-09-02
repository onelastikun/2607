module top (
  input  logic         clock,
  input  logic         reset,
  output logic [63:0]  cycle_count,
  output logic [31:0]  pc,
  output logic [31:0]  inst,
  output logic         commit_valid,
  output logic [31:0]  commit_pc,
  output logic [31:0]  commit_inst,
  output logic [511:0] gpr_state
);

  import "DPI-C" function int unsigned pmem_read(
    input int unsigned addr,
    input byte unsigned len
  );
  import "DPI-C" function void pmem_write(
    input int unsigned addr,
    input int unsigned data,
    input byte unsigned mask
  );
  import "DPI-C" function void npc_ebreak(
    input int unsigned trap_pc,
    input int unsigned code
  );
  import "DPI-C" function void npc_abort(
    input int unsigned abort_pc,
    input int unsigned abort_inst
  );

  localparam logic [31:0] RESET_VECTOR = 32'h8000_0000;

  logic [31:0] gpr [0:15];
  logic [31:0] pc_reg;
  logic [31:0] next_pc;
  logic [31:0] rs1_value;
  logic [31:0] rs2_value;
  logic [31:0] rd_value;
  logic [31:0] imm_i;
  logic [31:0] imm_s;
  logic [31:0] imm_b;
  logic [31:0] imm_u;
  logic [31:0] imm_j;
  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [31:0] mem_rdata;
  logic [4:0]  rs1;
  logic [4:0]  rs2;
  logic [4:0]  rd;
  logic [3:0]  mem_wmask;
  logic        rd_write;
  logic        mem_write;
  logic        is_ebreak;
  logic        illegal;
  logic        branch_taken;

  genvar gi;
  generate
    for (gi = 0; gi < 16; gi = gi + 1) begin : gen_gpr_state
      assign gpr_state[gi * 32 +: 32] = gpr[gi];
    end
  endgenerate

  integer ri;
  always_comb begin
    pc = pc_reg;
    inst = pmem_read(pc_reg, 8'd4);
    rs1 = inst[19:15];
    rs2 = inst[24:20];
    rd = inst[11:7];
    rs1_value = gpr[rs1[3:0]];
    rs2_value = gpr[rs2[3:0]];

    imm_i = {{20{inst[31]}}, inst[31:20]};
    imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25],
             inst[11:8], 1'b0};
    imm_u = {inst[31:12], 12'b0};
    imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20],
             inst[30:21], 1'b0};

    next_pc = pc_reg + 32'd4;
    rd_value = 32'd0;
    rd_write = 1'b0;
    mem_addr = 32'd0;
    mem_wdata = 32'd0;
    mem_rdata = 32'd0;
    mem_wmask = 4'b0000;
    mem_write = 1'b0;
    is_ebreak = 1'b0;
    illegal = 1'b0;
    branch_taken = 1'b0;

    case (inst[6:0])
      7'b0110111: begin  // LUI
        if (rd[4]) illegal = 1'b1;
        else begin
          rd_write = 1'b1;
          rd_value = imm_u;
        end
      end

      7'b0010111: begin  // AUIPC
        if (rd[4]) illegal = 1'b1;
        else begin
          rd_write = 1'b1;
          rd_value = pc_reg + imm_u;
        end
      end

      7'b1101111: begin  // JAL
        if (rd[4]) illegal = 1'b1;
        else begin
          rd_write = 1'b1;
          rd_value = pc_reg + 32'd4;
          next_pc = pc_reg + imm_j;
        end
      end

      7'b1100111: begin  // JALR
        if (rd[4] || rs1[4] || (inst[14:12] != 3'b000)) illegal = 1'b1;
        else begin
          rd_write = 1'b1;
          rd_value = pc_reg + 32'd4;
          next_pc = (rs1_value + imm_i) & 32'hffff_fffe;
        end
      end

      7'b1100011: begin  // BRANCH
        if (rs1[4] || rs2[4]) illegal = 1'b1;
        else begin
          case (inst[14:12])
            3'b000: branch_taken = (rs1_value == rs2_value);                 // BEQ
            3'b001: branch_taken = (rs1_value != rs2_value);                 // BNE
            3'b100: branch_taken = ($signed(rs1_value) < $signed(rs2_value));// BLT
            3'b101: branch_taken = ($signed(rs1_value) >= $signed(rs2_value));// BGE
            3'b110: branch_taken = (rs1_value < rs2_value);                  // BLTU
            3'b111: branch_taken = (rs1_value >= rs2_value);                 // BGEU
            default: illegal = 1'b1;
          endcase
          if (branch_taken && !illegal) next_pc = pc_reg + imm_b;
        end
      end

      7'b0000011: begin  // LOAD
        if (rd[4] || rs1[4]) illegal = 1'b1;
        else begin
          mem_addr = rs1_value + imm_i;
          rd_write = 1'b1;
          case (inst[14:12])
            3'b000: begin                                                     // LB
              mem_rdata = pmem_read(mem_addr, 8'd1);
              rd_value = {{24{mem_rdata[7]}}, mem_rdata[7:0]};
            end
            3'b001: begin                                                     // LH
              mem_rdata = pmem_read(mem_addr, 8'd2);
              rd_value = {{16{mem_rdata[15]}}, mem_rdata[15:0]};
            end
            3'b010: begin                                                     // LW
              mem_rdata = pmem_read(mem_addr, 8'd4);
              rd_value = mem_rdata;
            end
            3'b100: begin                                                     // LBU
              mem_rdata = pmem_read(mem_addr, 8'd1);
              rd_value = {24'd0, mem_rdata[7:0]};
            end
            3'b101: begin                                                     // LHU
              mem_rdata = pmem_read(mem_addr, 8'd2);
              rd_value = {16'd0, mem_rdata[15:0]};
            end
            default: begin
              rd_write = 1'b0;
              illegal = 1'b1;
            end
          endcase
        end
      end

      7'b0100011: begin  // STORE
        if (rs1[4] || rs2[4]) illegal = 1'b1;
        else begin
          mem_addr = rs1_value + imm_s;
          mem_wdata = rs2_value;
          mem_write = 1'b1;
          case (inst[14:12])
            3'b000: mem_wmask = 4'b0001;  // SB
            3'b001: mem_wmask = 4'b0011;  // SH
            3'b010: mem_wmask = 4'b1111;  // SW
            default: begin
              mem_write = 1'b0;
              illegal = 1'b1;
            end
          endcase
        end
      end

      7'b0010011: begin  // OP-IMM
        if (rd[4] || rs1[4]) illegal = 1'b1;
        else begin
          rd_write = 1'b1;
          case (inst[14:12])
            3'b000: rd_value = rs1_value + imm_i;                            // ADDI
            3'b010: rd_value = {31'd0, ($signed(rs1_value) < $signed(imm_i))};          // SLTI
            3'b011: rd_value = {31'd0, (rs1_value < imm_i)};                            // SLTIU
            3'b100: rd_value = rs1_value ^ imm_i;                            // XORI
            3'b110: rd_value = rs1_value | imm_i;                            // ORI
            3'b111: rd_value = rs1_value & imm_i;                            // ANDI
            3'b001: begin
              if (inst[31:25] == 7'b0000000)
                rd_value = rs1_value << inst[24:20];                         // SLLI
              else illegal = 1'b1;
            end
            3'b101: begin
              if (inst[31:25] == 7'b0000000)
                rd_value = rs1_value >> inst[24:20];                         // SRLI
              else if (inst[31:25] == 7'b0100000)
                rd_value = $signed(rs1_value) >>> inst[24:20];               // SRAI
              else illegal = 1'b1;
            end
            default: illegal = 1'b1;
          endcase
          if (illegal) rd_write = 1'b0;
        end
      end

      7'b0110011: begin  // OP
        if (rd[4] || rs1[4] || rs2[4]) illegal = 1'b1;
        else begin
          rd_write = 1'b1;
          case ({inst[31:25], inst[14:12]})
            10'b0000000_000: rd_value = rs1_value + rs2_value;               // ADD
            10'b0100000_000: rd_value = rs1_value - rs2_value;               // SUB
            10'b0000000_001: rd_value = rs1_value << rs2_value[4:0];         // SLL
            10'b0000000_010: rd_value = {31'd0, ($signed(rs1_value) < $signed(rs2_value))};// SLT
            10'b0000000_011: rd_value = {31'd0, (rs1_value < rs2_value)};               // SLTU
            10'b0000000_100: rd_value = rs1_value ^ rs2_value;               // XOR
            10'b0000000_101: rd_value = rs1_value >> rs2_value[4:0];         // SRL
            10'b0100000_101: rd_value = $signed(rs1_value) >>> rs2_value[4:0];// SRA
            10'b0000000_110: rd_value = rs1_value | rs2_value;               // OR
            10'b0000000_111: rd_value = rs1_value & rs2_value;               // AND
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

  always_ff @(posedge clock) begin
    if (reset) begin
      pc_reg <= RESET_VECTOR;
      cycle_count <= 64'd0;
      commit_valid <= 1'b0;
      commit_pc <= 32'd0;
      commit_inst <= 32'd0;
      for (ri = 0; ri < 16; ri = ri + 1) begin
        gpr[ri] <= 32'd0;
      end
    end else begin
      cycle_count <= cycle_count + 64'd1;
      commit_valid <= 1'b1;
      commit_pc <= pc_reg;
      commit_inst <= inst;
      pc_reg <= next_pc;

      if (rd_write && (rd != 5'd0)) gpr[rd[3:0]] <= rd_value;
      gpr[0] <= 32'd0;
      if (mem_write) pmem_write(mem_addr, mem_wdata, {4'd0, mem_wmask});
      if (illegal) npc_abort(pc_reg, inst);
      if (is_ebreak) npc_ebreak(pc_reg, gpr[10]);
    end
  end

endmodule
