// 十六进制七段数码管译码器。
// segments[6:0] 对应七个笔段，segments[7] 为小数点；当前小数点始终关闭。
module hex7seg (
  input  logic [3:0] value,
  output logic [7:0] segments
);

  // 组合查找表把 4 位十六进制数转换为段码，不保存任何状态。
  always_comb begin
    case (value)
      4'h0: segments = 8'b0_0111111;
      4'h1: segments = 8'b0_0000110;
      4'h2: segments = 8'b0_1011011;
      4'h3: segments = 8'b0_1001111;
      4'h4: segments = 8'b0_1100110;
      4'h5: segments = 8'b0_1101101;
      4'h6: segments = 8'b0_1111101;
      4'h7: segments = 8'b0_0000111;
      4'h8: segments = 8'b0_1111111;
      4'h9: segments = 8'b0_1101111;
      4'ha: segments = 8'b0_1110111;
      4'hb: segments = 8'b0_1111100;
      4'hc: segments = 8'b0_0111001;
      4'hd: segments = 8'b0_1011110;
      4'he: segments = 8'b0_1111001;
      default: segments = 8'b0_1110001;
    endcase
  end

endmodule
