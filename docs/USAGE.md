# xdtc 使用文档

推荐通过 Xmake Addon 使用。本页先给出可以生成并编译 C 源文件的完整例子，再说明构建接入和数据 DSL；命令、配置引用、模板与公共 API 可通过标题直接查询。工具 v0.8.0 对应 Addon 0.2.1。

## 最小完整示例

在消费工程中创建以下文件。这里生成一个返回配置值的 C 函数，应用调用它并检查结果。

```text
project/
├── xmake.lua
├── xdtc.lua
├── board.lua
├── src/main.c
└── templates/mcu.c.tpl
```

### 1. Xmake 插件和构建目标

`xmake.lua`：

```lua
add_repositories("kunyi git@github.com:wmem/xmake-addons.git")
add_addons("xdtc 0.2.1")

target("app")
    set_kind("binary")
    set_languages("c11")
    set_targetdir("build")
    add_rules("@addon/xdtc/codegen", {config = "xdtc.lua"})
    add_files("src/main.c")
    add_files("build/mcu.c", {always_added = true})
target_end()
```

### 2. 任务配置

`xdtc.lua`：

```lua
return {
    data = "board.lua",
    tpl = {
        {files = {"templates/mcu.c.tpl"}, out = "build/mcu.c"},
    },
}
```

这个文件选择数据入口和输出任务，不直接描述设备参数；`data` 指向数据 DSL 文件。一个配置可以有多个输出任务，并不限于 app_config.c／app_config.h。

### 3. 数据

`board.lua`：

```lua
return {
    mcu = {
        enable = true,
        match = "mcu.c.tpl",
        chip = "example-mcu",
        clock_mhz = 200,
    },
}
```

### 4. 模板与应用

`templates/mcu.c.tpl`：

```c
unsigned mcu_clock_mhz(void)
{
    return {{ clock_mhz }};
}
```

`src/main.c`：

```c
unsigned mcu_clock_mhz(void);

int main(void)
{
    return mcu_clock_mhz() == 200 ? 0 : 1;
}
```

### 5. 安装、生成和运行

在消费工程目录运行以下命令。工程需要支持 Addon 的 Xmake，本机验证使用 3.1.1+HEAD.3ba37a0 和宿主 C 编译器。

```sh
xmake addon --install -y kunyi@xdtc
xmake xdtc gen
xmake xdtc data
xmake
./build/app
```

生成结果为 `build/mcu.c`；`data` 向 stdout 输出展开数据；构建也会在编译前生成缺失文件。程序退出码为 0 表示配置值一致。声明依赖的工程也可以由 Xmake 自动安装插件；安装状态由 `xmake-addons.lock` 固定。已有旧版本时用 `xmake addon --upgrade -y` 更新。

## Xmake 集成

### Addon 接入

Addon 提供三种能力，按需要分别使用：

