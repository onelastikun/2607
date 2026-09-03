// 非流水 MiniRV 使用的串行 AXI4-Lite 主设备。
// 同一时刻只允许一个取指、load 或 store 事务；响应握手当周期直接提交以减少空闲周期。
module minirv_axi_lite_master (
  input  logic        clock,
  input  logic        reset,
  input  logic [31:0] core_pc,
  output logic [31:0] core_inst,
  input  logic        core_dmem_read,
  input  logic [2:0]  core_dmem_len,
  input  logic [31:0] core_dmem_addr,
  output logic [31:0] core_dmem_rdata,
  input  logic        core_dmem_write,
  input  logic [31:0] core_dmem_wdata,
  input  logic [3:0]  core_dmem_wmask,
  output logic        core_step,

  output logic        arvalid,
  input  logic        arready,
  output logic [31:0] araddr,
  input  logic        rvalid,
  output logic        rready,
  input  logic [31:0] rdata,
  input  logic [1:0]  rresp,

  output logic        awvalid,
  input  logic        awready,
  output logic [31:0] awaddr,
  output logic        wvalid,
  input  logic        wready,
  output logic [31:0] wdata,
  output logic [3:0]  wstrb,
  input  logic        bvalid,
  output logic        bready,
  input  logic [1:0]  bresp,

  output logic        bus_error
);

  // 状态机把一次指令执行拆成取指，以及可选的数据读写阶段。
  // AXI 读地址/读数据和写地址/写数据/写响应均使用独立握手。
  typedef enum logic [2:0] {
    FETCH_ADDR, FETCH_DATA, LOAD_ADDR, LOAD_DATA, STORE_SEND, STORE_RESP
  } State;

  State state;
  logic [31:0] inst_reg;
  // AXI 允许 AW 与 W 独立握手，分别记录完成状态后才能等待 B 响应。
  logic aw_done;
  logic w_done;
  logic aw_handshake;
  logic w_handshake;
  logic fetch_response;
  logic load_response;
  logic store_response;
  logic response_error;
  logic bus_error_latched;

  // valid && ready 表示当前拍完成一次传输。
  assign aw_handshake = awvalid && awready;
  assign w_handshake = wvalid && wready;
  assign fetch_response = (state == FETCH_DATA) && rvalid && rready;
  assign load_response = (state == LOAD_DATA) && rvalid && rready;
  assign store_response = (state == STORE_RESP) && bvalid && bready;
  assign response_error = ((fetch_response || load_response) &&
                           (rresp != 2'b00)) ||
                          (store_response && (bresp != 2'b00));
  // 在响应握手的当前拍组合输出错误，使运行时能报告发起故障访问的指令，
  // 而不是等到下一个时钟沿后把错误错误地归到后继指令。
  assign bus_error = bus_error_latched || response_error;

  // 取指响应到达时直接把 rdata 送给译码器；如果它是访存指令，
  // 再锁存到 inst_reg，保证后续数据事务等待期间指令内容保持不变。
  assign core_inst = fetch_response ? rdata : inst_reg;
  assign core_dmem_rdata = load_response ? rdata : 32'd0;

  // 组合块只根据当前状态驱动通道。默认全部无效可避免锁存器和意外请求。
  // valid 一旦在某状态拉高，会保持到对应 ready 握手为止。
  always_comb begin
    arvalid = 1'b0;
    araddr = 32'd0;
    rready = 1'b0;
    awvalid = 1'b0;
    awaddr = core_dmem_addr;
    wvalid = 1'b0;
    wdata = core_dmem_wdata;
    wstrb = core_dmem_wmask;
    bready = 1'b0;
    core_step = 1'b0;

    case (state)
      // 取指和 load 共用读通道，但地址来源不同。
      FETCH_ADDR: begin arvalid = 1'b1; araddr = core_pc; end
      FETCH_DATA: begin
        rready = 1'b1;
        if (rvalid && !core_dmem_read && !core_dmem_write) core_step = 1'b1;
      end
      LOAD_ADDR: begin arvalid = 1'b1; araddr = core_dmem_addr; end
      LOAD_DATA: begin rready = 1'b1; core_step = rvalid; end
      // AW/W 谁先握手就停止重发谁，尚未握手的通道继续保持 valid 和数据稳定。
      STORE_SEND: begin
        awvalid = !aw_done;
        wvalid = !w_done;
      end
      STORE_RESP: begin bready = 1'b1; core_step = bvalid; end
      default: ;
    endcase
  end

  // 时序块只保存事务进度、指令寄存器和粘滞错误状态。
  always_ff @(posedge clock) begin
    if (reset) begin
      state <= FETCH_ADDR;
      inst_reg <= 32'h0000_0013;
      aw_done <= 1'b0;
      w_done <= 1'b0;
      bus_error_latched <= 1'b0;
    end else begin
      if (response_error) bus_error_latched <= 1'b1;
      case (state)
        FETCH_ADDR: if (arvalid && arready) state <= FETCH_DATA;
        // 取指完成后，普通指令直接回到下一次取指；访存指令进入数据事务。
        FETCH_DATA: if (fetch_response) begin
          inst_reg <= rdata;
          if (core_dmem_read) begin
            if ((core_dmem_len != 3'd1) && (core_dmem_len != 3'd2) &&
                (core_dmem_len != 3'd4)) bus_error_latched <= 1'b1;
            state <= LOAD_ADDR;
          end else if (core_dmem_write) begin
            aw_done <= 1'b0;
            w_done <= 1'b0;
            state <= STORE_SEND;
          end else state <= FETCH_ADDR;
        end
        LOAD_ADDR: if (arvalid && arready) state <= LOAD_DATA;
        LOAD_DATA: if (load_response) begin
          state <= FETCH_ADDR;
        end
        // 必须确认 AW 和 W 都已完成，才能进入写响应阶段。
        STORE_SEND: begin
          if (aw_handshake) aw_done <= 1'b1;
          if (w_handshake) w_done <= 1'b1;
          if ((aw_done || aw_handshake) && (w_done || w_handshake)) begin
            state <= STORE_RESP;
          end
        end
        STORE_RESP: if (store_response) begin
          state <= FETCH_ADDR;
        end
        default: state <= FETCH_ADDR;
      endcase
    end
  end

endmodule
