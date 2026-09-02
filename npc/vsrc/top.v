module top (
  input  wire        clock,
  input  wire        reset,
  output reg  [63:0] cycle_count
);

  always @(posedge clock) begin
    if (reset) begin
      cycle_count <= 64'd0;
    end else begin
      cycle_count <= cycle_count + 64'd1;
    end
  end

endmodule
