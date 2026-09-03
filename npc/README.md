# NPC 代码导读：面向 C 语言学习者的 C++ 与 RTL 入门

> 更新时间：2026-09-03
> 适用范围：当前仓库中 E7“接入 SoC”之前的 NPC、MiniRV、DiffTest、Abstract Machine 和简易 AXI 总线代码。

## 1. 阅读目标

这份文档假设你已经能够使用 C 语言，但刚开始接触 C++ 和 Verilog/SystemVerilog。阅读后应当能够回答以下问题：

1. NPC 仿真器由哪些模块组成？
2. C++ 的类、对象、引用、构造函数和智能指针在本项目中分别解决什么问题？
3. C++ 如何驱动 Verilator 生成的硬件模型？
4. RTL 如何通过 DPI-C 访问 C++ 中的主存和 MMIO 设备？
5. 一条普通指令、load 指令和 store 指令分别如何执行？
6. DiffTest 为什么必须在“指令提交”时比较，而不能每个时钟周期都比较？
7. 出现非法指令、总线错误、DiffTest 不一致或超时时，应当从哪里开始调试？

本文不会系统讲解整个 C++ 标准，而是只解释当前代码实际使用到的 C++ 特性。

---

## 2. 建议阅读顺序

如果你第一次接触这套代码，建议按以下顺序阅读：

1. `npc/csrc/include/types.h`：先了解公共数据结构；
2. `npc/csrc/main.cpp`：建立仿真器整体流程；
3. `npc/csrc/memory.cpp`：理解镜像和主存；
4. `npc/csrc/device.cpp`：理解串口和计时器；
5. `npc/csrc/runtime.cpp`：理解 DPI-C；
6. `npc/csrc/simulator.cpp`：理解 C++ 如何驱动 Verilator；
7. `npc/csrc/difftest.cpp`：理解 NPC 和 NEMU 如何逐指令比较；
8. `npc/vsrc/top.sv`：从 RTL 顶层观察各模块连接；
9. `npc/vsrc/minirv_core.sv`、`minirv_decode.sv`、`minirv_regfile.sv`：理解 CPU 数据通路；
10. `npc/vsrc/minirv_axi_lite_master.sv`：理解 CPU 为什么需要等待总线；
11. AXI 适配器、互联和从设备模块；
12. `npc/nvboard/`：最后阅读板级演示适配。

不要一开始就同时阅读所有 AXI 信号。先理解 C++ 主流程和 CPU 核心，再阅读总线会容易很多。

---

## 3. 整体结构

### 3.1 软件和硬件的分工

当前 NPC 可以粗略分成三层：

```text
┌──────────────────────────────────────────────────────────────┐
│ C++ 仿真环境                                                 │
│                                                              │
│ main / options / simulator / memory / device / difftest      │
└──────────────────────────────┬───────────────────────────────┘
                               │ Verilator 端口和 DPI-C
┌──────────────────────────────▼───────────────────────────────┐
│ RTL 平台与总线                                                │
│                                                              │
│ top → AXI4-Lite 主设备 → AXI4 适配器 → 4×4 互联 → 从设备     │
└──────────────────────────────┬───────────────────────────────┘
                               │ 指令/数据请求与 step
┌──────────────────────────────▼───────────────────────────────┐
│ MiniRV CPU                                                   │
│                                                              │
│ minirv_core → minirv_decode + minirv_regfile                 │
└──────────────────────────────────────────────────────────────┘
```

三层职责分别是：

- **C++ 仿真环境**：加载镜像、保存主存、模拟设备、驱动时钟、生成波形、执行 DiffTest、决定宿主进程退出码；
- **RTL 平台与总线**：把 CPU 的简单访存请求转换成 AXI 握手事务，并完成地址译码和响应路由；
- **MiniRV CPU**：实现 RISC-V 架构状态、指令译码、运算、跳转和访存语义。

CPU 核心不知道镜像文件路径，也不会直接调用 C++。这种边界使核心既能连接 NPC 总线，也能被 NVBoard 顶层复用。

### 3.2 一次主存访问的完整路径

```text
MiniRV 核心
  │ dmem_addr / dmem_write / dmem_wdata / dmem_wmask
  ▼
minirv_axi_lite_master
  │ AXI4-Lite
  ▼
axi_lite_master_to_axi4
  │ 单拍 AXI4，添加 ID/LEN/SIZE/BURST
  ▼
axi4_system_interconnect
  │ 地址译码、仲裁、ID 路由
  ▼
axi4_to_lite_slave
  │ 再转换为 AXI4-Lite
  ▼
axi_lite_pmem
  │ DPI-C 调用
  ▼
pmem_read() / pmem_write()       ← runtime.cpp
  │
  ├── 命中 MMIO → DeviceMap       ← device.cpp
  └── 未命中   → Memory           ← memory.cpp
```

这里最重要的边界是：

- CPU 只产生硬件信号；
- 总线模块只处理握手和路由；
- 只有最末端的平台从设备 `axi_lite_pmem` 使用 DPI-C；
- C++ 再决定该地址属于主存还是设备。

---

# 第一部分：从 C 语言过渡到本项目使用的 C++

## 4. C++ 并不是“完全不同的语言”

当前项目中的大部分 C++ 仍然保留了熟悉的 C 风格：

- `if`、`for`、`while`、`switch` 与 C 基本相同；
- 指针、数组、位运算和整数类型仍然存在；
- `std::uint32_t` 对应 C 中 `<stdint.h>` 的 `uint32_t`；
- 函数声明和函数调用方式基本相同；
- `const`、结构体和枚举的基本思想也相同。

项目使用 C++，主要是为了更安全地管理以下对象：

