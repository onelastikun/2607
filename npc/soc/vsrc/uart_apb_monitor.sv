// 旁路观察 16550 的 APB 寄存器写入，用于在宿主终端显示实际发送字符。
// 观察器不参与 ready/valid 或串口功能，只读取已经到达 UART 的 APB 事务。
module uart_apb_monitor (
  input logic        clock,
  input logic        reset,
  input logic        psel,
  input logic        penable,
  input logic        pwrite,
  input logic [28:0] paddr,
  input logic [31:0] pwdata,
  input logic [3:0]  pstrb
);

  import "DPI-C" function void soc_uart_write(input byte unsigned ch);

  logic dlab;
  logic [7:0] selected_byte;
  logic selected_strobe;

  always_comb begin
    selected_byte = pwdata >> {paddr[1:0], 3'b000};
    selected_strobe = pstrb[paddr[1:0]];
  end

  // uart_top_apb 在 APB setup 阶段产生内部 reg_we，因此观察相同条件。
  always_ff @(posedge clock) begin
    if (reset) begin
      dlab <= 1'b0;
    end else if (psel && !penable && pwrite && selected_strobe) begin
      if (paddr[2:0] == 3'd3) dlab <= selected_byte[7];
      // DLAB=0 时 offset 0 才是发送保持寄存器；DLAB=1 时它是除数低字节。
      if ((paddr[2:0] == 3'd0) && !dlab) soc_uart_write(selected_byte);
    end
  end

endmodule

bind APBUart16550 uart_apb_monitor u_uart_monitor (
  .clock(clock), .reset(reset),
  .psel(auto_apply_in_psel), .penable(auto_apply_in_penable),
  .pwrite(auto_apply_in_pwrite), .paddr(auto_apply_in_paddr),
  .pwdata(auto_apply_in_pwdata), .pstrb(auto_apply_in_pstrb)
);
