// NPC 的 SimpleBus 存储器/设备从端。
// 请求只发送一次，经过可配置等待周期后返回 respValid；实际数据由 DPI-C 平台模型提供。
module simple_bus_pmem #(
  parameter int READ_DELAY = 0,
  parameter int WRITE_DELAY = 0
) (
  input  logic        clock,
  input  logic        reset,

  input  logic        ifu_reqValid,
  input  logic [31:0] ifu_addr,
  output logic        ifu_respValid,
  output logic [31:0] ifu_rdata,

  input  logic        lsu_reqValid,
  input  logic [31:0] lsu_addr,
  input  logic [1:0]  lsu_size,
  input  logic        lsu_wen,
  input  logic [31:0] lsu_wdata,
  input  logic [3:0]  lsu_wmask,
  output logic        lsu_respValid,
  output logic [31:0] lsu_rdata,

  output logic        bus_error
);

  import "DPI-C" function int unsigned pmem_read(
    input int unsigned address,
    input byte unsigned length
  );
  import "DPI-C" function void pmem_write(
    input int unsigned address,
    input int unsigned data,
    input byte unsigned mask
  );

  localparam logic [31:0] PMEM_BASE = 32'h8000_0000;
  localparam logic [31:0] PMEM_END  = 32'h8800_0000;
  localparam logic [31:0] RTC_LOW   = 32'ha000_0048;
  localparam logic [31:0] RTC_HIGH  = 32'ha000_004c;
  localparam logic [31:0] SERIAL    = 32'ha000_03f8;

  logic ifu_pending;
  logic lsu_pending;
  integer ifu_wait;
  integer lsu_wait;
  logic [31:0] ifu_data_reg;
  logic [31:0] lsu_data_reg;
  logic ifu_error_reg;
  logic lsu_error_reg;
  logic [7:0] lsu_length;
  logic [4:0] lsu_shift;
  logic [31:0] aligned_lsu_addr;

  function automatic logic pmem_contains(
    input logic [31:0] address,
    input logic [7:0] length
  );
    logic [32:0] last_address;
    begin
      last_address = {1'b0, address} + {25'd0, length};
      pmem_contains = (address >= PMEM_BASE) && (last_address <= {1'b0, PMEM_END});
    end
  endfunction

  function automatic logic valid_data_address(
    input logic [31:0] address,
    input logic [7:0] length,
    input logic write_access
  );
    begin
      valid_data_address = pmem_contains(address, length) ||
                           (!write_access && (length == 8'd4) &&
                            ((address == RTC_LOW) || (address == RTC_HIGH))) ||
                           (write_access && (address == SERIAL));
    end
  endfunction

  always_comb begin
    case (lsu_size)
      2'd0: lsu_length = 8'd1;
      2'd1: lsu_length = 8'd2;
      2'd2: lsu_length = 8'd4;
      default: lsu_length = 8'd0;
    endcase
    lsu_shift = {lsu_addr[1:0], 3'b000};
    aligned_lsu_addr = {lsu_addr[31:2], 2'b00};

    ifu_respValid = ifu_pending && (ifu_wait == 0);
    lsu_respValid = lsu_pending && (lsu_wait == 0);
    ifu_rdata = ifu_data_reg;
    lsu_rdata = lsu_data_reg;
    bus_error = (ifu_respValid && ifu_error_reg) ||
                (lsu_respValid && lsu_error_reg);
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      ifu_pending <= 1'b0;
      lsu_pending <= 1'b0;
      ifu_wait <= 0;
      lsu_wait <= 0;
      ifu_data_reg <= 32'd0;
      lsu_data_reg <= 32'd0;
      ifu_error_reg <= 1'b0;
      lsu_error_reg <= 1'b0;
    end else begin
      if (!ifu_pending && ifu_reqValid) begin
        ifu_pending <= 1'b1;
        ifu_wait <= READ_DELAY;
        ifu_error_reg <= !pmem_contains(ifu_addr, 8'd4);
        ifu_data_reg <= pmem_contains(ifu_addr, 8'd4)
                      ? pmem_read(ifu_addr, 8'd4) : 32'd0;
      end else if (ifu_pending) begin
        if (ifu_wait != 0) ifu_wait <= ifu_wait - 1;
        else ifu_pending <= 1'b0;
      end

      if (!lsu_pending && lsu_reqValid) begin
        lsu_pending <= 1'b1;
        lsu_wait <= lsu_wen ? WRITE_DELAY : READ_DELAY;
        lsu_error_reg <= (lsu_length == 0) ||
                         !valid_data_address(lsu_addr, lsu_length, lsu_wen);
        if (!lsu_wen && (lsu_length != 0) &&
            valid_data_address(lsu_addr, lsu_length, 1'b0)) begin
          // SimpleBus 返回标准 32 位 byte lane，主设备再把目标字节移回低位。
          lsu_data_reg <= pmem_read(lsu_addr, lsu_length) << lsu_shift;
        end else begin
          lsu_data_reg <= 32'd0;
        end
        if (lsu_wen && (lsu_length != 0) &&
            valid_data_address(lsu_addr, lsu_length, 1'b1)) begin
          pmem_write(aligned_lsu_addr, lsu_wdata, {4'd0, lsu_wmask});
        end
      end else if (lsu_pending) begin
        if (lsu_wait != 0) lsu_wait <= lsu_wait - 1;
        else lsu_pending <= 1'b0;
      end
    end
  end

endmodule
