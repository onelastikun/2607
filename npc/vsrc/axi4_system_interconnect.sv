// NPC 系统互联封装：把当前 CPU 主设备接入可复用的 4x4 AXI4 互联，
// 下游连接主存、MMIO 和两个错误从设备。READ/WRITE_DELAY 仅用于延迟回归。
module axi4_system_interconnect #(
  parameter int READ_DELAY = 0,
  parameter int WRITE_DELAY = 0
) (
  input  logic        clock,
  input  logic        reset,
  input  logic        arvalid,
  output logic        arready,
  input  logic [31:0] araddr,
  input  logic [3:0]  arid,
  input  logic [7:0]  arlen,
  input  logic [2:0]  arsize,
  input  logic [1:0]  arburst,
  output logic        rvalid,
  input  logic        rready,
  output logic [31:0] rdata,
  output logic [1:0]  rresp,
  output logic [3:0]  rid,
  output logic        rlast,
  input  logic        awvalid,
  output logic        awready,
  input  logic [31:0] awaddr,
  input  logic [3:0]  awid,
  input  logic [7:0]  awlen,
  input  logic [2:0]  awsize,
  input  logic [1:0]  awburst,
  input  logic        wvalid,
  output logic        wready,
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  input  logic        wlast,
  output logic        bvalid,
  input  logic        bready,
  output logic [1:0]  bresp,
  output logic [3:0]  bid,
  output logic        bus_error
);

  // 上游 ID 为 4 位；互联追加 2 位主设备编号后，下游 ID 为 6 位。
  localparam int MID_WIDTH = 4;
  localparam int SID_WIDTH = 6;

  // m_* 是互联的 4 路主设备侧打包信号，每一路占固定切片。
  logic [3:0] m_arvalid;
  logic [3:0] m_arready;
  logic [127:0] m_araddr;
  logic [15:0] m_arid;
  logic [31:0] m_arlen;
  logic [11:0] m_arsize;
  logic [7:0] m_arburst;
  logic [3:0] m_rvalid;
  logic [3:0] m_rready;
  logic [127:0] m_rdata;
  logic [7:0] m_rresp;
  logic [15:0] m_rid;
  logic [3:0] m_rlast;
  logic [3:0] m_awvalid;
  logic [3:0] m_awready;
  logic [127:0] m_awaddr;
  logic [15:0] m_awid;
  logic [31:0] m_awlen;
  logic [11:0] m_awsize;
  logic [7:0] m_awburst;
  logic [3:0] m_wvalid;
  logic [3:0] m_wready;
  logic [127:0] m_wdata;
  logic [15:0] m_wstrb;
  logic [3:0] m_wlast;
  logic [3:0] m_bvalid;
  logic [3:0] m_bready;
  logic [7:0] m_bresp;
  logic [15:0] m_bid;

  // s_* 是互联的 4 路从设备侧打包信号。
  logic [3:0] s_arvalid;
  logic [3:0] s_arready;
  logic [127:0] s_araddr;
  logic [23:0] s_arid;
  logic [31:0] s_arlen;
  logic [11:0] s_arsize;
  logic [7:0] s_arburst;
  logic [3:0] s_rvalid;
  logic [3:0] s_rready;
  logic [127:0] s_rdata;
  logic [7:0] s_rresp;
  logic [23:0] s_rid;
  logic [3:0] s_rlast;
  logic [3:0] s_awvalid;
  logic [3:0] s_awready;
  logic [127:0] s_awaddr;
  logic [23:0] s_awid;
  logic [31:0] s_awlen;
  logic [11:0] s_awsize;
  logic [7:0] s_awburst;
  logic [3:0] s_wvalid;
  logic [3:0] s_wready;
  logic [127:0] s_wdata;
  logic [15:0] s_wstrb;
  logic [3:0] s_wlast;
  logic [3:0] s_bvalid;
  logic [3:0] s_bready;
  logic [7:0] s_bresp;
  logic [23:0] s_bid;
  logic [1:0] target_protocol_error;
  logic inactive_master_activity;

  // “接入 SoC”前只有主设备槽 0 连接 CPU，其余三路固定为空闲。
  // 把单路端口装入打包总线的最低切片，响应也只从最低切片取回。
  assign m_arvalid = {3'd0, arvalid};
  assign m_araddr = {96'd0, araddr};
  assign m_arid = {12'd0, arid};
  assign m_arlen = {24'd0, arlen};
  assign m_arsize = {9'd0, arsize};
  assign m_arburst = {6'd0, arburst};
  assign arready = m_arready[0];
  assign rvalid = m_rvalid[0];
  assign m_rready = {3'd0, rready};
  assign rdata = m_rdata[31:0];
  assign rresp = m_rresp[1:0];
  assign rid = m_rid[3:0];
  assign rlast = m_rlast[0];

  assign m_awvalid = {3'd0, awvalid};
  assign m_awaddr = {96'd0, awaddr};
  assign m_awid = {12'd0, awid};
  assign m_awlen = {24'd0, awlen};
  assign m_awsize = {9'd0, awsize};
  assign m_awburst = {6'd0, awburst};
  assign awready = m_awready[0];
  assign m_wvalid = {3'd0, wvalid};
  assign m_wdata = {96'd0, wdata};
  assign m_wstrb = {12'd0, wstrb};
  assign m_wlast = {3'd0, wlast};
  assign wready = m_wready[0];
  assign bvalid = m_bvalid[0];
  assign m_bready = {3'd0, bready};
  assign bresp = m_bresp[1:0];
  assign bid = m_bid[3:0];
  // 空闲主设备槽理论上不应收到任何响应；出现活动说明互联路由发生错误。
  assign inactive_master_activity =
      (|m_arready[3:1]) || (|m_rvalid[3:1]) || (|m_rdata[127:32]) ||
      (|m_rresp[7:2]) || (|m_rid[15:4]) || (|m_rlast[3:1]) ||
      (|m_awready[3:1]) || (|m_wready[3:1]) || (|m_bvalid[3:1]) ||
      (|m_bresp[7:2]) || (|m_bid[15:4]);
  // 从设备协议错误和空闲槽异常统一上报给顶层，但保留独立来源便于定位。
  assign bus_error = (|target_protocol_error) || inactive_master_activity;

  // 纯互联模块只负责译码、仲裁和 ID 路由，不包含具体存储器行为。
  axi4_interconnect_4x4 #(
    .MID_WIDTH(MID_WIDTH), .SID_WIDTH(SID_WIDTH)
  ) u_crossbar (
    .clock(clock), .reset(reset),
    .m_arvalid(m_arvalid), .m_arready(m_arready), .m_araddr(m_araddr),
    .m_arid(m_arid), .m_arlen(m_arlen), .m_arsize(m_arsize),
    .m_arburst(m_arburst), .m_rvalid(m_rvalid), .m_rready(m_rready),
    .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rid(m_rid), .m_rlast(m_rlast),
    .m_awvalid(m_awvalid), .m_awready(m_awready), .m_awaddr(m_awaddr),
    .m_awid(m_awid), .m_awlen(m_awlen), .m_awsize(m_awsize),
    .m_awburst(m_awburst), .m_wvalid(m_wvalid), .m_wready(m_wready),
    .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
    .m_bvalid(m_bvalid), .m_bready(m_bready), .m_bresp(m_bresp), .m_bid(m_bid),
    .s_arvalid(s_arvalid), .s_arready(s_arready), .s_araddr(s_araddr),
    .s_arid(s_arid), .s_arlen(s_arlen), .s_arsize(s_arsize),
    .s_arburst(s_arburst), .s_rvalid(s_rvalid), .s_rready(s_rready),
    .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rid(s_rid), .s_rlast(s_rlast),
    .s_awvalid(s_awvalid), .s_awready(s_awready), .s_awaddr(s_awaddr),
    .s_awid(s_awid), .s_awlen(s_awlen), .s_awsize(s_awsize),
    .s_awburst(s_awburst), .s_wvalid(s_wvalid), .s_wready(s_wready),
    .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast),
    .s_bvalid(s_bvalid), .s_bready(s_bready), .s_bresp(s_bresp), .s_bid(s_bid)
  );

  genvar target;
  generate
    // 槽 0/1 分别承载主存和 MMIO。两者都通过 AXI4-to-Lite 适配器访问平台从设备。
    for (target = 0; target < 2; target = target + 1) begin : gen_real_target
      logic lite_arvalid;
      logic lite_arready;
      logic [31:0] lite_araddr;
      logic lite_rvalid;
      logic lite_rready;
      logic [31:0] lite_rdata;
      logic [1:0] lite_rresp;
      logic lite_awvalid;
      logic lite_awready;
      logic [31:0] lite_awaddr;
      logic lite_wvalid;
      logic lite_wready;
      logic [31:0] lite_wdata;
      logic [3:0] lite_wstrb;
      logic lite_bvalid;
      logic lite_bready;
      logic [1:0] lite_bresp;

      axi4_to_lite_slave #(.SID_WIDTH(SID_WIDTH)) u_adapter (
        .clock(clock), .reset(reset),
        .axi_arvalid(s_arvalid[target]), .axi_arready(s_arready[target]),
        .axi_araddr(s_araddr[target*32 +: 32]),
        .axi_arid(s_arid[target*SID_WIDTH +: SID_WIDTH]),
        .axi_arlen(s_arlen[target*8 +: 8]),
        .axi_arsize(s_arsize[target*3 +: 3]),
        .axi_arburst(s_arburst[target*2 +: 2]),
        .axi_rvalid(s_rvalid[target]), .axi_rready(s_rready[target]),
        .axi_rdata(s_rdata[target*32 +: 32]),
        .axi_rresp(s_rresp[target*2 +: 2]),
        .axi_rid(s_rid[target*SID_WIDTH +: SID_WIDTH]),
        .axi_rlast(s_rlast[target]),
        .axi_awvalid(s_awvalid[target]), .axi_awready(s_awready[target]),
        .axi_awaddr(s_awaddr[target*32 +: 32]),
        .axi_awid(s_awid[target*SID_WIDTH +: SID_WIDTH]),
        .axi_awlen(s_awlen[target*8 +: 8]),
        .axi_awsize(s_awsize[target*3 +: 3]),
        .axi_awburst(s_awburst[target*2 +: 2]),
        .axi_wvalid(s_wvalid[target]), .axi_wready(s_wready[target]),
        .axi_wdata(s_wdata[target*32 +: 32]),
        .axi_wstrb(s_wstrb[target*4 +: 4]), .axi_wlast(s_wlast[target]),
        .axi_bvalid(s_bvalid[target]), .axi_bready(s_bready[target]),
        .axi_bresp(s_bresp[target*2 +: 2]),
        .axi_bid(s_bid[target*SID_WIDTH +: SID_WIDTH]),
        .lite_arvalid(lite_arvalid), .lite_arready(lite_arready),
        .lite_araddr(lite_araddr), .lite_rvalid(lite_rvalid),
        .lite_rready(lite_rready), .lite_rdata(lite_rdata),
        .lite_rresp(lite_rresp), .lite_awvalid(lite_awvalid),
        .lite_awready(lite_awready), .lite_awaddr(lite_awaddr),
        .lite_wvalid(lite_wvalid), .lite_wready(lite_wready),
        .lite_wdata(lite_wdata), .lite_wstrb(lite_wstrb),
        .lite_bvalid(lite_bvalid), .lite_bready(lite_bready),
        .lite_bresp(lite_bresp), .protocol_error(target_protocol_error[target])
      );

      // 两个地址窗口最终共用 DPI-C 后端，由 C++ 再区分主存和具体 MMIO 地址。
      axi_lite_pmem #(
        .READ_DELAY(READ_DELAY), .WRITE_DELAY(WRITE_DELAY)
      ) u_target (
        .clock(clock), .reset(reset),
        .arvalid(lite_arvalid), .arready(lite_arready), .araddr(lite_araddr),
        .rvalid(lite_rvalid), .rready(lite_rready), .rdata(lite_rdata),
        .rresp(lite_rresp), .awvalid(lite_awvalid), .awready(lite_awready),
        .awaddr(lite_awaddr), .wvalid(lite_wvalid), .wready(lite_wready),
        .wdata(lite_wdata), .wstrb(lite_wstrb), .bvalid(lite_bvalid),
        .bready(lite_bready), .bresp(lite_bresp)
      );
    end

    // 槽 2 是保留扩展窗口，槽 3 是默认窗口；当前都明确返回错误。
    for (target = 2; target < 4; target = target + 1) begin : gen_error_target
      axi4_error_slave #(.SID_WIDTH(SID_WIDTH)) u_error (
        .clock(clock), .reset(reset),
        .arvalid(s_arvalid[target]), .arready(s_arready[target]),
        .araddr(s_araddr[target*32 +: 32]),
        .arid(s_arid[target*SID_WIDTH +: SID_WIDTH]),
        .arlen(s_arlen[target*8 +: 8]),
        .arsize(s_arsize[target*3 +: 3]),
        .arburst(s_arburst[target*2 +: 2]),
        .rvalid(s_rvalid[target]), .rready(s_rready[target]),
        .rdata(s_rdata[target*32 +: 32]),
        .rresp(s_rresp[target*2 +: 2]),
        .rid(s_rid[target*SID_WIDTH +: SID_WIDTH]), .rlast(s_rlast[target]),
        .awvalid(s_awvalid[target]), .awready(s_awready[target]),
        .awaddr(s_awaddr[target*32 +: 32]),
        .awid(s_awid[target*SID_WIDTH +: SID_WIDTH]),
        .awlen(s_awlen[target*8 +: 8]),
        .awsize(s_awsize[target*3 +: 3]),
        .awburst(s_awburst[target*2 +: 2]),
        .wvalid(s_wvalid[target]), .wready(s_wready[target]),
        .wdata(s_wdata[target*32 +: 32]),
        .wstrb(s_wstrb[target*4 +: 4]), .wlast(s_wlast[target]),
        .bvalid(s_bvalid[target]), .bready(s_bready[target]),
        .bresp(s_bresp[target*2 +: 2]),
        .bid(s_bid[target*SID_WIDTH +: SID_WIDTH])
      );
    end
  endgenerate

endmodule
