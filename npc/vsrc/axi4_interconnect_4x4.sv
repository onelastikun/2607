// Four-master/four-slave AXI4 interconnect for single-beat transactions.
// IDs are extended with the master index so read/write responses route without
// global ordering state. Burst fields are forwarded, but this project issues
// only LEN=0 transactions before SoC integration.
module axi4_interconnect_4x4 #(
  parameter int MID_WIDTH = 4,
  parameter int SID_WIDTH = MID_WIDTH + 2
) (
  input  logic                         clock,
  input  logic                         reset,

  input  logic [3:0]                   m_arvalid,
  output logic [3:0]                   m_arready,
  input  logic [4*32-1:0]              m_araddr,
  input  logic [4*MID_WIDTH-1:0]       m_arid,
  input  logic [4*8-1:0]               m_arlen,
  input  logic [4*3-1:0]               m_arsize,
  input  logic [4*2-1:0]               m_arburst,
  output logic [3:0]                   m_rvalid,
  input  logic [3:0]                   m_rready,
  output logic [4*32-1:0]              m_rdata,
  output logic [4*2-1:0]               m_rresp,
  output logic [4*MID_WIDTH-1:0]       m_rid,
  output logic [3:0]                   m_rlast,

  input  logic [3:0]                   m_awvalid,
  output logic [3:0]                   m_awready,
  input  logic [4*32-1:0]              m_awaddr,
  input  logic [4*MID_WIDTH-1:0]       m_awid,
  input  logic [4*8-1:0]               m_awlen,
  input  logic [4*3-1:0]               m_awsize,
  input  logic [4*2-1:0]               m_awburst,
  input  logic [3:0]                   m_wvalid,
  output logic [3:0]                   m_wready,
  input  logic [4*32-1:0]              m_wdata,
  input  logic [4*4-1:0]               m_wstrb,
  input  logic [3:0]                   m_wlast,
  output logic [3:0]                   m_bvalid,
  input  logic [3:0]                   m_bready,
  output logic [4*2-1:0]               m_bresp,
  output logic [4*MID_WIDTH-1:0]       m_bid,

  output logic [3:0]                   s_arvalid,
  input  logic [3:0]                   s_arready,
  output logic [4*32-1:0]              s_araddr,
  output logic [4*SID_WIDTH-1:0]       s_arid,
  output logic [4*8-1:0]               s_arlen,
  output logic [4*3-1:0]               s_arsize,
  output logic [4*2-1:0]               s_arburst,
  input  logic [3:0]                   s_rvalid,
  output logic [3:0]                   s_rready,
  input  logic [4*32-1:0]              s_rdata,
  input  logic [4*2-1:0]               s_rresp,
  input  logic [4*SID_WIDTH-1:0]       s_rid,
  input  logic [3:0]                   s_rlast,

  output logic [3:0]                   s_awvalid,
  input  logic [3:0]                   s_awready,
  output logic [4*32-1:0]              s_awaddr,
  output logic [4*SID_WIDTH-1:0]       s_awid,
  output logic [4*8-1:0]               s_awlen,
  output logic [4*3-1:0]               s_awsize,
  output logic [4*2-1:0]               s_awburst,
  output logic [3:0]                   s_wvalid,
  input  logic [3:0]                   s_wready,
  output logic [4*32-1:0]              s_wdata,
  output logic [4*4-1:0]               s_wstrb,
  output logic [3:0]                   s_wlast,
  input  logic [3:0]                   s_bvalid,
  output logic [3:0]                   s_bready,
  input  logic [4*2-1:0]               s_bresp,
  input  logic [4*SID_WIDTH-1:0]       s_bid
);

  logic [3:0] write_busy;
  logic [1:0] write_target [0:3];
  integer comb_master;
  integer comb_slave;
  integer seq_master;
  logic [1:0] response_master;

  function automatic logic [1:0] decode_target(input logic [3:0] region);
    case (region)
      4'h8: decode_target = 2'd0;  // main memory
      4'ha: decode_target = 2'd1;  // MMIO
      4'hc: decode_target = 2'd2;  // reserved expansion window
      default: decode_target = 2'd3; // default/error target
    endcase
  endfunction

  always_comb begin
    m_arready = 4'd0;
    m_rvalid = 4'd0;
    m_rdata = '0;
    m_rresp = '0;
    m_rid = '0;
    m_rlast = 4'd0;
    m_awready = 4'd0;
    m_wready = 4'd0;
    m_bvalid = 4'd0;
    m_bresp = '0;
    m_bid = '0;

    s_arvalid = 4'd0;
    s_araddr = '0;
    s_arid = '0;
    s_arlen = '0;
    s_arsize = '0;
    s_arburst = '0;
    s_rready = 4'd0;
    s_awvalid = 4'd0;
    s_awaddr = '0;
    s_awid = '0;
    s_awlen = '0;
    s_awsize = '0;
    s_awburst = '0;
    s_wvalid = 4'd0;
    s_wdata = '0;
    s_wstrb = '0;
    s_wlast = 4'd0;
    s_bready = 4'd0;

    // Fixed-priority address arbitration is local to each target.
    for (comb_slave = 0; comb_slave < 4; comb_slave = comb_slave + 1) begin
      for (comb_master = 0; comb_master < 4; comb_master = comb_master + 1) begin
        if (!s_arvalid[comb_slave] && m_arvalid[comb_master] &&
            decode_target(m_araddr[comb_master*32 + 28 +: 4]) == comb_slave[1:0]) begin
          s_arvalid[comb_slave] = 1'b1;
          s_araddr[comb_slave*32 +: 32] = m_araddr[comb_master*32 +: 32];
          s_arid[comb_slave*SID_WIDTH +: SID_WIDTH] =
              {comb_master[1:0], m_arid[comb_master*MID_WIDTH +: MID_WIDTH]};
          s_arlen[comb_slave*8 +: 8] = m_arlen[comb_master*8 +: 8];
          s_arsize[comb_slave*3 +: 3] = m_arsize[comb_master*3 +: 3];
          s_arburst[comb_slave*2 +: 2] = m_arburst[comb_master*2 +: 2];
          m_arready[comb_master] = s_arready[comb_slave];
        end
        if (!s_awvalid[comb_slave] && m_awvalid[comb_master] && !write_busy[comb_master] &&
            decode_target(m_awaddr[comb_master*32 + 28 +: 4]) == comb_slave[1:0]) begin
          s_awvalid[comb_slave] = 1'b1;
          s_awaddr[comb_slave*32 +: 32] = m_awaddr[comb_master*32 +: 32];
          s_awid[comb_slave*SID_WIDTH +: SID_WIDTH] =
              {comb_master[1:0], m_awid[comb_master*MID_WIDTH +: MID_WIDTH]};
          s_awlen[comb_slave*8 +: 8] = m_awlen[comb_master*8 +: 8];
          s_awsize[comb_slave*3 +: 3] = m_awsize[comb_master*3 +: 3];
          s_awburst[comb_slave*2 +: 2] = m_awburst[comb_master*2 +: 2];
          m_awready[comb_master] = s_awready[comb_slave];
        end
      end
    end

    // AXI4 W has no ID, so an accepted AW records each master's target.
    for (comb_slave = 0; comb_slave < 4; comb_slave = comb_slave + 1) begin
      for (comb_master = 0; comb_master < 4; comb_master = comb_master + 1) begin
        if (!s_wvalid[comb_slave] && write_busy[comb_master] &&
            write_target[comb_master] == comb_slave[1:0] && m_wvalid[comb_master]) begin
          s_wvalid[comb_slave] = 1'b1;
          s_wdata[comb_slave*32 +: 32] = m_wdata[comb_master*32 +: 32];
          s_wstrb[comb_slave*4 +: 4] = m_wstrb[comb_master*4 +: 4];
          s_wlast[comb_slave] = m_wlast[comb_master];
          m_wready[comb_master] = s_wready[comb_slave];
        end
      end
    end

    // Response IDs carry the original master index in their upper bits.
    for (comb_master = 0; comb_master < 4; comb_master = comb_master + 1) begin
      for (comb_slave = 0; comb_slave < 4; comb_slave = comb_slave + 1) begin
        response_master = s_rid[comb_slave*SID_WIDTH + MID_WIDTH +: 2];
        if (!m_rvalid[comb_master] && s_rvalid[comb_slave] &&
            response_master == comb_master[1:0]) begin
          m_rvalid[comb_master] = 1'b1;
          m_rdata[comb_master*32 +: 32] = s_rdata[comb_slave*32 +: 32];
          m_rresp[comb_master*2 +: 2] = s_rresp[comb_slave*2 +: 2];
          m_rid[comb_master*MID_WIDTH +: MID_WIDTH] =
              s_rid[comb_slave*SID_WIDTH +: MID_WIDTH];
          m_rlast[comb_master] = s_rlast[comb_slave];
          s_rready[comb_slave] = m_rready[comb_master];
        end

        response_master = s_bid[comb_slave*SID_WIDTH + MID_WIDTH +: 2];
        if (!m_bvalid[comb_master] && s_bvalid[comb_slave] &&
            response_master == comb_master[1:0]) begin
          m_bvalid[comb_master] = 1'b1;
          m_bresp[comb_master*2 +: 2] = s_bresp[comb_slave*2 +: 2];
          m_bid[comb_master*MID_WIDTH +: MID_WIDTH] =
              s_bid[comb_slave*SID_WIDTH +: MID_WIDTH];
          s_bready[comb_slave] = m_bready[comb_master];
        end
      end
    end
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      write_busy <= 4'd0;
      for (seq_master = 0; seq_master < 4; seq_master = seq_master + 1) begin
        write_target[seq_master] <= 2'd0;
      end
    end else begin
      for (seq_master = 0; seq_master < 4; seq_master = seq_master + 1) begin
        if (m_awvalid[seq_master] && m_awready[seq_master]) begin
          write_busy[seq_master] <= 1'b1;
          write_target[seq_master] <=
              decode_target(m_awaddr[seq_master*32 + 28 +: 4]);
        end
        if (m_bvalid[seq_master] && m_bready[seq_master]) begin
          write_busy[seq_master] <= 1'b0;
        end
      end
    end
  end

endmodule
