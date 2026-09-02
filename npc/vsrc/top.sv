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
  logic [31:0] next_pc;
  logic [31:0] rd_value;
  logic [4:0]  rd;
  logic [4:0]  rs1;
  logic [4:0]  rs2;
  logic        rd_write;
  logic        is_ebreak;
  logic        illegal;
  logic [31:0] imm_i;

  genvar gi;
  generate
    for (gi = 0; gi < 16; gi = gi + 1) begin : gen_gpr_state
      assign gpr_state[gi * 32 +: 32] = gpr[gi];
    end
  endgenerate

  // The architectural PC is kept separately from commit information.
  logic [31:0] pc_reg;
  integer ri;
  always_comb begin
    pc = pc_reg;
    inst = pmem_read(pc_reg, 8'd4);
    rs1 = inst[19:15];
    rs2 = inst[24:20];
    rd = inst[11:7];
    imm_i = {{20{inst[31]}}, inst[31:20]};

    next_pc = pc_reg + 32'd4;
    rd_value = 32'd0;
    rd_write = 1'b0;
    is_ebreak = 1'b0;
    illegal = 1'b0;

    case (inst[6:0])
      7'b0010011: begin
        if ((inst[14:12] == 3'b000) && !rs1[4] && !rd[4]) begin
          rd_write = 1'b1;
          rd_value = gpr[rs1[3:0]] + imm_i;
        end else begin
          illegal = 1'b1;
        end
      end
      7'b0110011: begin
        if (({inst[31:25], inst[14:12]} == 10'b0000000_000) &&
            !rs1[4] && !rs2[4] && !rd[4]) begin
          rd_write = 1'b1;
          rd_value = gpr[rs1[3:0]] + gpr[rs2[3:0]];
        end else begin
          illegal = 1'b1;
        end
      end
      7'b1110011: begin
        if (inst == 32'h0010_0073) begin
          is_ebreak = 1'b1;
        end else begin
          illegal = 1'b1;
        end
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

      if (rd_write && (rd != 5'd0)) begin
        gpr[rd[3:0]] <= rd_value;
      end
      gpr[0] <= 32'd0;

      if (illegal) begin
        npc_abort(pc_reg, inst);
      end
      if (is_ebreak) begin
        npc_ebreak(pc_reg, gpr[10]);
      end
    end
  end

endmodule
