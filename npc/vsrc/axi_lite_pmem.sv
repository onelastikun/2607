// 连接 C++ 物理地址空间的 AXI4-Lite 从设备。
// 可配置读写延迟用于验证主设备会正确保持 valid、地址和数据直到握手完成。
module axi_lite_pmem #(
  parameter int READ_DELAY = 1,
  parameter int WRITE_DELAY = 1
) (
  input  logic        clock,
  input  logic        reset,
  input  logic        arvalid,
  output logic        arready,
  input  logic [31:0] araddr,
  output logic        rvalid,
  input  logic        rready,
  output logic [31:0] rdata,
  output logic [1:0]  rresp,
  input  logic        awvalid,
  output logic        awready,
  input  logic [31:0] awaddr,
  input  logic        wvalid,
  output logic        wready,
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  output logic        bvalid,
  input  logic        bready,
  output logic [1:0]  bresp
);

  // DPI-C 只存在于平台适配层；CPU 核心和总线协议逻辑都不直接调用 C++。
  import "DPI-C" function int unsigned pmem_read(
    input int unsigned addr,
    input byte unsigned len
  );
  import "DPI-C" function void pmem_write(
    input int unsigned addr,
    input int unsigned data,
    input byte unsigned mask
  );

  // 读通道一次只保存一个地址；rvalid 拉高后保持数据，直到主设备接受。
  logic read_pending;
  logic [31:0] read_addr;
  integer read_count;
  // 写地址和写数据可能先后到达，因此分别保存，再合并成一次写操作。
  logic aw_pending;
  logic [31:0] write_addr;
  logic w_pending;
  logic [31:0] write_data;
  logic [3:0] write_strb;
  integer write_count;
  logic write_wait;
  logic ar_hs;
  logic aw_hs;
  logic w_hs;

  // 有未完成响应时停止接收新事务，从结构上保证单 outstanding。
  assign arready = !read_pending && !rvalid;
  assign awready = !aw_pending && !write_wait && !bvalid;
  assign wready = !w_pending && !write_wait && !bvalid;
  assign rresp = 2'b00;
  assign bresp = 2'b00;
  assign ar_hs = arvalid && arready;
  assign aw_hs = awvalid && awready;
  assign w_hs = wvalid && wready;

  // 所有 ready/valid 对应的数据都在握手沿锁存，等待期间不会依赖上游变化。
  always_ff @(posedge clock) begin
    if (reset) begin
      read_pending <= 1'b0;
      read_addr <= 32'd0;
      read_count <= 0;
      rvalid <= 1'b0;
      rdata <= 32'd0;
      aw_pending <= 1'b0;
      write_addr <= 32'd0;
      w_pending <= 1'b0;
      write_data <= 32'd0;
      write_strb <= 4'd0;
      write_count <= 0;
      write_wait <= 1'b0;
      bvalid <= 1'b0;
    end else begin
      // R 通道握手后才能撤销 rvalid；随后才可接受下一次 AR。
      if (rvalid && rready) rvalid <= 1'b0;
      if (ar_hs) begin
        read_pending <= 1'b1;
        read_addr <= araddr;
        read_count <= READ_DELAY;
      end else if (read_pending) begin
        if (read_count == 0) begin
          rdata <= pmem_read(read_addr, 8'd4);
          rvalid <= 1'b1;
          read_pending <= 1'b0;
        end else read_count <= read_count - 1;
      end

      // AW 和 W 都到达后启动延迟计数，写入完成后才产生 B 响应。
      if (bvalid && bready) bvalid <= 1'b0;
      if (aw_hs) begin aw_pending <= 1'b1; write_addr <= awaddr; end
      if (w_hs) begin
        w_pending <= 1'b1;
        write_data <= wdata;
        write_strb <= wstrb;
      end

      if (!write_wait && !bvalid &&
          (aw_pending || aw_hs) && (w_pending || w_hs)) begin
        write_wait <= 1'b1;
        write_count <= WRITE_DELAY;
        aw_pending <= 1'b0;
        w_pending <= 1'b0;
        if (aw_hs) write_addr <= awaddr;
        if (w_hs) begin write_data <= wdata; write_strb <= wstrb; end
      end else if (write_wait) begin
        if (write_count == 0) begin
          pmem_write(write_addr, write_data, {4'd0, write_strb});
          bvalid <= 1'b1;
          write_wait <= 1'b0;
        end else write_count <= write_count - 1;
      end
    end
  end

endmodule
