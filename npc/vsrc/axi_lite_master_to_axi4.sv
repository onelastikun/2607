// 将单拍 AXI4-Lite 主设备适配到带 ID 和突发字段的 AXI4 接口。
// 数据通道直接透传，只补充本项目固定使用的单拍事务元数据。
module axi_lite_master_to_axi4 #(
  parameter logic [3:0] READ_ID = 4'd0,
  parameter logic [3:0] WRITE_ID = 4'd1
) (
  input  logic        lite_arvalid,
  output logic        lite_arready,
  input  logic [31:0] lite_araddr,
  output logic        lite_rvalid,
  input  logic        lite_rready,
  output logic [31:0] lite_rdata,
  output logic [1:0]  lite_rresp,
  input  logic        lite_awvalid,
  output logic        lite_awready,
  input  logic [31:0] lite_awaddr,
  input  logic        lite_wvalid,
  output logic        lite_wready,
  input  logic [31:0] lite_wdata,
  input  logic [3:0]  lite_wstrb,
  output logic        lite_bvalid,
  input  logic        lite_bready,
  output logic [1:0]  lite_bresp,

  output logic        axi_arvalid,
  input  logic        axi_arready,
  output logic [31:0] axi_araddr,
  output logic [3:0]  axi_arid,
  output logic [7:0]  axi_arlen,
  output logic [2:0]  axi_arsize,
  output logic [1:0]  axi_arburst,
  input  logic        axi_rvalid,
  output logic        axi_rready,
  input  logic [31:0] axi_rdata,
  input  logic [1:0]  axi_rresp,
  input  logic [3:0]  axi_rid,
  input  logic        axi_rlast,
  output logic        axi_awvalid,
  input  logic        axi_awready,
  output logic [31:0] axi_awaddr,
  output logic [3:0]  axi_awid,
  output logic [7:0]  axi_awlen,
  output logic [2:0]  axi_awsize,
  output logic [1:0]  axi_awburst,
  output logic        axi_wvalid,
  input  logic        axi_wready,
  output logic [31:0] axi_wdata,
  output logic [3:0]  axi_wstrb,
  output logic        axi_wlast,
  input  logic        axi_bvalid,
  output logic        axi_bready,
  input  logic [1:0]  axi_bresp,
  input  logic [3:0]  axi_bid,
  output logic        protocol_error
);

  // 读事务固定为 LEN=0（单拍）、SIZE=2（每拍 4 字节）、INCR 类型。
  assign axi_arvalid = lite_arvalid;
  assign lite_arready = axi_arready;
  assign axi_araddr = lite_araddr;
  assign axi_arid = READ_ID;
  assign axi_arlen = 8'd0;
  assign axi_arsize = 3'd2;
  assign axi_arburst = 2'b01;
  assign lite_rvalid = axi_rvalid;
  assign axi_rready = lite_rready;
  assign lite_rdata = axi_rdata;
  assign lite_rresp = axi_rresp;

  // 写事务同样是单拍；因此 WLAST 恒为 1。
  assign axi_awvalid = lite_awvalid;
  assign lite_awready = axi_awready;
  assign axi_awaddr = lite_awaddr;
  assign axi_awid = WRITE_ID;
  assign axi_awlen = 8'd0;
  assign axi_awsize = 3'd2;
  assign axi_awburst = 2'b01;
  assign axi_wvalid = lite_wvalid;
  assign lite_wready = axi_wready;
  assign axi_wdata = lite_wdata;
  assign axi_wstrb = lite_wstrb;
  assign axi_wlast = 1'b1;
  assign lite_bvalid = axi_bvalid;
  assign axi_bready = lite_bready;
  assign lite_bresp = axi_bresp;

  // Lite 主设备一次只有一个事务，因此返回 ID 必须等于固定请求 ID，
  // 且唯一的读数据拍必须同时带 RLAST。违反这些约束表示互联或从设备出错。
  assign protocol_error =
      (axi_rvalid && (axi_rid != READ_ID || !axi_rlast)) ||
      (axi_bvalid && (axi_bid != WRITE_ID));

endmodule
