# xdtc 使用文档

本文档按“**我要完成什么任务**”组织。第一次使用先看“最小完整示例”，之后直接通过目录跳到需要的功能即可。

## 最小完整示例

### 1. Xmake 集成

推荐直接把完整仓库 clone/vendor 到项目的 `tools/xdtc`，例如：

```text
project/
├── xmake.lua
├── xdtc.lua
├── tools/
│   └── xdtc/
│       ├── xmake.lua
│       └── modules/
├── data/
│   └── root.lua
└── templates/
    └── module.sv.tpl
```

`xmake.lua`：

```lua
includes("tools/xdtc/xmake.lua")

target("app")
    set_kind("binary")
    add_rules("xdtc.codegen")
    add_files("src/*.c")
```

根 `xmake.lua` 会自动注册：

```text
xmake xdtc gen      手动生成
xdtc.codegen rule   target 构建前自动生成
```

### 2. 唯一生成配置 `xdtc.lua`

```lua
return {
    data = "data/root.lua",
    tpl = {
        {
            files = {"templates/*.tpl"},
            out = "build/generated.sv"
        }
    }
}
```

手动运行：

```sh
xmake xdtc gen
```

正常构建：

```sh
xmake
```

`xdtc.codegen` 在 target 的 `on_prepare` 阶段运行，因此生成发生在编译前。

### 3. 数据

```lua
-- data/root.lua
include("uart.lua")

return {
    project = {
        version = "1.0.0"
    }
}
```

```lua
-- data/uart.lua
return {
    soc = {
        uart0 = {
            enable = true,
            match = "module.sv.tpl",
            width = 32
        }
    }
}
```

### 4. 模板

```text
// project {{ root.project.version }}
module {{ name }};
    localparam int WIDTH = {{ width }};
endmodule
```

这里 `name` 自动为 `uart0`，`root` 自动指向完整数据树。

---

## Xmake 集成

推荐入口：

```lua
includes("tools/xdtc/xmake.lua")
```

它会按 `tools/xdtc/xmake.lua` 自身位置自动把同目录下的 `modules/` 加入 Xmake module 搜索路径，并注册手动 task 和 build rule；不需要宿主工程再调用 `add_moduledirs()`。

### 手动生成

默认读取项目根目录的 `xdtc.lua`：

```sh
xmake xdtc gen
```

使用其他配置文件：

```sh
xmake xdtc --config=configs/fpga.lua gen
```

### 编译前自动生成

```lua
target("app")
    add_rules("xdtc.codegen")
```

默认读取：

```text
<project>/xdtc.lua
```

也可覆盖：

```lua
target("app")
    add_rules("xdtc.codegen", {
        config = "configs/fpga.lua"
    })
```

### 多 target

同一个 Xmake 进程中，相同的 config 默认只执行一次：

```lua
target("a")
    add_rules("xdtc.codegen")

target("b")
    add_rules("xdtc.codegen")
```

如果确实需要每个 target 都执行：

```lua
add_rules("xdtc.codegen", {once = false})
```

如果配置文件是可选的：

```lua
add_rules("xdtc.codegen", {optional = true})
```

`optional = true` 时，配置文件不存在会直接跳过；默认不存在即报错。

### 生成新的 C/C++ 源文件

这是 Xmake 本身的扫描时序要求。若源文件在项目加载时尚不存在，普通：

```lua
add_files("build/generated.c")
```

会被 Xmake 忽略。必须写：

```lua
target("app")
    add_rules("xdtc.codegen")
    add_files("src/main.c")
    add_files("build/generated.c", {always_added = true})
```

这样 `on_prepare` 生成文件后，它会参与当前这次编译。

如果生成的是 header、Verilog、Tcl、DTS 等不直接加入 Xmake C/C++ source list 的文件，则不需要 `always_added`。

## 灵活入口

`tools/xdtc/xmake.lua + xdtc.lua + task/rule` 是推荐约定，但不是强制入口。

### 完全直接调用

