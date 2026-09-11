// E8 门级仿真的外部存储器模型。
// 正式 NPC 从 0x30000000 复位，这里提供两条 MiniRV 启动指令跳到 0x80000000，
// 随后的主存访问通过 DPI-C（Verilator）或 VPI（Icarus）完成。
module netlist_bus_pmem (
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
  output logic        test_passed,
  output logic        test_failed
);

`ifndef __ICARUS__
  import "DPI-C" function int unsigned pmem_read(
    input int unsigned address,
    input byte unsigned length
  );
  import "DPI-C" function void pmem_write(
    input int unsigned address,
    input int unsigned data,
    input byte unsigned mask
  );
`endif

  localparam logic [31:0] PMEM_BASE = 32'h8000_0000;
  localparam logic [31:0] PMEM_END  = 32'h8800_0000;
  localparam logic [31:0] EXIT_ADDR = 32'ha000_0000;
  localparam logic [31:0] PASS_CODE = 32'h0000_600d;

  logic ifu_pending;
  logic lsu_pending;
  // 门级 Verilator 仿真中，标准单元 DFF 与外部 RTL 同时在上升沿求值；
  // 响应保持多个周期，避免响应产生和撤销与 DFF 采样发生竞态。
  logic [1:0] ifu_wait;
  logic [1:0] lsu_wait;
  logic [31:0] ifu_data_reg;
  logic [31:0] lsu_data_reg;
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
      pmem_contains = (address >= PMEM_BASE) &&
                      (last_address <= {1'b0, PMEM_END});
    end
  endfunction

  function automatic logic [31:0] boot_instruction(input logic [31:0] address);
    begin
      case (address)
        32'h3000_0000: boot_instruction = 32'h8000_00b7;  // lui x1, 0x80000
        32'h3000_0004: boot_instruction = 32'h0000_8067;  // jalr x0, 0(x1)
        default:       boot_instruction = 32'h0010_0073;  // 非法启动流尽快结束
      endcase
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
    // wait=1/0 时保持响应，直到 CPU 至少完整采样一次。
    ifu_respValid = ifu_pending && (ifu_wait <= 2'd1);
    lsu_respValid = lsu_pending && (lsu_wait <= 2'd1);
    ifu_rdata = ifu_data_reg;
    lsu_rdata = lsu_data_reg;
  end

`ifdef __ICARUS__
  always @(posedge clock) begin
`else
  always_ff @(posedge clock) begin
`endif
    if (reset) begin
      ifu_pending <= 1'b0;
      lsu_pending <= 1'b0;
      ifu_wait <= 2'd0;
      lsu_wait <= 2'd0;
      ifu_data_reg <= 32'd0;
      lsu_data_reg <= 32'd0;
      test_passed <= 1'b0;
      test_failed <= 1'b0;
    end else begin
      // IFU 响应至少保持到一个完整上升沿之后；在响应完成的同一拍
      // 可以接收下一次请求，适配无 ready 信号的 SimpleBus。
      if (ifu_pending) begin
        if (ifu_wait != 0) begin
          ifu_wait <= ifu_wait - 1'b1;
        end else if (ifu_reqValid) begin
          ifu_wait <= 2'd2;
          if ((ifu_addr >= 32'h3000_0000) && (ifu_addr < 32'h3000_000c)) begin
            ifu_data_reg <= boot_instruction(ifu_addr);
          end else if (pmem_contains(ifu_addr, 8'd4)) begin
`ifdef __ICARUS__
            $pmem_read(ifu_addr, 8'd4, ifu_data_reg);
`else
            ifu_data_reg <= pmem_read(ifu_addr, 8'd4);
`endif
          end else begin
            ifu_data_reg <= 32'h0010_0073;
            test_failed <= 1'b1;
          end
        end else begin
          ifu_pending <= 1'b0;
        end
      end else if (ifu_reqValid) begin
        ifu_pending <= 1'b1;
        ifu_wait <= 2'd2;
        if ((ifu_addr >= 32'h3000_0000) && (ifu_addr < 32'h3000_000c)) begin
          ifu_data_reg <= boot_instruction(ifu_addr);
        end else if (pmem_contains(ifu_addr, 8'd4)) begin
`ifdef __ICARUS__
          $pmem_read(ifu_addr, 8'd4, ifu_data_reg);
`else
          ifu_data_reg <= pmem_read(ifu_addr, 8'd4);
`endif
        end else begin
          ifu_data_reg <= 32'h0010_0073;
          test_failed <= 1'b1;
        end
      end

      // LSU 与 IFU 使用相同的响应保持策略。
      if (lsu_pending) begin
        if (lsu_wait != 0) begin
          lsu_wait <= lsu_wait - 1'b1;
        end else if (lsu_reqValid) begin
          lsu_wait <= 2'd2;
          lsu_data_reg <= 32'd0;
          if (lsu_wen && (lsu_addr == EXIT_ADDR)) begin
            if (lsu_wdata == PASS_CODE)
              test_passed <= 1'b1;
            else
              test_failed <= 1'b1;
          end else if ((lsu_length == 0) ||
                       !pmem_contains(lsu_addr, lsu_length)) begin
            test_failed <= 1'b1;
          end else if (lsu_wen) begin
`ifdef __ICARUS__
            $pmem_write(aligned_lsu_addr, lsu_wdata, {4'd0, lsu_wmask});
`else
            pmem_write(aligned_lsu_addr, lsu_wdata, {4'd0, lsu_wmask});
`endif
          end else begin
`ifdef __ICARUS__
            $pmem_read(lsu_addr, lsu_length, lsu_data_reg);
            lsu_data_reg = lsu_data_reg << lsu_shift;
`else
            lsu_data_reg <= pmem_read(lsu_addr, lsu_length) << lsu_shift;
`endif
          end
        end else begin
          lsu_pending <= 1'b0;
        end
      end else if (lsu_reqValid) begin
        lsu_pending <= 1'b1;
        lsu_wait <= 2'd2;
        lsu_data_reg <= 32'd0;
        if (lsu_wen && (lsu_addr == EXIT_ADDR)) begin
          if (lsu_wdata == PASS_CODE)
            test_passed <= 1'b1;
          else
            test_failed <= 1'b1;
        end else if ((lsu_length == 0) ||
                     !pmem_contains(lsu_addr, lsu_length)) begin
          test_failed <= 1'b1;
        end else if (lsu_wen) begin
`ifdef __ICARUS__
          $pmem_write(aligned_lsu_addr, lsu_wdata, {4'd0, lsu_wmask});
`else
          pmem_write(aligned_lsu_addr, lsu_wdata, {4'd0, lsu_wmask});
`endif
        end else begin
`ifdef __ICARUS__
          $pmem_read(lsu_addr, lsu_length, lsu_data_reg);
          lsu_data_reg = lsu_data_reg << lsu_shift;
`else
          lsu_data_reg <= pmem_read(lsu_addr, lsu_length) << lsu_shift;
`endif
        end
      end
    end
  end

endmodule
