// 轻量级 MiniRV 反汇编器，仅覆盖讲义要求的指令、只读 CSR 和 ebreak。
#include "disasm.h"

#include <iomanip>
#include <sstream>
#include <string>

namespace npc {
namespace {

std::int32_t sign_extend(std::uint32_t value, unsigned width) {
  const std::uint32_t sign = 1u << (width - 1);
  return static_cast<std::int32_t>((value ^ sign) - sign);
}

std::string reg(unsigned index) { return "x" + std::to_string(index); }

std::string unknown(std::uint32_t instruction) {
  std::ostringstream out;
  out << ".word 0x" << std::hex << std::setw(8) << std::setfill('0')
      << instruction;
  return out.str();
}

const char *csr_name(unsigned csr) {
  switch (csr) {
    case 0xf11: return "mvendorid";
    case 0xf12: return "marchid";
    case 0xb00: return "mcycle";
    case 0xb80: return "mcycleh";
    case 0xc00: return "cycle";
    case 0xc80: return "cycleh";
    default: return nullptr;
  }
}

}  // 匿名命名空间

std::string disassemble(std::uint32_t pc, std::uint32_t instruction) {
  (void)pc;
  const unsigned rd = (instruction >> 7) & 0x1fu;
  const unsigned funct3 = (instruction >> 12) & 0x7u;
  const unsigned rs1 = (instruction >> 15) & 0x1fu;
  const unsigned rs2 = (instruction >> 20) & 0x1fu;
  const unsigned funct7 = instruction >> 25;
  const auto imm_i = sign_extend(instruction >> 20, 12);
  const auto imm_s = sign_extend(((instruction >> 25) << 5) |
                                     ((instruction >> 7) & 0x1fu),
                                 12);

  std::ostringstream out;
  switch (instruction & 0x7fu) {
    case 0x37:  // LUI
      out << "lui " << reg(rd) << ", 0x" << std::hex << (instruction >> 12);
      break;
    case 0x67:  // JALR
      if (funct3 != 0) return unknown(instruction);
      out << "jalr " << reg(rd) << ", " << imm_i << '(' << reg(rs1) << ')';
      break;
    case 0x03:  // LW / LBU
      if (funct3 == 2) out << "lw ";
      else if (funct3 == 4) out << "lbu ";
      else return unknown(instruction);
      out << reg(rd) << ", " << imm_i << '(' << reg(rs1) << ')';
      break;
    case 0x23:  // SW / SB
      if (funct3 == 0) out << "sb ";
      else if (funct3 == 2) out << "sw ";
      else return unknown(instruction);
      out << reg(rs2) << ", " << imm_s << '(' << reg(rs1) << ')';
      break;
    case 0x13:  // ADDI
      if (funct3 != 0) return unknown(instruction);
      out << "addi " << reg(rd) << ", " << reg(rs1) << ", " << imm_i;
      break;
    case 0x33:  // ADD
      if (funct3 != 0 || funct7 != 0) return unknown(instruction);
      out << "add " << reg(rd) << ", " << reg(rs1) << ", " << reg(rs2);
      break;
    case 0x73: {  // EBREAK / CSRRS rd, csr, x0
      if (instruction == 0x00100073u) {
        out << "ebreak";
        break;
      }
      const unsigned csr = instruction >> 20;
      const char *name = csr_name(csr);
      if (funct3 != 2 || rs1 != 0 || name == nullptr) return unknown(instruction);
      out << "csrr " << reg(rd) << ", " << name;
      break;
    }
    default:
      return unknown(instruction);
  }
  return out.str();
}

}  // 命名空间 npc
