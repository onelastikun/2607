// ysyxSoC 教学 GPIO 的 APB 从设备。
// 地址 0x0 控制 16 位 LED，0x4 读取 16 位开关，0x8 保存 8 个十六进制数位。
module mygpio_top_apb (
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);

  reg [15:0] output_reg;
  reg [31:0] digits_reg;
  reg [31:0] read_data;

  wire transfer = in_psel && in_penable;
  wire write_transfer = transfer && in_pwrite;

  // 本设备无等待周期；PREADY 只在 APB access 阶段有效。
  assign in_pready = transfer;
  assign in_pslverr = 1'b0;
  assign in_prdata = read_data;
  assign gpio_out = output_reg;

  // 低 4 位地址足以区分 16 字节设备窗口中的三个寄存器。
  always @(*) begin
    read_data = 32'b0;
    case (in_paddr[3:2])
      2'd0: read_data = {16'b0, output_reg};
      2'd1: read_data = {16'b0, gpio_in};
      2'd2: read_data = digits_reg;
      default: read_data = 32'b0;
    endcase
  end

  // 写掩码逐字节生效，复位后 LED 和数码管全部熄灭/显示 0。
  always @(posedge clock) begin
    if (reset) begin
      output_reg <= 16'b0;
      digits_reg <= 32'b0;
    end else if (write_transfer) begin
      case (in_paddr[3:2])
        2'd0: begin
          if (in_pstrb[0]) output_reg[7:0] <= in_pwdata[7:0];
          if (in_pstrb[1]) output_reg[15:8] <= in_pwdata[15:8];
        end
        2'd2: begin
          if (in_pstrb[0]) digits_reg[7:0] <= in_pwdata[7:0];
          if (in_pstrb[1]) digits_reg[15:8] <= in_pwdata[15:8];
          if (in_pstrb[2]) digits_reg[23:16] <= in_pwdata[23:16];
          if (in_pstrb[3]) digits_reg[31:24] <= in_pwdata[31:24];
        end
        default: begin end
      endcase
    end
  end

  // 每个数位独立译码，段码 bit[6:0] 对应 g~a，bit[7] 为关闭的小数点。
  function [7:0] hex_to_segments;
    input [3:0] digit;
    begin
      case (digit)
        4'h0: hex_to_segments = 8'b0_0111111;
        4'h1: hex_to_segments = 8'b0_0000110;
        4'h2: hex_to_segments = 8'b0_1011011;
        4'h3: hex_to_segments = 8'b0_1001111;
        4'h4: hex_to_segments = 8'b0_1100110;
        4'h5: hex_to_segments = 8'b0_1101101;
        4'h6: hex_to_segments = 8'b0_1111101;
        4'h7: hex_to_segments = 8'b0_0000111;
        4'h8: hex_to_segments = 8'b0_1111111;
        4'h9: hex_to_segments = 8'b0_1101111;
        4'ha: hex_to_segments = 8'b0_1110111;
        4'hb: hex_to_segments = 8'b0_1111100;
        4'hc: hex_to_segments = 8'b0_0111001;
        4'hd: hex_to_segments = 8'b0_1011110;
        4'he: hex_to_segments = 8'b0_1111001;
        default: hex_to_segments = 8'b0_1110001;
      endcase
    end
  endfunction

  assign gpio_seg_0 = hex_to_segments(digits_reg[3:0]);
  assign gpio_seg_1 = hex_to_segments(digits_reg[7:4]);
  assign gpio_seg_2 = hex_to_segments(digits_reg[11:8]);
  assign gpio_seg_3 = hex_to_segments(digits_reg[15:12]);
  assign gpio_seg_4 = hex_to_segments(digits_reg[19:16]);
  assign gpio_seg_5 = hex_to_segments(digits_reg[23:20]);
  assign gpio_seg_6 = hex_to_segments(digits_reg[27:24]);
  assign gpio_seg_7 = hex_to_segments(digits_reg[31:28]);

  // 保护口当前未参与访问权限控制，保留端口以匹配 ysyxSoC 框架接口。
  wire unused_in_pprot = &{1'b0, in_pprot};

endmodule
