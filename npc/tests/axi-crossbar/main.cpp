#include <verilated.h>

#include <cstdint>
#include <cstdlib>
#include <iostream>

#include "Vaxi4_interconnect_4x4.h"

namespace {

void eval(Vaxi4_interconnect_4x4 &dut) {
  dut.clock = 0;
  dut.eval();
}

void tick(Vaxi4_interconnect_4x4 &dut) {
  dut.clock = 0;
  dut.eval();
  dut.clock = 1;
  dut.eval();
}

bool expect(bool condition, const char *message) {
  if (!condition) std::cerr << "FAIL: " << message << '\n';
  return condition;
}

}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  Vaxi4_interconnect_4x4 dut;
  dut.reset = 1;
  tick(dut);
  dut.reset = 0;

  bool pass = true;

  // Master 2 reads MMIO (target 1); the extended ID is {2'b10, 4'h5}.
  dut.m_arvalid = 1u << 2;
  dut.m_araddr[2] = 0xa0000048u;
  dut.m_arid = 5u << (2 * 4);
  dut.m_arlen = 0;
  dut.m_arsize = 2u << (2 * 3);
  dut.m_arburst = 1u << (2 * 2);
  dut.s_arready = 1u << 1;
  eval(dut);
  pass &= expect(dut.s_arvalid == (1u << 1), "read target decode");
  pass &= expect(dut.s_araddr[1] == 0xa0000048u, "read address forwarding");
  pass &= expect(((dut.s_arid >> 6) & 0x3fu) == 0x25u,
                 "read ID extension");
  pass &= expect(dut.m_arready == (1u << 2), "read ready routing");

  // Route the slave response back to the original master and original ID.
  dut.m_arvalid = 0;
  dut.s_arready = 0;
  dut.s_rvalid = 1u << 1;
  dut.s_rdata[1] = 0x12345678u;
  dut.s_rid = 0x25u << 6;
  dut.s_rlast = 1u << 1;
  dut.m_rready = 1u << 2;
  eval(dut);
  pass &= expect(dut.m_rvalid == (1u << 2), "read response routing");
  pass &= expect(dut.m_rdata[2] == 0x12345678u, "read data forwarding");
  pass &= expect(((dut.m_rid >> 8) & 0xfu) == 5u, "read ID restoration");
  pass &= expect(dut.s_rready == (1u << 1), "read response ready routing");

  // Two masters contend for memory; fixed priority grants master 0.
  dut.s_rvalid = 0;
  dut.m_rready = 0;
  dut.m_arvalid = (1u << 0) | (1u << 1);
  dut.m_araddr[0] = 0x80000000u;
  dut.m_araddr[1] = 0x80000004u;
  dut.s_arready = 1u << 0;
  eval(dut);
  pass &= expect(dut.m_arready == (1u << 0), "read arbitration priority");

  // W must not move before an AW handshake records its target.
  dut.m_arvalid = 0;
  dut.s_arready = 0;
  dut.m_wvalid = 1u << 3;
  dut.s_wready = 1u << 2;
  eval(dut);
  pass &= expect(dut.m_wready == 0, "write data waits for address route");

  // Master 3 writes target 2 with ID 7.
  dut.m_wvalid = 0;
  dut.m_awvalid = 1u << 3;
  dut.m_awaddr[3] = 0xc0000010u;
  dut.m_awid = 7u << (3 * 4);
  dut.m_awlen = 0;
  dut.m_awsize = 2u << (3 * 3);
  dut.m_awburst = 1u << (3 * 2);
  dut.s_awready = 1u << 2;
  eval(dut);
  pass &= expect(dut.s_awvalid == (1u << 2), "write target decode");
  pass &= expect(((dut.s_awid >> 12) & 0x3fu) == 0x37u,
                 "write ID extension");
  tick(dut);

  dut.m_awvalid = 0;
  dut.s_awready = 0;
  dut.m_wvalid = 1u << 3;
  dut.m_wdata[3] = 0xdeadbeefu;
  dut.m_wstrb = 0xfu << (3 * 4);
  dut.m_wlast = 1u << 3;
  dut.s_wready = 1u << 2;
  eval(dut);
  pass &= expect(dut.s_wvalid == (1u << 2), "write data target routing");
  pass &= expect(dut.s_wdata[2] == 0xdeadbeefu, "write data forwarding");
  pass &= expect(((dut.s_wstrb >> 8) & 0xfu) == 0xfu,
                 "write strobe forwarding");
  tick(dut);

  dut.m_wvalid = 0;
  dut.s_wready = 0;
  dut.s_bvalid = 1u << 2;
  dut.s_bid = 0x37u << 12;
  dut.m_bready = 1u << 3;
  eval(dut);
  pass &= expect(dut.m_bvalid == (1u << 3), "write response routing");
  pass &= expect(((dut.m_bid >> 12) & 0xfu) == 7u, "write ID restoration");
  pass &= expect(dut.s_bready == (1u << 2), "write response ready routing");

  dut.final();
  if (!pass) return EXIT_FAILURE;
  std::cout << "PASS: AXI4 4x4 decode, arbitration and ID routing\n";
  return EXIT_SUCCESS;
}
