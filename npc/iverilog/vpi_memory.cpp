// Icarus Verilog 的 VPI 访存插件。
//
// E8 要求在 Icarus 中使用 VPI 替代 DPI-C。这里注册两个系统函数：
//   $pmem_read(address, length)
//   $pmem_write(address, data, mask)
//
// 它们复用 NPC 已有的 Memory/DeviceMap，实现与 Verilator 仿真相同的
// 主存、串口和计时器行为。镜像路径通过 +img=FILE 传给 vvp。
#include <vpi_user.h>

#include <cstdint>
#include <cstring>
#include <iostream>
#include <memory>
#include <string>

#include "device.h"
#include "memory.h"
#include "runtime.h"
#include "types.h"

extern "C" std::uint32_t pmem_read(std::uint32_t address,
                                    std::uint8_t length);
extern "C" void pmem_write(std::uint32_t address, std::uint32_t data,
                           std::uint8_t mask);

namespace {

npc::Memory g_memory;
npc::DeviceMap g_devices;
npc::RunState g_state;

std::uint32_t read_argument(vpiHandle argument) {
  s_vpi_value value{};
  value.format = vpiIntVal;
  vpi_get_value(argument, &value);
  return static_cast<std::uint32_t>(value.value.integer);
}

void report_vpi_error(const char *message) {
  vpi_printf("VPI error: %s\n", message);
  vpi_control(vpiFinish, 1);
}

PLI_INT32 pmem_read_calltf(PLI_BYTE8 *) {
  vpiHandle call = vpi_handle(vpiSysTfCall, nullptr);
  vpiHandle arguments = vpi_iterate(vpiArgument, call);
  if (arguments == nullptr) {
    report_vpi_error("$pmem_read expects address, length and output");
    return 0;
  }

  vpiHandle address_handle = vpi_scan(arguments);
  vpiHandle length_handle = vpi_scan(arguments);
  vpiHandle result_handle = vpi_scan(arguments);
  if (address_handle == nullptr || length_handle == nullptr ||
      result_handle == nullptr) {
    report_vpi_error("$pmem_read expects address, length and output");
    return 0;
  }

  const auto address = read_argument(address_handle);
  const auto length = static_cast<std::uint8_t>(read_argument(length_handle));
  const auto result = pmem_read(address, length);

  s_vpi_value result_value{};
  result_value.format = vpiIntVal;
  result_value.value.integer = static_cast<PLI_INT32>(result);
  vpi_put_value(result_handle, &result_value, nullptr, vpiNoDelay);
  return 0;
}

PLI_INT32 pmem_write_calltf(PLI_BYTE8 *) {
  vpiHandle call = vpi_handle(vpiSysTfCall, nullptr);
  vpiHandle arguments = vpi_iterate(vpiArgument, call);
  if (arguments == nullptr) {
    report_vpi_error("$pmem_write expects address, data and mask");
    return 0;
  }

  vpiHandle address_handle = vpi_scan(arguments);
  vpiHandle data_handle = vpi_scan(arguments);
  vpiHandle mask_handle = vpi_scan(arguments);
  if (address_handle == nullptr || data_handle == nullptr || mask_handle == nullptr) {
    report_vpi_error("$pmem_write expects address, data and mask");
    return 0;
  }

  pmem_write(read_argument(address_handle), read_argument(data_handle),
             static_cast<std::uint8_t>(read_argument(mask_handle)));
  return 0;
}

void register_system_tasks() {
  s_vpi_systf_data read_data{};
  read_data.type = vpiSysTask;
  read_data.tfname = const_cast<PLI_BYTE8 *>("$pmem_read");
  read_data.calltf = pmem_read_calltf;
  vpi_register_systf(&read_data);

  s_vpi_systf_data write_data{};
  write_data.type = vpiSysTask;
  write_data.tfname = const_cast<PLI_BYTE8 *>("$pmem_write");
  write_data.calltf = pmem_write_calltf;
  vpi_register_systf(&write_data);

  s_vpi_vlog_info info{};
  std::string image_path;
  if (vpi_get_vlog_info(&info) != 0) {
    for (int i = 1; i < info.argc; ++i) {
      constexpr const char kImagePrefix[] = "+img=";
      if (std::strncmp(info.argv[i], kImagePrefix,
                       sizeof(kImagePrefix) - 1) == 0) {
        image_path = info.argv[i] + sizeof(kImagePrefix) - 1;
        break;
      }
    }
  }

  try {
    const auto image_size = g_memory.load_image(image_path);
    g_memory.enable_checks();
    npc::bind_runtime(g_memory, g_devices, g_state);
    vpi_printf("loaded %zu bytes at 0x%08x\n", image_size, npc::kPmemBase);
  } catch (const std::exception &error) {
    report_vpi_error(error.what());
  }
}

}  // namespace

extern "C" {
void (*vlog_startup_routines[])() = {register_system_tasks, nullptr};
}
