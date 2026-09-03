// 轻量级 RV32E 反汇编器，仅用于 itrace 和失败诊断。
#include "disasm.h"

#include <array>
#include <iomanip>
#include <sstream>
#include <string>

namespace npc {
namespace {

// 将 width 位补码立即数扩展到 32 位有符号整数。
std::int32_t sign_extend(std::uint32_t value, unsigned width) {
  const std::uint32_t sign = 1u << (width - 1);
  return static_cast<std::int32_t>((value ^ sign) - sign);
}

std::string reg(unsigned index) { return "x" + std::to_string(index); }

// 分支和跳转立即数是相对当前 PC 的有符号偏移。
std::string target(std::uint32_t pc, std::int32_t offset) {
  std::ostringstream out;
  out << "0x" << std::hex << std::setw(8) << std::setfill('0')
      << (pc + static_cast<std::uint32_t>(offset));
  return out.str();
}

// 保留原始机器码比错误猜测指令名称更适合定位译码问题。
std::string unknown(std::uint32_t instruction) {
  std::ostringstream out;
  out << ".word 0x" << std::hex << std::setw(8) << std::setfill('0')
      << instruction;
  return out.str();
}

}  // 匿名命名空间

std::string disassemble(std::uint32_t pc, std::uint32_t instruction) {
  // 先按 RISC-V 固定字段切分，后续各 opcode 分支只负责格式化。
  const unsigned rd = (instruction >> 7) & 0x1fu;
  const unsigned funct3 = (instruction >> 12) & 0x7u;
  const unsigned rs1 = (instruction >> 15) & 0x1fu;
  const unsigned rs2 = (instruction >> 20) & 0x1fu;
  const unsigned funct7 = instruction >> 25;
  // S/B/J 型立即数在指令中并不连续，这里按规范重新拼接并符号扩展。
  const auto imm_i = sign_extend(instruction >> 20, 12);
  const auto imm_s = sign_extend(((instruction >> 25) << 5) |
                                     ((instruction >> 7) & 0x1fu),
                                 12);
  const auto imm_b = sign_extend(((instruction >> 31) << 12) |
                                     (((instruction >> 7) & 1u) << 11) |
                                     (((instruction >> 25) & 0x3fu) << 5) |
                                     (((instruction >> 8) & 0xfu) << 1),
                                 13);
  const auto imm_j = sign_extend(((instruction >> 31) << 20) |
                                     (((instruction >> 12) & 0xffu) << 12) |
                                     (((instruction >> 20) & 1u) << 11) |
                                     (((instruction >> 21) & 0x3ffu) << 1),
                                 21);

  // 此反汇编器只覆盖当前 MiniRV 实现的整数子集，保持实现小而明确。
  std::ostringstream out;
  switch (instruction & 0x7fu) {
    case 0x37:
      out << "lui " << reg(rd) << ", 0x" << std::hex
          << (instruction >> 12);
      break;
    case 0x17:
      out << "auipc " << reg(rd) << ", 0x" << std::hex
          << (instruction >> 12);
      break;
    case 0x6f:
      out << "jal " << reg(rd) << ", " << target(pc, imm_j);
      break;
    case 0x67:
      if (funct3 != 0) return unknown(instruction);
      out << "jalr " << reg(rd) << ", " << imm_i << '(' << reg(rs1) << ')';
      break;
    case 0x63: {
      static constexpr std::array<const char *, 8> names = {
          "beq", "bne", nullptr, nullptr, "blt", "bge", "bltu", "bgeu"};
      if (names[funct3] == nullptr) return unknown(instruction);
      out << names[funct3] << ' ' << reg(rs1) << ", " << reg(rs2) << ", "
          << target(pc, imm_b);
      break;
    }
    case 0x03: {
      static constexpr std::array<const char *, 8> names = {
          "lb", "lh", "lw", nullptr, "lbu", "lhu", nullptr, nullptr};
      if (names[funct3] == nullptr) return unknown(instruction);
      out << names[funct3] << ' ' << reg(rd) << ", " << imm_i << '('
          << reg(rs1) << ')';
      break;
    }
    case 0x23: {
      static constexpr std::array<const char *, 8> names = {
          "sb", "sh", "sw", nullptr, nullptr, nullptr, nullptr, nullptr};
      if (names[funct3] == nullptr) return unknown(instruction);
      out << names[funct3] << ' ' << reg(rs2) << ", " << imm_s << '('
          << reg(rs1) << ')';
      break;
    }
    case 0x13: {
      static constexpr std::array<const char *, 8> names = {
          "addi", "slli", "slti", "sltiu", "xori", nullptr, "ori", "andi"};
      if (funct3 == 5) {
        if (funct7 == 0) out << "srli ";
        else if (funct7 == 0x20) out << "srai ";
        else return unknown(instruction);
        out << reg(rd) << ", " << reg(rs1) << ", " << rs2;
      } else {
        if (names[funct3] == nullptr || (funct3 == 1 && funct7 != 0)) {
          return unknown(instruction);
        }
        out << names[funct3] << ' ' << reg(rd) << ", " << reg(rs1) << ", ";
        if (funct3 == 1) out << rs2;
        else out << imm_i;
      }
      break;
    }
    case 0x33: {
      const char *name = nullptr;
      if (funct7 == 0) {
        static constexpr std::array<const char *, 8> names = {
            "add", "sll", "slt", "sltu", "xor", "srl", "or", "and"};
        name = names[funct3];
      } else if (funct7 == 0x20 && funct3 == 0) {
        name = "sub";
      } else if (funct7 == 0x20 && funct3 == 5) {
        name = "sra";
      }
      if (name == nullptr) return unknown(instruction);
      out << name << ' ' << reg(rd) << ", " << reg(rs1) << ", " << reg(rs2);
      break;
    }
    case 0x0f:
      if (funct3 != 0) return unknown(instruction);
      out << "fence";
      break;
    case 0x73:
      if (instruction == 0x00100073u) out << "ebreak";
      else return unknown(instruction);
      break;
    default:
      return unknown(instruction);
  }
  return out.str();
}

}  // 命名空间 npc