- 主存数组；
- Verilator 仿真上下文；
- RTL 顶层对象；
- VCD 波形对象；
- NEMU 动态库句柄；
- 字符串和错误信息。

可以先把 C++ 理解成：**C 语言加上对象生命周期管理和标准容器**。

---

## 5. `namespace`：避免全局名称冲突

代码经常出现：

```cpp
namespace npc {

class Memory {
  // ...
};

}  // 命名空间 npc
```

它相当于给名称增加一个前缀。命名空间外使用时写成：

```cpp
npc::Memory memory;
npc::Options options;
```

可以近似理解为 C 项目中手工使用前缀：

```c
typedef struct npc_memory npc_memory;
typedef struct npc_options npc_options;
```

区别是 `namespace` 由语言直接支持，不需要把每个符号都手工命名为 `npc_xxx`。

### 5.1 匿名命名空间

有些 `.cpp` 中还有：

```cpp
namespace {

constexpr uint32_t kRtcAddress = 0xa0000048u;

}
```

匿名命名空间中的名称只在当前源文件可见，作用近似于 C 中的文件级 `static`：

```c
static const uint32_t kRtcAddress = 0xa0000048u;
```

这样可以防止不同 `.cpp` 文件中的内部名称互相冲突。

---

## 6. `class`、对象和成员函数

以 `Memory` 为例：

```cpp
class Memory {
 public:
  Memory();
  uint32_t read(uint32_t address, uint8_t length);

 private:
  std::vector<uint8_t> bytes_;
};
```

可以把类理解为“带操作函数的结构体”。它在 C 中大致可以写成：

```c
typedef struct {
  uint8_t *bytes;
  size_t size;
} Memory;

void memory_init(Memory *self);
uint32_t memory_read(Memory *self, uint32_t address, uint8_t length);
```

C++ 调用：

```cpp
Memory memory;
uint32_t value = memory.read(address, 4);
```

近似对应 C 调用：

```c
Memory memory;
memory_init(&memory);
uint32_t value = memory_read(&memory, address, 4);
```

成员函数内部隐含了一个指向当前对象的 `this` 指针。因此：

```cpp
memory.read(address, 4);
```

可以理解为：

```c
memory_read(&memory, address, 4);
```

### 6.1 `public` 和 `private`

- `public`：类外部可以调用；
- `private`：只能由类自己的成员函数访问。

`Memory` 把内部 `bytes_` 设为私有，外部必须通过 `read()` 和 `write()` 操作，从而集中执行地址检查和小端序转换。

### 6.2 变量名后的下划线

例如：

```cpp
std::vector<uint8_t> bytes_;
void *handle_ = nullptr;
```

末尾下划线只是本项目用于表示“类成员变量”的命名习惯，不是 C++ 语法要求。

---

## 7. 构造函数和析构函数

### 7.1 构造函数

构造函数名称与类名相同，没有返回类型：

```cpp
Memory::Memory() : bytes_(kPmemSize, 0) {}
```

创建对象时会自动执行：

```cpp
Memory memory;
```

上面的初始化列表：

```cpp
: bytes_(kPmemSize, 0)
```

表示创建一个大小为 `kPmemSize`、初始值全部为 0 的字节数组。

C 语言通常需要手工调用：

```c
Memory memory;
memory_init(&memory);
```

C++ 构造函数的价值是减少“声明了对象却忘记初始化”的情况。

### 7.2 析构函数

析构函数名称前带 `~`：

```cpp
Difftest::~Difftest() {
  if (handle_ != nullptr) dlclose(handle_);
}
```

对象离开作用域时会自动调用析构函数。即使中途通过异常退出当前作用域，已经成功构造的局部对象仍会被正确清理。

这就是 C++ 常说的 **RAII**：

> 资源的获取和释放绑定到对象生命周期。

在 C 中，经常需要跳转到统一清理标签：

```c
resource = open_resource();
if (error1) goto cleanup;
if (error2) goto cleanup;

cleanup:
close_resource(resource);
```

C++ 则倾向于让对象析构函数自动完成清理。

---

## 8. 引用 `&` 与指针

代码中有：

```cpp
void bind_runtime(Memory &memory, DeviceMap &devices, RunState &state);
```

这里的 `Memory &` 是“引用”，可以理解为一个不能为空、使用时不需要解引用符号的别名。

C++：

```cpp
void clear(Memory &memory) {
  memory.write(...);
}
```

近似 C：

```c
void clear(Memory *memory) {
  memory_write(memory, ...);
}
```

调用方式区别：

```cpp
bind_runtime(memory, devices, state);  // C++ 引用
bind_runtime(&memory, &devices, &state); // 如果是 C 指针接口
```

本项目中引用主要用于表达：

- 调用者传入一个已经存在的对象；
- 函数不会接管对象所有权；
- 参数不应该为空。

指针仍用于可能为空或需要和 C 接口兼容的场景，例如：

```cpp
npc::Memory *g_memory = nullptr;
void *handle_ = nullptr;
```

---

## 9. `const` 成员函数

例如：

```cpp
bool DeviceMap::read(...) const;
```

函数参数列表后的 `const` 表示该成员函数不会修改对象的普通成员变量。

可以近似理解为 C 接口接收：

```c
bool device_read(const DeviceMap *self, ...);
```

这能让编译器帮助检查意外修改。

另一个常见形式是：

```cpp
const Memory &memory
```

表示函数可以读取该对象，但不能通过这个引用修改它。

---

## 10. `std::string`、`std::vector` 和 `std::array`

### 10.1 `std::string`

`std::string` 是自动管理内存的字符串：

```cpp
std::string image_path;
```

常用操作：

```cpp
image_path.empty();   // 是否为空
image_path.c_str();   // 获取兼容 C API 的 const char *
```

