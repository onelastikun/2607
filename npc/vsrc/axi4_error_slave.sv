// Default target: accepts single-beat traffic and returns an error response.
module axi4_error_slave #(
  parameter int SID_WIDTH = 6
) (
  input  logic                 clock,
  input  logic                 reset,
  input  logic                 arvalid,
  output logic                 arready,
  input  logic [31:0]          araddr,
  input  logic [SID_WIDTH-1:0] arid,
  input  logic [7:0]           arlen,
  input  logic [2:0]           arsize,
  input  logic [1:0]           arburst,
  output logic                 rvalid,
  input  logic                 rready,
  output logic [31:0]          rdata,
  output logic [1:0]           rresp,
  output logic [SID_WIDTH-1:0] rid,
  output logic                 rlast,
  input  logic                 awvalid,
  output logic                 awready,
  input  logic [31:0]          awaddr,
  input  logic [SID_WIDTH-1:0] awid,
  input  logic [7:0]           awlen,
  input  logic [2:0]           awsize,
  input  logic [1:0]           awburst,
  input  logic                 wvalid,
  output logic                 wready,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0]          wdata,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [3:0]           wstrb,
  input  logic                 wlast,
  output logic                 bvalid,
  input  logic                 bready,
  output logic [1:0]           bresp,
  output logic [SID_WIDTH-1:0] bid
);

  logic aw_seen;
  logic w_seen;
  logic [SID_WIDTH-1:0] pending_awid;
  logic write_protocol_ok;

  assign arready = !rvalid;
  assign rresp = (arlen == 0 && arsize == 3'd2 && arburst == 2'b01)
               ? 2'b11 : 2'b10;
  assign rlast = 1'b1;
  assign awready = !aw_seen && !bvalid;
  assign wready = !w_seen && !bvalid;
  assign write_protocol_ok = awlen == 0 && awsize == 3'd2 &&
                             awburst == 2'b01 && awaddr != 32'd0 &&
                             awaddr[1:0] == 0 && wlast && (|wstrb);
  assign bresp = write_protocol_ok ? 2'b11 : 2'b10;

  always_ff @(posedge clock) begin
    if (reset) begin
      rvalid <= 1'b0;
      rdata <= 32'd0;
      rid <= '0;
      aw_seen <= 1'b0;
      w_seen <= 1'b0;
      pending_awid <= '0;
      bvalid <= 1'b0;
      bid <= '0;
    end else begin
      if (rvalid && rready) rvalid <= 1'b0;
      if (arvalid && arready) begin
        rdata <= araddr;
        rid <= arid;
        rvalid <= 1'b1;
      end

      if (bvalid && bready) bvalid <= 1'b0;
      if (awvalid && awready) begin
        aw_seen <= 1'b1;
        pending_awid <= awid;
      end
      if (wvalid && wready) w_seen <= 1'b1;
      if (!bvalid && (aw_seen || (awvalid && awready)) &&
          (w_seen || (wvalid && wready))) begin
        bid <= aw_seen ? pending_awid : awid;
        bvalid <= 1'b1;
        aw_seen <= 1'b0;
        w_seen <= 1'b0;
      end
    end
  end

endmodule
