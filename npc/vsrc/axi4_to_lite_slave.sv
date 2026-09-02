// Adapts one single-beat AXI4 target port to an AXI4-Lite slave.
module axi4_to_lite_slave #(
  parameter int SID_WIDTH = 6
) (
  input  logic                 clock,
  input  logic                 reset,
  input  logic                 axi_arvalid,
  output logic                 axi_arready,
  input  logic [31:0]          axi_araddr,
  input  logic [SID_WIDTH-1:0] axi_arid,
  input  logic [7:0]           axi_arlen,
  input  logic [2:0]           axi_arsize,
  input  logic [1:0]           axi_arburst,
  output logic                 axi_rvalid,
  input  logic                 axi_rready,
  output logic [31:0]          axi_rdata,
  output logic [1:0]           axi_rresp,
  output logic [SID_WIDTH-1:0] axi_rid,
  output logic                 axi_rlast,
  input  logic                 axi_awvalid,
  output logic                 axi_awready,
  input  logic [31:0]          axi_awaddr,
  input  logic [SID_WIDTH-1:0] axi_awid,
  input  logic [7:0]           axi_awlen,
  input  logic [2:0]           axi_awsize,
  input  logic [1:0]           axi_awburst,
  input  logic                 axi_wvalid,
  output logic                 axi_wready,
  input  logic [31:0]          axi_wdata,
  input  logic [3:0]           axi_wstrb,
  input  logic                 axi_wlast,
  output logic                 axi_bvalid,
  input  logic                 axi_bready,
  output logic [1:0]           axi_bresp,
  output logic [SID_WIDTH-1:0] axi_bid,

  output logic                 lite_arvalid,
  input  logic                 lite_arready,
  output logic [31:0]          lite_araddr,
  input  logic                 lite_rvalid,
  output logic                 lite_rready,
  input  logic [31:0]          lite_rdata,
  input  logic [1:0]           lite_rresp,
  output logic                 lite_awvalid,
  input  logic                 lite_awready,
  output logic [31:0]          lite_awaddr,
  output logic                 lite_wvalid,
  input  logic                 lite_wready,
  output logic [31:0]          lite_wdata,
  output logic [3:0]           lite_wstrb,
  input  logic                 lite_bvalid,
  output logic                 lite_bready,
  input  logic [1:0]           lite_bresp,
  output logic                 protocol_error
);

  logic [SID_WIDTH-1:0] read_id;
  logic [SID_WIDTH-1:0] write_id;

  assign lite_arvalid = axi_arvalid;
  assign axi_arready = lite_arready;
  assign lite_araddr = axi_araddr;
  assign axi_rvalid = lite_rvalid;
  assign lite_rready = axi_rready;
  assign axi_rdata = lite_rdata;
  assign axi_rresp = lite_rresp;
  assign axi_rid = read_id;
  assign axi_rlast = 1'b1;

  assign lite_awvalid = axi_awvalid;
  assign axi_awready = lite_awready;
  assign lite_awaddr = axi_awaddr;
  assign lite_wvalid = axi_wvalid;
  assign axi_wready = lite_wready;
  assign lite_wdata = axi_wdata;
  assign lite_wstrb = axi_wstrb;
  assign axi_bvalid = lite_bvalid;
  assign lite_bready = axi_bready;
  assign axi_bresp = lite_bresp;
  assign axi_bid = write_id;

  always_ff @(posedge clock) begin
    if (reset) begin
      read_id <= '0;
      write_id <= '0;
      protocol_error <= 1'b0;
    end else begin
      if (axi_arvalid && axi_arready) begin
        read_id <= axi_arid;
        if (axi_arlen != 0 || axi_arsize != 3'd2 || axi_arburst != 2'b01)
          protocol_error <= 1'b1;
      end
      if (axi_awvalid && axi_awready) begin
        write_id <= axi_awid;
        if (axi_awlen != 0 || axi_awsize != 3'd2 || axi_awburst != 2'b01)
          protocol_error <= 1'b1;
      end
      if (axi_wvalid && axi_wready && !axi_wlast) protocol_error <= 1'b1;
    end
  end

endmodule