相比 `char *`，它会自动分配和释放内存，也会记录字符串长度。

### 10.2 `std::vector<uint8_t>`

`Memory` 使用：

```cpp
std::vector<std::uint8_t> bytes_;
```

它是长度在运行时确定的连续数组。构造后可以像 C 数组一样用下标访问：

```cpp
bytes_[offset]
```

还可以取得连续内存首地址：

```cpp
bytes_.data()
```

这里选择 `vector` 是因为 128 MiB 主存不适合作为巨大的栈上局部数组，并且 `vector` 会自动释放内存。

### 10.3 `std::array<uint32_t, 4>`

内置自检程序使用：

```cpp
const std::array<std::uint32_t, 4> program = { ... };
```

它表示编译期固定长度的数组，与 C 数组接近，但能提供 `.size()` 等接口。

---

## 11. `auto`：让编译器推导类型

例如：

```cpp
const auto image_size = memory.load_image(options.image_path);
```

编译器知道 `load_image()` 返回 `std::size_t`，因此 `image_size` 的类型就是 `std::size_t`。

它不表示“动态类型”，也不会在运行时改变类型。下面两句效果相同：

```cpp
const auto image_size = memory.load_image(path);
const std::size_t image_size = memory.load_image(path);
```

本项目在类型很明显或类型名较长时使用 `auto`，架构数据仍显式使用 `std::uint32_t` 等固定宽度类型。

---

## 12. `nullptr`

C++ 使用：

```cpp
Memory *g_memory = nullptr;
```

它代替 C 中常见的 `NULL`。`nullptr` 有明确的空指针类型，不会像整数常量 `0` 那样引起函数重载歧义。

判断方法与 C 相似：

```cpp
if (g_memory != nullptr) {
  // ...
}
```

---

## 13. `std::unique_ptr` 和对象所有权

`Simulator` 中有：

```cpp
std::unique_ptr<VerilatedContext> context_;
std::unique_ptr<Vtop> dut_;
std::unique_ptr<VerilatedVcdC> trace_;
```

`unique_ptr` 表示：

- 该指针指向的对象只有一个所有者；
- 所有者销毁时，目标对象会自动 `delete`；
- 默认不能复制，防止两个对象重复释放同一地址。

创建方式：

```cpp
context_ = std::make_unique<VerilatedContext>();
```

近似于 C：

```c
VerilatedContext *context = malloc(sizeof(*context));
// 使用结束后必须 free(context)
```

区别是 `unique_ptr` 会自动释放。

访问目标对象时：

```cpp
dut_->clock = 1;
dut_->eval();
```

`->` 与 C 指针访问结构体成员的语法相同。

### 13.1 为什么 `trace_` 可以为空

只有指定 `--wave` 时才创建 VCD 对象。因此代码可以判断：

```cpp
if (trace_) {
  trace_->dump(...);
}
```

`unique_ptr` 在条件表达式中可以直接表示“是否持有对象”。

---

## 14. 异常 `try`、`throw` 和 `catch`

主函数使用：

```cpp
try {
  // 初始化和运行
} catch (const std::exception &error) {
  std::cerr << error.what() << '\n';
  return EXIT_FAILURE;
}
```

其他模块遇到无法继续的初始化错误时使用：

```cpp
throw std::runtime_error("cannot open image");
```

执行 `throw` 后，程序会跳转到能够处理该异常的 `catch`。跳转过程中，已经构造的局部 C++ 对象会自动析构。

可以把它类比为 C 中层层返回错误码，但异常适合处理本项目中的致命初始化错误：

- 镜像无法打开；
- 镜像大于物理内存；
- NEMU 共享库无法加载；
- DiffTest 必需符号不存在。

客户程序的 bad trap、总线错误和超时没有使用异常，因为它们是正常仿真流程的一部分，由 `RunState` 和返回码处理。

---

## 15. C++ 类型转换

本项目使用了几种显式类型转换。

### 15.1 `static_cast`

```cpp
static_cast<std::uint32_t>(micros)
```

用于普通、可检查的数值转换，比 C 风格强制转换更明确。

### 15.2 `reinterpret_cast`

```cpp
reinterpret_cast<char *>(bytes_.data())
```

表示把一段内存重新解释为另一种指针类型。镜像读取需要把字节数组地址交给 `ifstream::read()`，后者要求 `char *`。

另一个用途是把 `dlsym()` 返回的通用地址转换成函数指针。

### 15.3 `const_cast`

```cpp
const_cast<std::uint8_t *>(memory.data())
```

用于去除 `const`。这里是因为 NEMU 的历史 DiffTest 接口参数不是 `const void *`，但初始化复制实际不会修改 NPC 的镜像。

`reinterpret_cast` 和 `const_cast` 都应谨慎使用；当前代码只在与既有 C API 交界处使用。

---

## 16. 模板在本项目中的唯一主要用途

`Difftest` 中有：

```cpp
template <typename T>
T load_symbol(const char *name);
```

这是一个函数模板。调用时，目标变量类型帮助编译器确定 `T`：

```cpp
memcpy_ = load_symbol<MemcpyFn>("difftest_memcpy");
exec_ = load_symbol<ExecFn>("difftest_exec");
```

如果不用模板，就要为每一种函数指针类型分别写几乎相同的 `dlsym()` 和错误检查代码。

这里的模板只是在编译期生成几个具体版本，不涉及运行时反射。

---

## 17. `extern "C"` 与 DPI-C

RTL 使用 DPI-C 按 C ABI 查找函数名。C++ 编译器默认会把参数类型编码到符号名中，这称为名称修饰。为了让 Verilog 能找到准确名称，需要写：

```cpp
extern "C" std::uint32_t pmem_read(...);
```

