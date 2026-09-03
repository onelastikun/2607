// 将互联的一路单拍 AXI4 从端口适配到 AXI4-Lite 从设备。
// 适配器保存请求 ID，Lite 从设备返回响应时再恢复 RID/BID。
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

  // Lite 没有 ID 字段，因此必须在地址握手时锁存 AXI4 ID。
  logic [SID_WIDTH-1:0] read_id;
  logic [SID_WIDTH-1:0] write_id;

  // 五个 Lite 通道与 AXI4 单拍通道逐一透传，只有 ID/RLAST 由本模块补充。
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

  // 同时检查本阶段的裁剪约束：只接受 4 字节、INCR、LEN=0 的事务。
  // protocol_error 为粘滞错误，复位前保持有效，便于顶层可靠捕获。
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
