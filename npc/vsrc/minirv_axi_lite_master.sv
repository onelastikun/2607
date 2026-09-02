// Serial AXI4-Lite master for a non-pipelined MiniRV core.
// Responses commit directly on their handshake cycle to avoid idle states.
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

  typedef enum logic [2:0] {
    FETCH_ADDR, FETCH_DATA, LOAD_ADDR, LOAD_DATA, STORE_SEND, STORE_RESP
  } State;

  State state;
  logic [31:0] inst_reg;
  logic aw_done;
  logic w_done;
  logic aw_handshake;
  logic w_handshake;
  logic fetch_response;
  logic load_response;
  logic store_response;

  assign aw_handshake = awvalid && awready;
  assign w_handshake = wvalid && wready;
  assign fetch_response = (state == FETCH_DATA) && rvalid && rready;
  assign load_response = (state == LOAD_DATA) && rvalid && rready;
  assign store_response = (state == STORE_RESP) && bvalid && bready;

  // During a fetch response the decoder sees bus data immediately. Memory
  // instructions are then held in inst_reg until their data transaction ends.
  assign core_inst = fetch_response ? rdata : inst_reg;
  assign core_dmem_rdata = load_response ? rdata : 32'd0;

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
      FETCH_ADDR: begin arvalid = 1'b1; araddr = core_pc; end
      FETCH_DATA: begin
        rready = 1'b1;
        if (rvalid && !core_dmem_read && !core_dmem_write) core_step = 1'b1;
      end
      LOAD_ADDR: begin arvalid = 1'b1; araddr = core_dmem_addr; end
      LOAD_DATA: begin rready = 1'b1; core_step = rvalid; end
      STORE_SEND: begin
        awvalid = !aw_done;
        wvalid = !w_done;
      end
      STORE_RESP: begin bready = 1'b1; core_step = bvalid; end
      default: ;
    endcase
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      state <= FETCH_ADDR;
      inst_reg <= 32'h0000_0013;
      aw_done <= 1'b0;
      w_done <= 1'b0;
      bus_error <= 1'b0;
    end else begin
      case (state)
        FETCH_ADDR: if (arvalid && arready) state <= FETCH_DATA;
        FETCH_DATA: if (fetch_response) begin
          inst_reg <= rdata;
          bus_error <= bus_error || (rresp != 2'b00);
          if (core_dmem_read) begin
            if ((core_dmem_len != 3'd1) && (core_dmem_len != 3'd2) &&
                (core_dmem_len != 3'd4)) bus_error <= 1'b1;
            state <= LOAD_ADDR;
          end else if (core_dmem_write) begin
            aw_done <= 1'b0;
            w_done <= 1'b0;
            state <= STORE_SEND;
          end else state <= FETCH_ADDR;
        end
        LOAD_ADDR: if (arvalid && arready) state <= LOAD_DATA;
        LOAD_DATA: if (load_response) begin
          bus_error <= bus_error || (rresp != 2'b00);
          state <= FETCH_ADDR;
        end
        STORE_SEND: begin
          if (aw_handshake) aw_done <= 1'b1;
          if (w_handshake) w_done <= 1'b1;
          if ((aw_done || aw_handshake) && (w_done || w_handshake)) begin
            state <= STORE_RESP;
          end
        end
        STORE_RESP: if (store_response) begin
          bus_error <= bus_error || (bresp != 2'b00);
          state <= FETCH_ADDR;
        end
        default: state <= FETCH_ADDR;
      endcase
    end
  end

endmodule