它的含义是：

> 函数体使用 C++ 编写，但导出符号和调用约定采用 C 规则。

当前 DPI-C 函数包括：

| C++ 函数 | 调用方向 | 作用 |
|---|---|---|
| `pmem_read` | RTL → C++ | 读取主存或计时器 |
| `pmem_write` | RTL → C++ | 写主存或串口 |
| `npc_ebreak` | RTL → C++ | 记录客户程序退出码 |
| `npc_abort` | RTL → C++ | 报告非法指令 |
| `npc_bus_error` | RTL → C++ | 报告总线错误和来源 |

这些函数只负责跨语言边界，不应在里面实现 CPU 指令语义。

---

# 第二部分：逐个阅读 C++ 模块

## 18. `types.h`：公共常量和状态

### 18.1 物理内存常量

```cpp
constexpr std::uint32_t kPmemBase = 0x80000000u;
constexpr std::size_t kPmemSize = 128u * 1024u * 1024u;
```

`constexpr` 表示编译期常量。NPC、镜像加载器和 DiffTest 必须使用同一组地址定义。

### 18.2 `Options`

`Options` 保存命令行结果：

- `image_path`：裸二进制镜像；
- `wave_path`：VCD 波形路径；
- `diff_path`：NEMU 共享库；
- `max_cycles`：超时周期；
- `itrace`：是否打印提交轨迹。

### 18.3 `RunState`

`RunState` 在 DPI-C 回调和主循环之间共享：

- `halted`：客户程序执行了 `ebreak`；
- `aborted`：发生非法指令、总线错误或 DiffTest 不一致；
- `code`：`ebreak` 时 `a0` 的值；
- `pc`：停止位置。

注意 `halted` 不等于测试通过。只有 `halted == true` 且 `code == 0` 才是 good trap。

---

## 19. `options.cpp`：命令行解析

支持的参数：

```text
--image FILE
--max-cycles N
--wave FILE
--itrace
--diff REF_SO
```

`parse_options()` 顺序遍历 `argv`。遇到需要值的参数时先执行 `++i`，把索引移动到参数值。

例如：

```text
argv[1] = "--image"
argv[2] = "program.bin"
```

当处理 `--image` 时，代码把 `i` 从 1 增加到 2，然后保存 `argv[2]`。

`parse_u64()` 使用 `strtoull()`，并检查 `end` 是否指向字符串结尾，防止把 `123abc` 当作合法数字。

---

## 20. `memory.cpp`：主存和镜像

### 20.1 内存表示

主存使用连续字节数组：

```cpp
std::vector<std::uint8_t> bytes_;
```

数组下标不是完整物理地址，而是：

```text
offset = address - 0x80000000
```

例如地址 `0x80000004` 对应 `bytes_[4]`。

### 20.2 镜像加载

`load_image()` 的流程：

1. 以二进制方式打开文件；
2. 先移动到文件末尾取得大小；
3. 检查镜像是否超过 128 MiB；
4. 回到文件开头；
5. 读取到 `bytes_[0]` 开始的位置；
6. 返回镜像字节数，供 DiffTest 初始化复制。

未指定镜像时会装入四条最小自检指令，最终检查 `x2 == 3`。

### 20.3 小端序读取

RISC-V 当前配置使用小端序。假设内存为：

```text
address+0: 0x78
address+1: 0x56
address+2: 0x34
address+3: 0x12
```

读取 4 字节得到：

```text
0x12345678
```

代码通过左移 `i * 8` 完成拼接。

### 20.4 写掩码

`mask` 的 bit0~bit3 分别控制四个字节：

| mask | 含义 |
|---|---|
| `0001` | 写最低 1 字节，供 `sb` 使用 |
| `0011` | 写最低 2 字节，供 `sh` 使用 |
| `1111` | 写全部 4 字节，供 `sw` 使用 |

当前 CPU 已经把非对齐地址体现在 `address` 中，因此 C++ 只需从该地址开始按掩码写入。

### 20.5 为什么越界后不直接 `abort()`

`Memory` 只记录：

```cpp
faulted_ = true;
fault_message_ = ...;
```

主循环在当前周期结束后统一退出。这样资源仍能正常析构，错误输出也保持一致。

---

## 21. `device.cpp`：串口和计时器

### 21.1 串口

串口地址为：

```text
0xa00003f8
```

当最低字节写掩码有效时，使用：

```cpp
std::putchar(...);
std::fflush(stdout);
```

立即把一个字符输出到宿主终端。`fflush()` 避免字符长时间停留在输出缓冲区。

### 21.2 计时器

计时器地址为：

```text
0xa0000048  低 32 位
0xa000004c  高 32 位
```

`steady_clock` 表示单调时钟，不会因为用户修改系统日期而倒退。

AM 中的 32 位 CPU 无法一次读取 64 位，因此会采用“高、低、高”的读取方法：

1. 读取高 32 位；
2. 读取低 32 位；
3. 再读一次高 32 位；
4. 两次高位相同才接受结果。

这样可以避免低 32 位恰好溢出时得到撕裂的 64 位数值。

### 21.3 设备函数为什么返回 `bool`

```cpp
bool DeviceMap::read(...);
```

返回值表示“该地址是否由设备处理”，不是读取数据本身：

- `true`：命中设备，`value` 已填写；
- `false`：未命中，调用者继续访问主存。

这是一个简单的地址分派接口。

---

## 22. `runtime.cpp`：DPI-C 转发层

### 22.1 为什么保存全局指针

DPI-C 回调由 RTL 发起，没有 `Memory` 对象参数。因此 `main()` 创建对象后调用：

```cpp
bind_runtime(memory, devices, state);
```

将对象地址保存到：