```lua
local xdtc = import("xdtc")

xdtc.run({
    base_dir = os.projectdir(),
    data = "data/root.lua",
    tpl = {
        {
            files = {"templates/*.tpl"},
            out = "build/generated.sv"
        }
    }
})
```

### 加载任意配置文件

```lua
local xdtc = import("xdtc")

xdtc.run_file("configs/fpga.lua", {
    base_dir = os.projectdir()
})
```

### 不使用默认 task/rule 集成

```lua
add_moduledirs("tools/xdtc/modules")

task("my_codegen")
    on_run(function()
        local xdtc = import("xdtc")
        xdtc.run_file("configs/fpga.lua", {
            base_dir = os.projectdir()
        })
    end)
```

因此上层工程可以自由决定：

```text
配置放哪里
什么时候执行
是否使用默认 task
是否绑定某个 target
是否直接传 config table
```

## 快速索引

| 我要做什么 | 用法 |
|---|---|
| 默认 `xdtc.lua` 手动生成 | `xmake xdtc gen` |
| 编译前自动生成 | `add_rules("xdtc.codegen")` |
| 使用其他配置文件 | `--config=...` / rule 的 `config = ...` |
| 不使用默认 task/rule 集成 | `xdtc.run(...)` / `xdtc.run_file(...)` |
| 包含另一个数据文件 | `include("sub.lua")` |
| 返回本文件的数据 | `return { ... }` |
| 查询数据 | `get("soc.uart0.width")` |
| 删除字段 | `remove("soc.uart0.debug")` |
| 强制替换/创建字段 | `replace("soc.uart0.width", 64)` |
| 合并对象 | `update("soc.uart0", {width = 64})` |
| 修改根数据 | `update_root({...})` |
| 获取整个 root | `get_root()` |
| 加载数据但不生成 | `xdtc.load(...)` |
| 已有 root，执行生成 | `xdtc.generate(...)` |
| 加载 + 生成一次完成 | `xdtc.run(...)` |
| 从配置文件运行 | `xdtc.run_file(...)` |
| 给最终输出套 wrapper | task 中设置 `input_template = "..."`，见 [`input_template` 输出包装](#input_template-输出包装) |
| 只使用模板引擎 | `import("xdtc.template")` |

---

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

### 一个推荐的拆分方式

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

所有文件最终贡献到同一棵 root tree。

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

从 Addon 0.2.1 起，工程可以在 `xmake.lua` 的配置域声明数据来源。先加载辅助接口：

```lua
includes("@addon/xdtc/config")
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
local xdtc = import("xdtc")
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

独立使用模板引擎：

```lua
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

### 为什么 `import("xdtc")` 不能直接写在顶层？

`add_moduledirs()` 可以放在顶层项目 DSL；`import()` 应放在 `on_run/on_load/...` 这类脚本作用域中。

```lua
add_moduledirs("modules")

task("codegen")
    on_run(function()
        local xdtc = import("xdtc")
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

第一次接入建议直接从 `examples/generator/` 复制修改。

## 命令、动作与路径基准

`xmake xdtc [--config=路径] <gen|data|run|动作> [位置参数]` 的完整约定和例子见
[README 的命令与工程动作](../README.md#命令与工程动作)。没有子命令会报错，不隐式生成。
配置查找默认相对启动目录；显式 -P 时相对所选工程。配置内部默认相对配置文件，
绝对路径不变；数据文件 include 仍相对当前数据文件。

`xdtc.load_data(config)` 读取 load_config 返回的任务配置，只展开 data，不添加 metadata。
`xdtc.execute(script_path, data, args, {base_dir=...})` 调用脚本的 main(data, ...)；
args 是位置参数数组，脚本错误原样传播。入口和数据每次重新读取，不受 Xmake 秒级文件缓存影响。
配置文件可通过 public API 转发另一份任务配置；load_config 返回的 base_dir 已规范化为绝对路径。

应用读取器可调用 `xdtc.select_action(config, name, root)`，返回该 action 选择的独立数据对象。
select 的路径、函数及错误约定统一见 [README](../README.md#xmake-addon-命令)。
