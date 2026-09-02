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
  integer ar_master;
  integer ar_slave;
  integer aw_master;
  integer aw_slave;
  integer w_master;
  integer w_slave;
  integer resp_master;
  integer resp_slave;
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

  always_comb begin : route_read_addresses
    m_arready = 4'd0;
    s_arvalid = 4'd0;
    s_araddr = '0;
    s_arid = '0;
    s_arlen = '0;
    s_arsize = '0;
    s_arburst = '0;
    for (ar_slave = 0; ar_slave < 4; ar_slave = ar_slave + 1) begin
      for (ar_master = 0; ar_master < 4; ar_master = ar_master + 1) begin
        if (!s_arvalid[ar_slave] && m_arvalid[ar_master] &&
            decode_target(m_araddr[ar_master*32 + 28 +: 4]) == ar_slave[1:0]) begin
          s_arvalid[ar_slave] = 1'b1;
          s_araddr[ar_slave*32 +: 32] = m_araddr[ar_master*32 +: 32];
          s_arid[ar_slave*SID_WIDTH +: SID_WIDTH] =
              {ar_master[1:0], m_arid[ar_master*MID_WIDTH +: MID_WIDTH]};
          s_arlen[ar_slave*8 +: 8] = m_arlen[ar_master*8 +: 8];
          s_arsize[ar_slave*3 +: 3] = m_arsize[ar_master*3 +: 3];
          s_arburst[ar_slave*2 +: 2] = m_arburst[ar_master*2 +: 2];
          m_arready[ar_master] = s_arready[ar_slave];
        end
      end
    end
  end

  always_comb begin : route_write_addresses
    m_awready = 4'd0;
    s_awvalid = 4'd0;
    s_awaddr = '0;
    s_awid = '0;
    s_awlen = '0;
    s_awsize = '0;
    s_awburst = '0;
    for (aw_slave = 0; aw_slave < 4; aw_slave = aw_slave + 1) begin
      for (aw_master = 0; aw_master < 4; aw_master = aw_master + 1) begin
        if (!s_awvalid[aw_slave] && m_awvalid[aw_master] &&
            !write_busy[aw_master] &&
            decode_target(m_awaddr[aw_master*32 + 28 +: 4]) == aw_slave[1:0]) begin
          s_awvalid[aw_slave] = 1'b1;
          s_awaddr[aw_slave*32 +: 32] = m_awaddr[aw_master*32 +: 32];
          s_awid[aw_slave*SID_WIDTH +: SID_WIDTH] =
              {aw_master[1:0], m_awid[aw_master*MID_WIDTH +: MID_WIDTH]};
          s_awlen[aw_slave*8 +: 8] = m_awlen[aw_master*8 +: 8];
          s_awsize[aw_slave*3 +: 3] = m_awsize[aw_master*3 +: 3];
          s_awburst[aw_slave*2 +: 2] = m_awburst[aw_master*2 +: 2];
          m_awready[aw_master] = s_awready[aw_slave];
        end
      end
    end
  end

  always_comb begin : route_write_data
    m_wready = 4'd0;
    s_wvalid = 4'd0;
    s_wdata = '0;
    s_wstrb = '0;
    s_wlast = 4'd0;
    for (w_slave = 0; w_slave < 4; w_slave = w_slave + 1) begin
      for (w_master = 0; w_master < 4; w_master = w_master + 1) begin
        if (!s_wvalid[w_slave] && write_busy[w_master] &&
            write_target[w_master] == w_slave[1:0] && m_wvalid[w_master]) begin
          s_wvalid[w_slave] = 1'b1;
          s_wdata[w_slave*32 +: 32] = m_wdata[w_master*32 +: 32];
          s_wstrb[w_slave*4 +: 4] = m_wstrb[w_master*4 +: 4];
          s_wlast[w_slave] = m_wlast[w_master];
          m_wready[w_master] = s_wready[w_slave];
        end
      end
    end
  end

  always_comb begin : route_responses
    m_rvalid = 4'd0;
    m_rdata = '0;
    m_rresp = '0;
    m_rid = '0;
    m_rlast = 4'd0;
    s_rready = 4'd0;
    m_bvalid = 4'd0;
    m_bresp = '0;
    m_bid = '0;
    s_bready = 4'd0;
    for (resp_master = 0; resp_master < 4; resp_master = resp_master + 1) begin
      for (resp_slave = 0; resp_slave < 4; resp_slave = resp_slave + 1) begin
        response_master = s_rid[resp_slave*SID_WIDTH + MID_WIDTH +: 2];
        if (!m_rvalid[resp_master] && s_rvalid[resp_slave] &&
            response_master == resp_master[1:0]) begin
          m_rvalid[resp_master] = 1'b1;
          m_rdata[resp_master*32 +: 32] = s_rdata[resp_slave*32 +: 32];
          m_rresp[resp_master*2 +: 2] = s_rresp[resp_slave*2 +: 2];
          m_rid[resp_master*MID_WIDTH +: MID_WIDTH] =
              s_rid[resp_slave*SID_WIDTH +: MID_WIDTH];
          m_rlast[resp_master] = s_rlast[resp_slave];
          s_rready[resp_slave] = m_rready[resp_master];
        end
        response_master = s_bid[resp_slave*SID_WIDTH + MID_WIDTH +: 2];
        if (!m_bvalid[resp_master] && s_bvalid[resp_slave] &&
            response_master == resp_master[1:0]) begin
          m_bvalid[resp_master] = 1'b1;
          m_bresp[resp_master*2 +: 2] = s_bresp[resp_slave*2 +: 2];
          m_bid[resp_master*MID_WIDTH +: MID_WIDTH] =
              s_bid[resp_slave*SID_WIDTH +: MID_WIDTH];
          s_bready[resp_slave] = m_bready[resp_master];
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