```cpp
Memory *g_memory;
DeviceMap *g_devices;
RunState *g_state;
```

这些指针不拥有对象，不能在 `runtime.cpp` 中释放。对象实际由 `main()` 的局部变量管理。

### 22.2 `pmem_read()` 的分派顺序

```text
先调用 DeviceMap::read()
  ├── 命中计时器：直接返回设备值
  └── 未命中：调用 Memory::read()
```

写操作同理，先尝试串口，再尝试主存。

虽然函数名称叫 `pmem_read`，它实际上是当前平台总线从设备的统一后端入口。

### 22.3 结束事件

- `npc_ebreak()`：设置 `halted`，保存 PC 和 `a0`；
- `npc_abort()`：设置 `aborted`，打印非法指令；
- `npc_bus_error()`：设置 `aborted`，打印故障 PC 和错误来源位。

回调不直接调用 `exit()`，从而让主循环统一关闭波形、RTL 对象和动态库。

---

## 23. `simulator.cpp`：驱动 Verilator

### 23.1 `Vtop` 是什么

Verilator 根据 `top.sv` 自动生成 C++ 类 `Vtop`。RTL 端口变成类成员，例如：

```cpp
dut_->clock = 1;
dut_->reset = 0;
dut_->eval();
```

你不需要手工编写 `Vtop.h`，它位于构建目录中。

### 23.2 时钟推进

一个完整周期由两个半周期组成：

```text
clock=0 → eval → timeInc
clock=1 → eval → timeInc
```

`eval()` 表示让 Verilator 重新计算电路。时钟从 0 变为 1 时会触发 RTL 中的：

```systemverilog
always_ff @(posedge clock)
```

### 23.3 同步复位

当前 RTL 使用同步复位，因此仅把 `reset=1` 还不够，还必须产生上升沿。`Simulator::reset()` 保持两个完整周期的复位，然后再撤销。

### 23.4 波形

只有指定：

```bash
make -C npc run WAVE=build/run.vcd
```

才创建 `VerilatedVcdC`。每次组合求值后执行 `dump()`，记录当前时间点信号。

### 23.5 提交历史

每当 `commit_valid` 有效，仿真器保存：

- `commit_pc`；
- `commit_inst`。

队列只保留最近 16 条，防止长程序无限占用内存。DiffTest 失败时打印这段历史，通常比直接查看完整波形更快。

---

## 24. `disasm.cpp`：轻量反汇编

反汇编器首先提取固定字段：

```text
opcode = inst[6:0]
rd     = inst[11:7]
funct3 = inst[14:12]
rs1    = inst[19:15]
rs2    = inst[24:20]
funct7 = inst[31:25]
```

然后按 opcode 选择格式。

S、B、J 型立即数在机器码中不是连续排列的，因此需要按规范重新拼接。拼接完成后调用 `sign_extend()` 做补码符号扩展。

这个模块不是 CPU 译码器：

- RTL `minirv_decode.sv` 决定电路实际行为；
- C++ `disasm.cpp` 只生成调试文本。

未知编码显示为 `.word 0x...`，避免调试工具错误猜测。

---

## 25. `difftest.cpp`：NPC 与 NEMU 比较

### 25.1 动态加载 NEMU

NPC 使用：

```cpp
dlopen(path, ...);
dlsym(handle, "difftest_exec");
```

运行时取得 NEMU 导出的函数，不启用 DiffTest 时就不需要加载该共享库。

必须取得四个接口：

- `difftest_init`；
- `difftest_memcpy`；
- `difftest_regcpy`；
- `difftest_exec`。

### 25.2 初始化同步

开始执行前：

1. 初始化 NEMU；
2. 把 NPC 镜像复制到 NEMU 的 `0x80000000`；
3. 把 NEMU PC 设置为复位向量；
4. 将寄存器初始化为 0。

否则两边不是从同一个状态开始，后面的比较没有意义。

### 25.3 每一步比较

DUT 提交一条指令后：

1. NEMU 执行一条指令；
2. 从 NEMU 取回 PC 和 16 个 RV32E 寄存器；
3. 比较下一 PC；
4. 比较 x0~x15；
5. 输出第一个不一致项；
6. 输出最近 16 条 DUT 提交轨迹。

### 25.4 为什么不能每个周期调用 DiffTest

一条指令可能经历：

```text
取指地址 → 等待取指数据 → load 地址 → 等待 load 数据 → 提交
```

等待总线期间，DUT 没有执行完新指令。如果此时让 NEMU 每周期执行一条，参考模型会远远跑到 DUT 前面。

因此主循环只在：

```cpp
if (simulator.commit_valid())
```

内部调用 `difftest->step()`。

---

## 26. `main.cpp`：把所有模块串起来

主函数流程可以概括为：

```text
解析命令行
  ↓
创建 Memory、DeviceMap、RunState
  ↓
绑定 DPI-C 运行时对象
  ↓
加载客户镜像
  ↓
创建 Simulator 并复位 RTL
  ↓
可选：创建 Difftest
  ↓
逐周期 tick
  ├── 提交时打印 itrace
  └── 提交时执行 DiffTest
  ↓
检查内存错误、abort、timeout、bad trap
  ↓
输出 good trap 或返回失败
```

### 26.1 周期数和指令数

`executed` 是 C++ 每调用一次 `tick()` 增加一次，表示总线仿真周期。

`instruction_count` 由 RTL 在 `step` 时增加，表示已经提交的客户指令数。

因为总线访问可能等待多个周期，所以通常：

```text
总线周期数 > 提交指令数
```

### 26.2 退出类型

