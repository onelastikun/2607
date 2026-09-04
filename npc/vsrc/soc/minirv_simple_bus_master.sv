// 将 MiniRV 核心的简单取指/访存端口连接到 ysyxSoC SimpleBus 接口。
// SimpleBus 没有 ready：请求脉冲发出后，主设备保持内部状态并等待 respValid。
module minirv_simple_bus_master (
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

  output logic        io_ifu_reqValid,
  output logic [31:0] io_ifu_addr,
  input  logic        io_ifu_respValid,
  input  logic [31:0] io_ifu_rdata,
  output logic        io_lsu_reqValid,
  output logic [31:0] io_lsu_addr,
  output logic [1:0]  io_lsu_size,
  output logic        io_lsu_wen,
  output logic [31:0] io_lsu_wdata,
  output logic [3:0]  io_lsu_wmask,
  input  logic        io_lsu_respValid,
  input  logic [31:0] io_lsu_rdata
);

  typedef enum logic [2:0] {
    FETCH_REQ, FETCH_RESP, LOAD_REQ, LOAD_RESP, STORE_REQ, STORE_RESP
  } State;

  State state;
  logic [31:0] inst_reg;
  logic [4:0] byte_shift;

  assign byte_shift = {core_dmem_addr[1:0], 3'b000};

  // 取指响应当拍直接译码；访存指令随后锁存在 inst_reg 中等待 LSU 响应。
  assign core_inst = ((state == FETCH_RESP) && io_ifu_respValid)
                   ? io_ifu_rdata : inst_reg;
  // AXI/APB 数据按地址低位放在对应字节通道，核心侧则统一从低位取数。
  assign core_dmem_rdata = ((state == LOAD_RESP) && io_lsu_respValid)
                         ? (io_lsu_rdata >> byte_shift) : 32'd0;

  always_comb begin
    io_ifu_reqValid = 1'b0;
    io_ifu_addr = core_pc;
    io_lsu_reqValid = 1'b0;
    io_lsu_addr = core_dmem_addr;
    io_lsu_size = 2'd0;
    io_lsu_wen = core_dmem_write;
    // 写数据和掩码根据地址低两位移动到标准总线字节通道。
    io_lsu_wdata = core_dmem_wdata << byte_shift;
    io_lsu_wmask = core_dmem_wmask << core_dmem_addr[1:0];
    core_step = 1'b0;

    case (core_dmem_len)
      3'd1: io_lsu_size = 2'd0;
      3'd2: io_lsu_size = 2'd1;
      3'd4: io_lsu_size = 2'd2;
      default: io_lsu_size = 2'd0;
    endcase

    case (state)
      FETCH_REQ: io_ifu_reqValid = 1'b1;
      FETCH_RESP: begin
        // 普通指令在取指响应当拍提交；load/store 先进入 LSU 阶段。
        if (io_ifu_respValid && !core_dmem_read && !core_dmem_write)
          core_step = 1'b1;
      end
      LOAD_REQ: io_lsu_reqValid = 1'b1;
      LOAD_RESP: core_step = io_lsu_respValid;
      STORE_REQ: io_lsu_reqValid = 1'b1;
      STORE_RESP: core_step = io_lsu_respValid;
      default: ;
    endcase
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      state <= FETCH_REQ;
      inst_reg <= 32'h0000_0013;
    end else begin
      case (state)
        // 请求端口没有 ready；ysyxSoC 的 MemBridge 会在该拍锁存请求。
        FETCH_REQ: state <= FETCH_RESP;
        FETCH_RESP: if (io_ifu_respValid) begin
          inst_reg <= io_ifu_rdata;
          if (core_dmem_read) state <= LOAD_REQ;
          else if (core_dmem_write) state <= STORE_REQ;
          else state <= FETCH_REQ;
        end
        LOAD_REQ: state <= LOAD_RESP;
        LOAD_RESP: if (io_lsu_respValid) state <= FETCH_REQ;
        STORE_REQ: state <= STORE_RESP;
        STORE_RESP: if (io_lsu_respValid) state <= FETCH_REQ;
        default: state <= FETCH_REQ;
      endcase
    end
  end

endmodule