| 需要的能力 | 接入方式 |
| --- | --- |
| 命令 gen/data/run/action | 安装 Addon 后执行 `xmake xdtc ...` |
| 编译前代码生成 | `add_rules("@addon/xdtc/codegen", {config = "xdtc.lua"})` |
| 配置域声明数据引用 | `includes("@addon/xdtc/config")`，见 [配置引用接口](#xmake-配置引用接口) |

命令和生成规则不需要 include 工具源码。自定义脚本域回调用 `import("@addon.xdtc.generator")` 取得核心 API。

### 编译前自动生成

```lua
target("app")
    add_rules("@addon/xdtc/codegen", {config = "configs/xdtc.lua"})
```

规则的 `config` 默认 `xdtc.lua`，相对路径以工程根目录为基准。规则在 `on_prepare` 阶段执行，每次检查数据和模板，内容变化才写输出；缺失文件会重新生成，生成失败会阻止构建。各 target 会执行自己的规则回调，Addon 规则只提供 `config` 参数，不提供源码集成桥接的 `once/optional` 参数。

### 生成新的 C/C++ 源文件

Xmake 收集源码时生成文件可能还不存在，必须显式声明：

```lua
add_files("build/mcu.c", {always_added = true})
```

生成的头文件则由工程自己添加包含目录。生成规则不自动管理 `files/includedirs`，避免把应用源码组织交给工具决定。

## 源码方式接入

需要直接管理工具源码时，可以将仓库放到 `tools/xdtc`，然后在宿主 xmake.lua 中使用：

```lua
includes("tools/xdtc/xmake.lua")

target("app")
    set_kind("binary")
    add_rules("xdtc.codegen", {config = "xdtc.lua"})
    add_files("src/main.c")
    add_files("build/mcu.c", {always_added = true})
target_end()
```

仓库根 xmake.lua 注册 `xmake xdtc` 命令和 `xdtc.codegen` 规则，并以自身目录定位 modules；不修改宿主的项目名称或版本。源码规则名称与 Addon 规则不同，命令 gen/data/run/action 的语义相同。不要在一个工程中重复注册两种命令入口。

源码规则使用 [integration.lua](../modules/xdtc/integration.lua) 桥接，额外支持：

```lua
add_rules("xdtc.codegen", {
    config = "configs/xdtc.lua",
    once = true,
    optional = false,
})
```

`once` 默认 true：同一进程中，相同配置只执行一次；设为 false 则每次执行。`optional` 默认 false：入口缺失会报错；设为 true 则入口缺失时跳过。这些参数属于源码规则，不适用于 `@addon/xdtc/codegen`。

## 灵活入口

工程也可以自己决定何时读取或生成。在 `on_load/on_run` 等脚本域中：

```lua
local xdtc = import("@addon.xdtc.generator")
local result = xdtc.run_file("configs/xdtc.lua", {
    base_dir = os.projectdir(),
})
```

也可以直接传普通 table 给 `xdtc.run()`；此时 table 中的 `base_dir` 是数据、模板和输出的路径基准。若仅使用源码模块，先在配置域声明 `add_moduledirs("tools/xdtc/modules")`，脚本域改为 `import("xdtc")`。

## 快速索引

| 我要做什么 | 用法或入口 |
| --- | --- |
| 默认任务配置手动生成 | `xmake xdtc gen` |
| 只展开数据 | `xmake xdtc data` |
| 执行脚本／工程动作 | [命令、动作与路径基准](#命令动作与路径基准) |
| 编译前自动生成 | `add_rules("@addon/xdtc/codegen")` |
| 给规则延迟提供对象 | `board:select(...)` 返回函数，见 [配置引用接口](#xmake-配置引用接口) |
| 在脚本域立即读取对象 | `xdtc.read_config(...)` |
| 使用其他任务配置 | `--config=...`／规则的 `config` 参数 |
| 复用数据、覆盖或删除 | `include/update/replace/remove`，见 [数据 DSL](#数据-dsl) |
| 加载数据但不生成 | `xdtc.load(...)`／`xdtc.load_data(...)` |
| 已有 root，执行生成 | `xdtc.generate(...)` |
| 从任务配置生成 | `xdtc.run_file(...)` |
| 给最终输出套 wrapper | [input_template 输出包装](#input_template-输出包装) |
| 只使用模板引擎 | [xdtc.template](#xdtctemplate) |

## 数据文件

数据配置文件是普通 Lua 脚本。它可以：

1. 调用 xdtc 注入的 DSL；
2. `include()` 其他数据文件；
3. 最后 `return` 一个对象；
4. 或者不返回任何数据，只通过 DSL 修改 root。

### include

```lua
include("bus.lua")
include("ip/uart.lua")
```

路径相对于**当前数据文件所在目录**，不是固定相对于项目根目录。

重复 include 同一个规范化路径只加载一次。

循环引用会报错，例如：

```text
a.lua -> b.lua -> a.lua
```

### return

```lua
return {
    soc = {
        width = 32
    }
}
```

当前文件的执行顺序是：

```text
include / get / update / ...
        ↓
脚本执行完成
        ↓
return {...} 最后 merge 到 root
```

因此：

```lua
update("soc.name", "old")

return {
    soc = {
        name = "new"
    }
}
```

最终 `soc.name == "new"`。

### 复用公共数据（可选）

```text
data/
├── root.lua
├── buses/
│   └── apb.lua
└── ips/
    ├── uart.lua
    └── gpio.lua
```

`root.lua`：

```lua
include("buses/apb.lua")
include("ips/uart.lua")
include("ips/gpio.lua")

return {
    project = {
        version = "1.0.0"
    }
}
```

这些文件最终贡献到同一棵 root tree。这个例子用于说明公共数据复用；应用可以只有一个 board.lua，再 include 组件或 MSP 提供的默认描述。

---

## 数据 DSL

### `include(path)`

加载另一个数据文件。

```lua
include("uart.lua")
```

### `get(path)`

读取 dotted path。不存在会报错。

```lua
local width = get("soc.uart0.width")
```

Lua 数组使用 **1-based index**：

```lua
local first = get("items.1")
local second_name = get("items.2.name")
```

`get()` 返回实时对象；如果返回的是 table，对它的修改会直接影响 root：

```lua
local uart = get("soc.uart0")
uart.width = 64
```

### `remove(path)`

删除对象字段。路径不存在时忽略。

```lua
remove("soc.uart0.debug")
```

当前版本的 `remove()` 主要面向 object property，不用于删除数组元素。

### `replace(path, value)`

直接替换或创建值；缺失的对象父路径会自动创建。

```lua
replace("soc.uart0.width", 64)
replace("soc.uart0.options.parity", "none")
```

删除请用 `remove()`，`replace(..., nil)` 不允许。

### `update(path, patch)`

对象 patch 执行 deep merge：

```lua
update("soc.uart0", {
    width = 64,
    fifo = {
        depth = 16
    }
})
```

非对象值执行同类型替换，但目标必须已经存在：

```lua
update("soc.uart0.width", 64)
```

如果目标不存在或类型不同，会报错。

### `update_root(patch)`

直接 deep merge 到根节点：

```lua
update_root({
    meta = {
        version = "1.0"
    }
})
```

兼容原 JS DTC 拼写：

```lua
updateRoot({...})
```

### `get_root()`

返回实时 root：

```lua
local root = get_root()
```

---

## 合并规则

xdtc 将 Lua table 分为：

- **array**：`table[1] ~= nil`
- **object**：`table[1] == nil`

合并规则：

| target | source | 结果 |
|---|---|---|
| object | object | 递归 deep merge |
| array | array | source 整体替换 target |
| 同类型 scalar | 同类型 scalar | source 替换 target |
| 不同类型 | 不同类型 | 报错 |

例如：

```lua
-- A
return {
    uart = {
        width = 32,
        options = {parity = "none"},
        ports = {"clk", "rst"}
    }
}
```

之后 merge：

```lua
return {
    uart = {
        width = 64,
        options = {stop_bits = 1},
        ports = {"clk", "rst_n", "tx"}
    }
}
```

结果：

```lua
uart = {
    width = 64,
    options = {
        parity = "none",
        stop_bits = 1
    },
    ports = {"clk", "rst_n", "tx"}
}
```

> 注意：稀疏数组如果没有 `[1]`，当前实现会被判断为 object。配置数据应使用连续 Lua 数组。

---

## 自动 `name`

数据构建完成后，普通对象如果没有自己的 `name`，会根据父对象 key 自动补齐：

```lua
return {
    soc = {
        uart0 = {
            width = 32
        }
    }
}
```

逻辑上变成：

```lua
{
    name = "root",
    soc = {
        name = "soc",
        uart0 = {
            name = "uart0",
            width = 32
        }
    }
}
```

如果数据已经明确提供 `name`，不会覆盖。

数组中的对象不自动添加 `name`。

关闭 metadata：

```lua
local root = xdtc.load("data/root.lua", {
    metadata = false
})
```

---

## 数据与模板匹配

一个普通对象同时满足下面两个条件才成为渲染候选：

```lua
enable = true
match = "..."
```

例如：

```lua
uart0 = {
    enable = true,
    match = "module.sv.tpl",
    width = 32
}
```

`match` 与**模板 basename** 匹配：

```text
module.sv.tpl
*.tpl
uart*.tpl
module?.tpl
```

支持：

```text
*   匹配任意数量字符
?   匹配一个字符
```

数组中的对象不会参与模板候选遍历。

普通对象节点为了保证生成稳定，会按照 key 的字典序遍历，而不是依赖 Lua table 的插入顺序。

---

## 模板发现

生成任务：

```lua
{
    files = {
        "templates/**/*.tpl"
    },
    out = "build/generated.sv"
}
```

`files` 支持：

```text
*    当前路径段内任意字符
?    当前路径段内一个字符
**   零个或多个路径段
```

例如：

```text
templates/*.tpl
templates/**/*.tpl
templates/ip/uart?.tpl
```

每个 pattern 按声明顺序处理；单个 pattern 展开的文件按路径排序；重复模板文件去重并保留第一次出现的位置。

---

## 模板上下文

**当前节点没有 `item` 前缀。** 当前节点字段直接注入模板作用域。

数据：

```lua
uart0 = {
    enable = true,
    match = "module.sv.tpl",
    width = 32,
    body = "logic ready;"
}
```

模板直接使用：

```text
{{ name }}
{{ width }}
{{ body }}
```

系统还自动提供：

| 名称 | 含义 |
|---|---|
| `parent` | 当前节点父对象；root 自身没有 parent |
| `root` | 最终完整 root tree |
| `template.name` | 当前模板 basename |
| `template.path` | 当前模板完整规范化路径 |
| `output.path` | 当前任务输出文件完整规范化路径 |

例如：

```text
// node: {{ name }}
// parent: {{ parent.name }}
// project: {{ root.project.version }}
// template: {{ template.name }}
```

保留名：

```text
parent
root
template
output
```

即使数据节点存在同名字段，系统生成的上下文也优先。

---

## 模板语法

### 表达式输出

```text
{{ name }}
{{ string.format("0x%08x", base) }}
```

独立模板引擎默认 HTML-style escape；generator 默认关闭 escape。

### 原始输出

```text
{* body *}
```

始终不 escape。

### Lua 语句/控制逻辑

```text
{% for _, port in ipairs(ports) do %}
{{ port }}
{% end %}
```

```text
{% if width == 32 then %}
localparam FULL_WIDTH = 1;
{% end %}
```

### 注释

```text
{# this is not emitted #}
```

### 转义模板 opener

```text
\{{ name }}
```

输出字面量：

```text
{{ name }}
```

### 模板可用 Lua 环境

模板可以使用上下文变量，以及受限的基础能力，例如：

```text
math
string
table
pairs / ipairs
type
tonumber / tostring
echo(...)
```

模板不暴露：

```text
import
io
os
debug
require
ngx
```

模板负责“渲染”，不负责自己访问文件或启动进程。

---

## 输出聚合

对于一个 generator task：

1. 按 `files` 找到模板；
2. 每个模板找所有匹配数据节点；
3. 每个匹配节点渲染一次；
4. 去掉每段末尾多余换行；
5. 所有 fragment 用一个 `\n` 拼接；
6. 如果存在可用的 `input_template`，将聚合内容替换到其中的 `{{.}}`；
7. 最后一次性写到 `out`。

即使没有模板或没有节点匹配，默认也会创建空输出文件。

两个 task 不允许写到同一个规范化输出路径。

## `input_template` 输出包装

`input_template` 是 task 的可选字段，用于在**最终聚合内容外再套一层文件模板**。它不是 xdtc 普通模板，不执行 `{{ name }}` 或 `{% ... %}`；它只识别字面量占位符：

```text
{{.}}
```

最小用法：

```lua
{
    files = {"templates/**/*.tpl"},
    input_template = "templates/output.sv.in",
    out = "build/generated.sv"
}
```

`templates/output.sv.in`：

```text
// AUTO GENERATED - DO NOT EDIT

{{.}}

// END GENERATED
```

假设原本准备写入 `out` 的内容是：

```text
module uart0;
endmodule
```

最终输出为：

```text
// AUTO GENERATED - DO NOT EDIT

module uart0;
endmodule

// END GENERATED
```

规则固定如下：

| 情况 | 行为 |
|---|---|
| 没有配置 `input_template` | 直接把原聚合内容写入 `out` |
| 配置了路径，但文件不存在 | 直接把原聚合内容写入 `out`，不报错 |
| 文件存在且包含 `{{.}}` | 将所有 `{{.}}` 替换为原聚合内容后写入 `out` |
| 文件存在但没有 `{{.}}` | 报错，避免静默丢失生成内容 |

其他文本全部原样保留。例如 wrapper 中的 `{{ name }}` **不会**再次作为 xdtc 模板执行：

```text
{{ name }}
{{.}}
```

这里只会替换 `{{.}}`。插入进去的生成内容也不会被再次扫描，因此即使生成内容本身含有 `{{.}}`，也保持原样。

`input_template` 相对路径与 `files` / `out` 一样，以 generator 的 `base_dir` 为基准。

---

## Xmake 配置引用接口

从 Addon 0.2.1 起，工程可以在 `xmake.lua` 的配置域声明数据来源。工程需先配置插件仓库并声明该版本的依赖；已有工程可以用 `xmake addon --upgrade -y` 更新锁定版本。加载辅助接口：

```lua
includes("@addon/xdtc/config")
-- 首次解析时插件可能尚未安装；安装完成后 Xmake 会重新读取工程。
if type(xdtc_config) ~= "function" then
    return
end
local board = xdtc_config("xdtc.lua")
```

`xdtc_config(file)` 返回配置引用对象，不展开数据。`file` 默认 `xdtc.lua`，相对路径以调用处的 `xmake.lua` 所在目录为基准，声明时固定为绝对路径；绝对路径直接使用。它读取的是含 `data` 字段的任务配置入口，而不是直接执行数据 DSL 文件。

### `board:select(selector)` 返回读取函数

此方法返回一个零参数函数，**不是选出的 table**。创建函数时不加载文件，也不生成代码。使用方调用后，函数重新读取任务配置和数据文件，展开 include/remove/replace 等操作，返回两个值：选出的独立 table、实际数据文件所在的绝对目录。每次调用重新读取，已有结果不随文件变化自动更新。

```lua
local read_mcu = board:select("mcu")
local read_root = board:select(".")
local read_debug = board:select("hardware.debug")

add_rules("my.firmware", {config = read_mcu})
```

`"."` 选择完整 root，其他字符串是从 root 开始的点分对象路径。需要组合字段、选择含点号的键或数组元素时，传入函数；该函数接收展开数据的独立副本并返回 table：

```lua
add_rules("my.tools", {
    config = board:select(function(root)
        return {
            mcu = root.hardware.mcu,
            debug = root.hardware.debug,
            flash = root.tools.flash,
        }
    end),
})
```

这里有两个函数：`select` 的参数函数负责组装数据，`select` 的返回函数负责延迟读取。组装函数只处理数据，使用配置域可用的 Lua 能力；不要在其中加载模块、操作文件或执行命令。

缺失路径、非法路径、缺少 selector、标量结果、函数返回 nil 或抛出异常，均在调用读取函数时明确报错，不回退到 root。空 table 有效。函数输入与选择结果独立复制，不将使用方修改写回原始数据。读取不执行 action，不渲染模板，不增加模板 metadata。

### 使用方必须调用读取函数

`add_rules()` 的附加参数只保存声明，不会自动执行函数，也不会自动将它转换为配置对象。下面是接受 table 或读取函数的完整规则示例：

```lua
rule("my.firmware")
    on_load(function(target)
        local value = target:extraconf("rules", "my.firmware", "config")
        local base
        if type(value) == "function" then
            -- 配置域声明的回调没有 import，先绑定到当前脚本环境。
            local sandbox = import("core.sandbox.sandbox")
            local read = sandbox.fork(value):script()
            value, base = read()
        end
        assert(type(value) == "table", "config 必须为 table 或返回 table 的函数")
        assert(type(value.chip) == "string", "config.chip 必须为字符串")
        -- 根据 value 配置 target；base 用于解析数据中的相对资源路径。
    end)
rule_end()
```

规则不需要依赖 xdtc：它只接收 table 或函数，字段约定由规则维护。绑定步骤针对配置域声明的回调；不能直接假定在 `on_load` 中调用任意函数就能使用 `import`。普通静态配置也可以直接传 `config = {chip = "example"}`。

## 公共 API

### `xdtc.version()`

返回当前 xdtc 版本号，例如：

```lua
print(xdtc.version()) -- 0.8.0
```

### `xdtc.load_config(config_path, opt)`

加载一个独立的任务配置文件，但不执行生成。配置文件必须 `return` 一个 table：

```lua
local config, filepath = xdtc.load_config("xdtc.lua", {
    base_dir = os.projectdir()
})
```

配置文件运行在 Xmake Lua sandbox 中，可使用 import 和常见 Xmake Lua 基础 API；`os.scriptdir()` 指向该配置文件所在目录。

### `xdtc.load_data(config)`

读取 `load_config()` 返回的任务配置，展开其 `data` 文件，返回完整 root；不增加模板 metadata，也不执行模板或 action。

```lua
local description = xdtc.load_config("xdtc.lua")
local root = xdtc.load_data(description)
```

### `xdtc.select_action(config, name, root)`

按 `config.actions[name].select` 选择已有 root 中的对象，立即返回独立 table，不执行 action 脚本、不重新加载数据。选择规则见 [action 输入](#action-输入)。

```lua
local tools = xdtc.select_action(description, "inspect", root)
```

这与 `board:select()` 返回读取函数不同。未知 action、错误声明或选择结果不是 table 时失败。

### `xdtc.execute(script_path, data, args, opt)`

调用脚本的 `main(data, ...)`，返回脚本结果。`args` 是位置参数数组，默认空数组；`opt.base_dir` 用于解析相对脚本路径，默认当前工作目录。入口模块按脚本自己的目录加载；缺失脚本、缺少 main 或脚本执行失败会报错。

```lua
xdtc.execute("scripts/inspect.lua", tools, {"message"}, {
    base_dir = description.base_dir,
})
```

### `xdtc.read_config(config_path, selector, opt)`

脚本域的立即读取接口，返回选中的 table 和实际数据文件目录；selector 与上述配置引用接口一致，`opt.base_dir` 只用于定位任务配置入口。它不返回读取函数：

```lua
local xdtc = import("@addon.xdtc.generator")
local mcu, directory = xdtc.read_config("xdtc.lua", "mcu", {
    base_dir = os.projectdir(),
})
```

配置域的 `board:select()` 返回回调，该回调调用这里的立即读取接口。

### `xdtc.run_file(config_path, opt)`

从配置文件执行完整流程：

```lua
local result = xdtc.run_file("xdtc.lua", {
    base_dir = os.projectdir()
})
```

支持浅层 top-level override：

```lua
xdtc.run_file("xdtc.lua", {
    base_dir = os.projectdir(),
    overrides = {
        write = false
    }
})
```

调用选项的 `base_dir` 只控制相对 `config_path` 的查找。配置内部路径默认相对于配置文件所在目录；配置中的 `base_dir` 可以显式覆盖，若它是相对路径，也相对于配置文件。绝对路径直接使用。

### `xdtc.load(entry_path, opt)`

只构建数据树：

```lua
local xdtc = import("@addon.xdtc.generator")
local root = xdtc.load("data/root.lua")
```

选项：

```lua
{
    metadata = true -- 默认 true
}
```

`xdtc.build()` 是 `xdtc.load()` 的别名。

### `xdtc.generate(root, tasks, opt)`

已有 root 时执行匹配和渲染：

```lua
local outputs = xdtc.generate(root, {
    {
        files = {"templates/*.tpl"},
        input_template = "templates/output.sv.in", -- optional
        out = "build/generated.sv"
    }
}, {
    base_dir = os.projectdir(),
    write = true,
    metadata = true,
    escape = false,
    cache = true
})
```

主要选项：

| 选项 | 默认 | 含义 |
|---|---:|---|
| `base_dir` | 当前工作目录 | task 相对路径基准 |
| `write` | `true` | `false` 时只返回内容，不写文件 |
| `metadata` | `true` | 是否补自动 `name` |
| `escape` | `false` | generator 的默认输出转义策略 |
| `cache` | `true` | 模板编译缓存 |

每个 task 支持：

| 字段 | 必须 | 含义 |
|---|---:|---|
| `files` | 是 | 模板文件或 glob 列表 |
| `out` | 是 | 最终输出文件 |
| `input_template` | 否 | 最终输出 wrapper；不存在时自动回退为直接输出 |
| `escape` | 否 | 覆盖 generator 的输出转义策略 |

例如单独覆盖 `escape`：

```lua
{
    files = {"templates/report.tpl"},
    out = "build/report.html",
    escape = true
}
```

返回值：

```lua
outputs[1] = {
    index = 1,
    output = "/abs/path/build/generated.sv",
    templates = {...},
    input_template = "/abs/path/templates/output.sv.in", -- nil when not configured
    input_template_applied = true, -- false when missing/not configured
    content = "...", -- final content after input_template wrapping
    debug = {...}
}
```

`debug` 会记录每个模板匹配到的数据 path。

### `xdtc.run(config)`

最常用的一站式 API：

```lua
local result = xdtc.run({
    base_dir = os.projectdir(),
    data = "data/root.lua",
    tpl = {
        {
            files = {"templates/**/*.tpl"},
            out = "build/generated.sv"
        }
    }
})
```

返回：

```lua
{
    root = <最终数据树>,
    outputs = <generate 返回结果>,
    debug_data = <metadata 注入前的数据快照>,
    debug_match = <模板匹配调试记录>
}
```

`debug_data` / `debug_match` 无论是否配置文件输出路径都会返回，便于测试或上层工具直接消费。

支持全局选项：

```text
metadata
escape
cache
write
debug_data_out / debugDataOut
debug_match_out / debugMatchOut
```

## 调试输出

需要确认“数据最后到底合成了什么”或“某个模板究竟匹配了哪些节点”时，不需要改模板打印日志。直接在 `xdtc.run()` 中打开两个可选输出：

```lua
xdtc.run({
    base_dir = os.projectdir(),
    data = "data/root.lua",

    debug_data_out = "build/debug/global-data.json",
    debug_match_out = "build/debug/match-data.json",

    tpl = {
        {
            files = {"templates/**/*.tpl"},
            out = "build/generated.sv"
        }
    }
})
```

也兼容 DTC 原来的 camelCase 名称：

```lua
debugDataOut = "build/debug/global-data.json"
debugMatchOut = "build/debug/match-data.json"
```

`debug_data_out` 在自动注入 `name` **之前**截取，因此用于观察真正由数据文件构建出的原始 root；里面不会出现自动 `name` 或 `parent`。

`debug_match_out` 在 metadata 完成后输出，每个模板记录包含：

```json
[
  {
    "templatePath": "/abs/path/module.tpl",
    "matchedObjects": [
      {
        "name": "uart0",
        "enable": true,
        "match": "module.tpl"
      }
    ]
  }
]
```

`matchedObjects` 不包含 `parent` 引用，因此 JSON 不会因为父子循环引用而无法输出。

### `xdtc.template`

Addon 中先载入公共模块以注册私有运行资源，再使用模板模块；以下代码运行在脚本域：

```lua
import("@addon.xdtc.generator")
local template = import("xdtc.template")

local text = template.render("module {{ name }};", {
    name = "uart"
}, {
    escape = false
})
```

文件模板：

```lua
local text = template.render_file(
    "templates/module.sv.tpl",
    {name = "uart"},
    {escape = false}
)
```

可复用编译结果：

```lua
local render = template.compile("{{ value }}", {
    escape = false
})

print(render({value = "a"}))
print(render({value = "b"}))
```

公开函数：

```text
render(source, context, opt)
render_file(filepath, context, opt)
compile(source, opt)
compile_file(filepath, opt)
parse(source, opt)
output(value)
escape(value)
clear_cache()
```

---

## 常见问题

### 为什么 `import()` 不能直接写在 xmake.lua 顶层？

`import()` 应放在 `on_run/on_load/...` 等脚本域中。配置域需要数据引用时使用 `xdtc_config(file):select(...)`，由规则调用返回函数；源文件的 `add_moduledirs()` 声明只用于直接接入源码。

```lua
task("codegen")
    on_run(function()
        local xdtc = import("@addon.xdtc.generator")
        -- ...
    end)
```

### 为什么模板里没有 `item.name`？

这是刻意设计。当前节点字段直接进入模板 scope：

```text
{{ name }}
```

而不是：

```text
{{ item.name }}
```

### `parent` 会写回数据树吗？

不会。`parent/root/template/output` 都只在渲染 context 中生成，不修改数据结构。

### 为什么数组里的对象没有自动 `name`？

这是与 DTC 匹配逻辑保持一致的行为。数组被视为一个值，不递归作为可匹配数据节点集合。

### 为什么生成顺序不是 Lua 文件中的对象书写顺序？

Lua table 不提供可靠对象插入顺序。为了 reproducible build，普通对象 key 使用字典序遍历。

需要显式顺序的数据应放进数组，并由模板自己遍历该数组。

---

## 示例目录

```text
examples/basic/       只构建 root tree
examples/template/    只使用模板引擎
examples/generator/   数据匹配 + 模板 + 代码生成
```

这些示例演示源码模块，`examples/integration/` 另演示源码规则。Addon 工程从本页的最小完整示例开始；运行仓库示例的方法见 [开发文档](DEVELOPMENT.md#示例-smoke-test)。

## 命令、动作与路径基准

### 命令格式

在消费工程中执行：

```sh
xmake xdtc gen
xmake xdtc data
xmake xdtc run scripts/check.lua message
xmake xdtc inspect message
xmake xdtc --config=configs/xdtc.lua gen
```

语法为 `xmake xdtc [选项] <gen|data|run|动作名> [位置参数]`，选项必须放在子命令前。

| 子命令 | 数据和行为 | 位置参数 |
| --- | --- | --- |
| `gen` | 按配置的 tpl 生成文件，默认添加模板 metadata | 不接受 |
| `data` | 展开完整 root，向 stdout 输出可加载的 `return {...}` Lua 文本 | 不接受 |
| `run` | 展开完整 root，交给指定脚本的 main | 第一个是脚本路径，其余转发 |
| action 名 | 展开 root，按 action.select 选择对象，交给 action.script 的 main | 全部转发 |

`data/run/action` 不添加模板 metadata，保留未启用节点和模板描述字段；不渲染模板、不写生成文件。run 和 action 脚本自己执行的文件或硬件操作由脚本负责。没有子命令、未知动作、保留名称冲突、错误 action 声明、脚本缺少 main 或执行失败，均非零退出。CLI 会检查所有 actions 的声明，但 gen/data 不调用选择函数。旧的无子命令生成和 action 路径字符串形式不再接受。

### action 输入

在最小完整示例的 xdtc.lua 中增加 action：

```lua
return {
    data = "board.lua",
    tpl = {
        {files = {"templates/mcu.c.tpl"}, out = "build/mcu.c"},
    },
    actions = {
        inspect = {script = "scripts/inspect.lua", select = "mcu"},
    },
}
```

`scripts/inspect.lua` 接收选中的 MCU 对象：

```lua
function main(mcu, message)
    print("%s: %s", message or "inspect", mcu.chip)
end
```

`xmake xdtc inspect demo` 输出 `demo: example-mcu`。inspect、flash、console 等名字均由工程声明，xdtc 不内置这些操作。

select 必须显式填写。`"."` 选择整个 root，其他字符串选择点分对象路径，例如 `"mcu"` 或 `"tools.debug"`。函数可组装对象：

```lua
select = function(root)
    return {mcu = root.hardware.processor, debug = root.tools.debug}
end
```

字符串选择和函数返回值必须为 table；空 table 有效，缺失路径、非法路径、标量、nil 和选择函数异常均报错，不回退 root。含点号的字段名或数组下标用函数选择。函数接收独立副本，返回对象也独立复制；脚本修改不会影响原始 root。脚本只约定输入字段，树结构变化由 action 的选择配置适配。

run 不应用 action 的 select。例如 `scripts/check.lua` 接收完整 root：

```lua
function main(root, message)
    print("%s: %s", message or "check", root.mcu.chip)
end
```

运行 `xmake xdtc run scripts/check.lua demo` 同样输出 `demo: example-mcu`，但输入形状与 inspect action 不同。

### 路径基准

| 路径来源 | 相对路径的基准 |
| --- | --- |
| CLI 的 --config；未指定时的 xdtc.lua | 启动目录；显式 -P 时是所选工程目录 |
| Addon／源码代码生成规则的 config 参数 | 工程根目录 |
| xdtc_config(file) 的 file 参数 | 声明处的 xmake.lua 所在目录 |
| load_config/run_file/read_config 的配置入口 | opt.base_dir；未指定时是当前工作目录 |
| 任务配置内的 data、模板、输出、run／action 脚本 | 该任务配置文件的目录，或它显式声明的 base_dir |
| 数据 DSL 的 include | 当前执行的数据文件目录 |

绝对路径直接使用。任务配置中的相对 base_dir 也以配置文件目录为基准；API 的 opt.base_dir 只定位配置入口，不改变配置内部的路径基准。直接 `xdtc.run(table)` 时，table 中的 base_dir 用于解析数据和生成任务。

公共目录可定义一次：

```lua
local components = path.absolute("../components", os.scriptdir())
return {
    data = "board.lua",
    tpl = {{files = {path.join(components, "msp/templates/*.tpl")}, out = "build/config.c"}},
}
```

配置文件可以使用 import；数据 DSL 不提供 import，复用数据用 include。普通数据字符串不自动转为绝对路径；消费方使用读取函数返回的数据文件目录解析自己的相对资源字段。

工程根目录的 xdtc.lua 也可以转发子工程入口：

```lua
local xdtc = import("@addon.xdtc.generator")
return xdtc.load_config(path.join(os.scriptdir(), "project/template/xdtc.lua"))
```

返回的 base_dir 已规范化为绝对路径，内部资源继续跟随子工程配置。配置、数据和执行脚本每次读取时绕过 Xmake 的秒级文件缓存；模板编译缓存由生成选项单独管理。