| 类型 | 条件 | 宿主返回值 |
|---|---|---|
| good trap | 执行 `ebreak` 且 `a0=0` | 成功 |
| bad trap | 执行 `ebreak` 且 `a0!=0` | 失败 |
| abort | 非法指令、总线错误、DiffTest 不一致、主存越界 | 失败 |
| timeout | 超过最大周期仍未结束 | 失败 |

---

# 第三部分：RTL 代码导读

## 27. 先区分组合逻辑和时序逻辑

### 27.1 `always_comb`

组合逻辑没有记忆：输出只取决于当前输入。

```systemverilog
always_comb begin
  result = 32'd0;
  if (enable) result = a + b;
end
```

组合块应该先给所有输出默认值。如果某条路径没有赋值，综合工具可能推断锁存器。

### 27.2 `always_ff @(posedge clock)`

时序逻辑在时钟上升沿更新状态：

```systemverilog
always_ff @(posedge clock) begin
  if (reset) q <= 0;
  else if (enable) q <= d;
end
```

时序逻辑使用非阻塞赋值 `<=`，使同一个时钟沿上的寄存器同时更新。

当前工程遵循：

- 译码和 ALU 放在组合逻辑；
- PC、寄存器堆、总线状态机放在时序逻辑；
- 同一个状态寄存器只由一个时序块驱动。

---

## 28. `minirv_regfile.sv`

RV32E 只有 16 个寄存器：

```text
x0 ~ x15
```

两个源寄存器通过组合端口读取。目的寄存器只在 `rd_write` 有效的时钟沿更新。

`x0` 通过两层保护保持为 0：

1. `rd_idx == 0` 时禁止写；
2. 每个非复位周期再次执行 `gpr[0] <= 0`。

`gpr_state` 把数组展平为 512 位信号，便于 Verilator 从 C++ 读取全部寄存器。

---

## 29. `minirv_decode.sv`

这是纯组合译码模块，主要输出：

- `next_pc`；
- 是否写寄存器；
- 写回数据；
- load/store 请求；
- `ebreak`；
- 非法指令标志。

### 29.1 RV32E 寄存器合法性

指令中寄存器编号仍有 5 位。CPU 核心取低 4 位作为数组下标，同时译码器检查最高位：

```text
bit4 = 0：x0~x15，合法
bit4 = 1：x16~x31，对 RV32E 非法
```

不能仅截断到 4 位，否则编码中的 x16 会错误地当成 x0。

### 29.2 默认值

组合块开头把所有输出设为安全默认值，例如：

```text
next_pc = pc + 4
不写寄存器
不读写数据存储器
不是 ebreak
不是非法指令
```

每种 opcode 只覆盖自己需要的输出。

### 29.3 load

总线统一返回从目标地址开始的 32 位值，译码器再根据 funct3：

- 选择 8、16 或 32 位；
- 对 `lb/lh` 做符号扩展；
- 对 `lbu/lhu` 做零扩展。

### 29.4 store

`sb/sh/sw` 使用相同的 32 位写数据，区别体现在：

```text
sb → wmask=0001
sh → wmask=0011
sw → wmask=1111
```

---

## 30. `minirv_core.sv`

核心模块连接寄存器堆和译码器，并保存：

- 当前 PC；
- 提交计数；
- 最近提交 PC；
- 最近提交机器码。

最关键的信号是 `step`。

当 `step=0`：

- 当前指令还在等待总线；
- PC 不更新；
- 寄存器不写回；
- 不产生 `commit_valid`。

当 `step=1`：

- PC 更新为 `next_pc`；
- 目的寄存器写回；
- 指令计数增加；
- `commit_valid` 拉高一个周期。

这就是 NPC 的架构提交边界。

---

## 31. `minirv_axi_lite_master.sv`

CPU 核心使用简单请求接口，但 AXI 要求多个独立握手通道。因此该模块使用状态机连接二者。

### 31.1 状态

| 状态 | 含义 |
|---|---|
| `FETCH_ADDR` | 发送取指读地址 |
| `FETCH_DATA` | 等待取指数据 |
| `LOAD_ADDR` | 发送 load 读地址 |
| `LOAD_DATA` | 等待 load 数据 |
| `STORE_SEND` | 独立发送 AW 和 W |
| `STORE_RESP` | 等待写响应 B |

### 31.2 普通指令

```text
FETCH_ADDR → FETCH_DATA → 提交 → FETCH_ADDR
```

### 31.3 load

```text
FETCH_ADDR → FETCH_DATA → LOAD_ADDR → LOAD_DATA → 提交 → FETCH_ADDR
```

### 31.4 store

```text
FETCH_ADDR → FETCH_DATA → STORE_SEND → STORE_RESP → 提交 → FETCH_ADDR
```

### 31.5 AW 和 W 为什么分别记录

AXI 写地址和写数据是两个独立通道：

- AW 可能先握手；
- W 可能先握手；
- 也可能同一拍握手。

`aw_done` 和 `w_done` 分别记录结果。只有两者都完成后，状态机才能进入 `STORE_RESP`。

已握手通道的 `valid` 会撤销，未握手通道继续保持 `valid`、地址或数据不变。

---

## 32. AXI 的五个通道

| 通道 | 全称 | 主要信号 | 方向 |
|---|---|---|---|
| AR | 读地址 | `arvalid/arready/araddr` | 主 → 从 |
| R | 读数据 | `rvalid/rready/rdata/rresp` | 从 → 主 |
| AW | 写地址 | `awvalid/awready/awaddr` | 主 → 从 |
| W | 写数据 | `wvalid/wready/wdata/wstrb` | 主 → 从 |
| B | 写响应 | `bvalid/bready/bresp` | 从 → 主 |

一次传输只在：

```text
valid == 1 && ready == 1
```

的时钟沿发生。

重要规则：

1. 发送方不能等待 `ready` 后才产生 `valid`；
2. `valid=1` 后，在握手前必须保持有效；
3. 等待握手期间地址、数据、掩码和控制信息必须稳定；
4. 读写通道可以独立推进；
5. 写事务必须等到 B 响应，不能只看到 AW/W 握手就认为完成。

---

## 33. `axi_lite_master_to_axi4.sv`

AXI4-Lite 没有 ID 和 burst 字段，而 4×4 互联使用 AXI4 风格接口。因此适配器补充：

```text
ID    = 固定读/写 ID
LEN   = 0       只有一拍
SIZE  = 2       2^2 = 4 字节
BURST = INCR
WLAST = 1
```

返回时检查：

- `RID` 是否等于固定读 ID；
- 单拍读响应是否带 `RLAST`；
- `BID` 是否等于固定写 ID。

---

## 34. `axi4_interconnect_4x4.sv`

### 34.1 打包端口

四路信号使用一个宽总线表示。例如：

```systemverilog
logic [4*32-1:0] m_araddr;
```

含义是四个 32 位地址连接成 128 位：

```text
m_araddr[31:0]    主设备 0
m_araddr[63:32]   主设备 1
m_araddr[95:64]   主设备 2
m_araddr[127:96]  主设备 3
```

SystemVerilog 的：

```systemverilog
m_araddr[index*32 +: 32]
```

表示从 `index*32` 开始向高位选择 32 位。

### 34.2 地址译码

| 地址最高 4 位 | 从设备槽 | 用途 |
|---|---:|---|
| `0x8` | 0 | 主存 |
| `0xa` | 1 | MMIO |
| `0xc` | 2 | 保留扩展窗口，目前返回错误 |
| 其他 | 3 | 默认错误窗口 |

### 34.3 仲裁

每个从设备分别扫描主设备 0~3。当前采用固定优先级：

```text
主设备 0 > 主设备 1 > 主设备 2 > 主设备 3
```

某个从设备已经选中一个请求后，不再接受同拍的其他请求。

### 34.4 ID 扩展

下游 ID 由两部分组成：

```text
{主设备编号, 原始 ID}
```

响应返回时读取高 2 位找到目标主设备，再把低位原始 ID 返回。

### 34.5 W 通道目标

W 通道没有 ID，无法单独判断属于哪个地址。因此互联在 AW 握手时记录：

- 该主设备存在未完成写事务；
- 该写事务目标从设备编号。

直到 B 响应完成才清除记录。

---

## 35. `axi4_to_lite_slave.sv` 与 `axi_lite_pmem.sv`

`axi4_to_lite_slave` 在 AR/AW 握手时保存 ID，因为后面的 Lite 接口没有 ID。Lite 响应到达后再恢复为 RID/BID。

`axi_lite_pmem` 是最终平台从设备：

- 锁存读地址；
- 等待可配置读延迟；
- 调用 `pmem_read()`；
- 保持 `rvalid/rdata` 直到握手；
- 分别锁存 AW 和 W；
- 两者都到达后等待写延迟；
- 调用 `pmem_write()`；
- 产生 B 响应。

`test-delayed` 会使用非零读写延迟重新运行 114 条指令，以证明 CPU 没有错误地假设存储器一定单周期返回。

---

## 36. `axi4_error_slave.sv`

非法地址不能直接让所有 `ready` 保持为 0，否则 CPU 会永久等待并最终只表现为超时。

错误从设备会正常接受事务，然后返回：

- `DECERR`：地址窗口不存在；
- `SLVERR`：事务格式违反当前裁剪协议。

这样仿真器能够在发起访问的指令处准确报告总线错误。

---

## 37. `top.sv`

顶层主要做四件事：

1. 连接 CPU 核心和 AXI4-Lite 主设备；
2. 通过适配器接入 4×4 AXI4 互联；
3. 汇总 Lite 响应错误、主设备协议错误和互联错误；
4. 在指令提交边界调用 DPI-C 回调。

顶层不实现具体指令语义，也不直接保存客户主存。

事件优先级为：

```text
总线错误 > 非法指令 > ebreak
```

避免一次故障同时被报告为正常结束。

---

# 第四部分：运行与调试

## 38. 常用命令

进入根目录后先加载环境：

```bash
source .envrc
```

### 38.1 构建 NPC

```bash
make -C npc
```

### 38.2 运行内置程序

```bash
make -C npc run
```

### 38.3 运行指定镜像

```bash
make -C npc run IMG=/absolute/path/program.bin MAX_CYCLES=100000
```

使用绝对路径最不容易受到 `make -C` 工作目录变化影响。

### 38.4 查看指令轨迹

```bash
make -C npc run IMG=/absolute/path/program.bin ITRACE=1
```

输出示例：

```text
0x80000000: 0x00100093  addi x1, x0, 1
```

### 38.5 生成波形

```bash
make -C npc run \
  IMG=/absolute/path/program.bin \
  WAVE=build/debug.vcd
```

只对短失败用例生成波形，避免长程序产生过大文件。

### 38.6 启用 DiffTest

```bash
make -C npc run \
  IMG=/absolute/path/program.bin \
  DIFF="$PWD/nemu/build/riscv32-nemu-interpreter-so"
```

### 38.7 关键回归

```bash
make -C npc test-itrace
make -C npc test-diff
make -C npc test-delayed
make -C npc test-bus-error
make -C npc/tests/axi-crossbar run
make -C npc/nvboard smoke
```

---

## 39. 推荐调试顺序

出现错误时，建议按以下顺序缩小问题：

### 39.1 先看错误类型

- `illegal instruction`：优先检查 opcode、funct3、funct7 和 RV32E 寄存器编号；
- `bus response error`：检查地址窗口、AXI 响应和协议错误来源；
- `DiffTest mismatch`：查看首个不一致寄存器和最近 16 条指令；
- `memory ... out of range`：检查完整物理地址和镜像/栈范围；
- `TIMEOUT`：检查状态机是否在等待某个永远不会到来的 ready/valid。

### 39.2 开启 itrace

先找到最后一条成功提交的指令，以及失败指令的 PC。

### 39.3 使用最短镜像

把失败程序缩短到只包含：

- 必要的寄存器初始化；
- 一条待测指令；
- 比较结果；
- `ebreak`。

### 39.4 最后再看波形

对 AXI 问题重点观察：

```text
state
arvalid/arready/araddr
rvalid/rready/rdata/rresp
awvalid/awready/awaddr
wvalid/wready/wdata/wstrb
bvalid/bready/bresp
core_step
commit_valid
```

---

## 40. 初学者容易混淆的概念

### 40.1 宿主机、客户程序和参考模型

- **宿主机**：运行 C++ NPC 的本机 Linux；
- **客户程序**：加载到 `0x80000000`、由 MiniRV 执行的 RISC-V 程序；
- **DUT**：Verilog 实现的 MiniRV；
- **参考模型**：NEMU；
- **仿真时间**：Verilator 的时间戳；
- **总线周期**：C++ 调用一次 `tick()`；
- **客户 uptime**：MMIO 计时器提供给 AM 程序的微秒数。

这些时间和执行主体不能混为一谈。

### 40.2 `eval()` 不等于“执行一条指令”

`eval()` 只是重新计算电路。一次指令可能需要多次 `eval()` 和多个时钟周期，只有 `commit_valid` 才表示完成了一条客户指令。

### 40.3 DPI-C 主存不等于 CPU 直接调用 C 函数

CPU 请求先经过完整总线握手，只有总线最末端的平台从设备调用 DPI-C。CPU 仍然必须等待读数据或写响应。

### 40.4 C++ 对象不是 RTL 模块

- C++ 对象存在于宿主进程中；
- RTL 模块描述硬件结构；
- `Vtop` 是 Verilator 把 RTL 转换得到的 C++ 仿真模型；
- DPI-C 是两边主动调用函数的桥梁。

---

## 41. 建议练习

建议按顺序做以下小练习，加深对代码的理解：

1. 在 `options.cpp` 增加一个只控制日志的布尔参数；
2. 在 `Memory::read()` 中临时打印某个指定地址的读取记录；
3. 用内置四条指令观察 `Simulator::tick()` 和 `commit_valid` 的关系；
4. 修改 `BUS_READ_DELAY`，比较总线周期数和指令数；
5. 画出一条 `lw` 从 FETCH 到 LOAD_DATA 的状态转换图；
6. 在 AXI 波形中寻找一次 AR 握手和对应 R 握手；
7. 在 `riscv-tests` 的短测试上开启 itrace，并对照 objdump；
8. 故意修改一条 ALU 运算，观察 DiffTest 的首个不一致和最近轨迹；完成后立即恢复修改。

不要一开始修改 4×4 互联。先熟悉 `main.cpp`、`Simulator` 和 `minirv_core`，再处理协议逻辑。

---

## 42. 文件职责速查表

### C++

| 文件 | 职责 |
|---|---|
| `csrc/main.cpp` | 仿真生命周期和最终退出结果 |
| `csrc/options.cpp` | 命令行解析 |
| `csrc/memory.cpp` | 主存和镜像加载 |
| `csrc/device.cpp` | 串口和计时器 MMIO |
| `csrc/runtime.cpp` | DPI-C 转发和结束事件 |
| `csrc/simulator.cpp` | Verilator 时钟、复位、波形、提交历史 |
| `csrc/disasm.cpp` | RV32E 调试反汇编 |
| `csrc/difftest.cpp` | NEMU 动态加载和逐指令比较 |

### RTL

| 文件 | 职责 |
|---|---|
| `vsrc/top.sv` | 仿真平台顶层和 DPI-C 事件上报 |
| `vsrc/minirv_core.sv` | PC、提交状态和模块连接 |
| `vsrc/minirv_decode.sv` | 指令译码、ALU、跳转、访存语义 |
| `vsrc/minirv_regfile.sv` | RV32E 16 个通用寄存器 |
| `vsrc/minirv_axi_lite_master.sv` | CPU 请求到 AXI4-Lite 事务 |
| `vsrc/axi_lite_master_to_axi4.sv` | Lite 主设备到单拍 AXI4 |
| `vsrc/axi4_interconnect_4x4.sv` | 译码、仲裁、ID 和响应路由 |
| `vsrc/axi4_system_interconnect.sv` | 实际连接 CPU、主存、MMIO、错误从设备 |
| `vsrc/axi4_to_lite_slave.sv` | 单拍 AXI4 到 Lite 从设备 |
| `vsrc/axi_lite_pmem.sv` | AXI4-Lite 平台从设备和 DPI-C |
| `vsrc/axi4_error_slave.sv` | 未映射地址的错误响应 |

---

## 43. 当前范围边界

当前代码只覆盖 E7“接入 SoC”之前：

- RV32E MiniRV；
- 32 位数据宽度；
- 单拍 AXI 事务；
- 受控单 outstanding；
- 主存、串口和 uptime 计时器；
- 4 主 4 从互联结构；
- NPC、DiffTest、AM 和 NVBoard 软件接入。

当前尚未包含：

- `ysyxSoC` 接入；
- AXI burst；
- cache；
- 中断和完整异常系统；
- Flash、SPI、PSRAM、UART 16550；
- 综合、STA 和物理设计。

阅读代码时不要把为后续保留的 AXI 字段误认为当前已经支持完整 burst。
