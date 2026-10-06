# xdtc v0.7.0

## Xmake Addon 命令

本仓库提供 Addon `xdtc`，安装后可以在消费工程中直接运行 `xmake xdtc gen`，无需复制工具源码或在工程中 `includes()`。默认读取启动目录的 `xdtc.lua`，`--config=<路径>` 可选择其他配置；显式 `-P <工程目录>` 时按该工程目录查找。选项必须位于子命令之前。

分发配方位于 [xmake-addons-repo](../xmake-addons-repo/README.md)，由工具自己的 [准备脚本](scripts/prepare-addon.lua)安装运行资源。现有工程内接入入口保持可用。Addon `0.2.0` 提供新的 gen/data/run/action 命令入口，并继续提供命名空间代码生成规则与核心 API：

```lua
add_repositories("kunyi git@github.com:wmem/xmake-addons.git")
add_addons("xdtc 0.2.x")
target("app")
    set_kind("binary")
    add_rules("@addon/xdtc/codegen", {config = "xdtc.lua"})
    add_files("src/*.c")
    add_files("build/generated.c", {always_added = true})
```

规则每次构建检查数据和模板，仅在输出内容变化时写入；缺失输出会重新生成，
生成错误会阻止编译。规则的 `config` 默认 `xdtc.lua`，相对路径以工程根目录为基准。
自定义构建回调也可以 `import("@addon.xdtc.generator")` 使用已有 `run_file()`、
`run()` 等 API，核心实现只维护在 `modules/`。

```sh
xmake xdtc gen
xmake xdtc --config=xdtc.lua gen
xmake xdtc -P /path/to/project --help
```

## 命令与工程动作

```sh
xmake xdtc gen
xmake xdtc data
xmake xdtc run scripts/check.lua argument
xmake xdtc flash
xmake xdtc --config=configs/board.lua gen
```

`gen`、`data`、`run` 是保留命令，其他名称从配置的 `actions` 查找。
`gen` 按 `tpl` 生成文件；`data` 只展开配置的 `data`，向 stdout 输出可加载的
`return {...}` Lua 文本；`run` 把完整展开数据传入脚本的 `main(config, ...)`；action 按 select 筛选输入。
后续位置参数原样传给脚本。没有子命令、未知动作、保留名称冲突、脚本缺少 main 或执行报错均失败退出。
原来的隐式生成命令 `xmake xdtc --config=...` 已改为显式 `gen`，不保留旧 CLI 调用方式。
自动构建规则与 `run_file()` 仍用于生成，无需改为启动 CLI 子进程。

```lua
local components = path.absolute("../components", os.scriptdir())
return {
    data = "user_config/app_config.lua",
    tpl = {{files = {"templates/*.tpl"}, out = "user_code/app_config.c"}},
    actions = {
        flash = {
            script = path.join(components, "msp/tools/actions/flash.lua"),
            select = "tools.flash",
        },
    },
}
```

action 必须为 `{script, select}`，不再接受旧的脚本路径字符串；迁移完整 root 输入时显式写
`select = "."`。其他字符串是从 root 开始的点分对象路径，例如 `"serial"`、`"tools.console"`。
字符串选择与函数返回值必须是 table；空 table 可用，缺失路径、标量、nil 或筛选异常均报错，
不会回退为 root。包含点号的字段名或数组下标可以通过 Lua 函数选择。

```lua
select = function(root)
    return {debug = root.board.debug, flash = root.tools.flash}
end
```

只有选择配置依赖数据树布局；脚本维护自己输入对象的字段契约。函数接收独立数据副本，
筛选结果也独立复制，避免修改影响后续生成或其他动作。gen/data 不执行 select；run 保持完整
root 的通用脚本入口。`xdtc.select_action(config, name, root)` 供应用读取器复用同一选择逻辑。

配置内部的 `data`、模板、输出和脚本路径默认相对于该配置文件；绝对路径直接使用。
显式 `base_dir` 可覆盖，若它是相对路径，也相对于配置文件。API 选项 `base_dir`
只决定到哪里查找配置文件，不再改变配置内部的默认基准。
数据文件的 `include()` 始终相对当前数据文件；普通数据字符串不自动转换为路径。
公共目录用 local 变量和 `path.absolute/path.join` 定义一次。

`data/run/action` 不添加模板 metadata，保留未启用节点和模板描述字段，不写生成文件。
脚本按其自己的目录解析模块，操作的字段契约由脚本维护；xdtc 不内置 MCU 或烧录逻辑。
配置文件允许使用 Xmake 的 import；数据 DSL 仍通过 include 加载数据。
工程可用公开 API 转发配置入口：

```lua
local generator = import("@addon.xdtc.generator")
return generator.load_config(path.join(os.scriptdir(), "project/template/xdtc.lua"))
```

本地开发需先准备完整插件目录，再交给 Xmake 安装。直接从源码 Git URL 或原始目录安装只会复制 Addon 内容，不执行分发配方，因此不会自动准备运行资源。

```sh
xmake lua scripts/prepare-addon.lua /tmp/xdtc-addon-stage
xmake addon --install /tmp/xdtc-addon-stage
```

准备脚本拒绝覆盖已有输出目录。验证统一由索引仓库的 [插件集成测试](../xmake-addons-repo/tests/test_addons.py)覆盖，原有工具测试仍可独立执行。

`xdtc` 是一个运行在 **Xmake 内置 Lua** 上的数据树、模板和代码生成工具。开发方式延续 DTC：多个 Lua 数据文件构建唯一 `root`，数据节点通过 `enable + match` 选择模板，最终聚合输出文件。

不需要系统 Lua、LuaJIT、LuaRocks、Node.js、OpenResty 或 nginx。

## 源码方式接入

推荐直接把仓库 clone 到宿主工程的 `tools/xdtc`：

```text
project/
├── xmake.lua
├── xdtc.lua
├── tools/
│   └── xdtc/
│       ├── xmake.lua
│       ├── modules/
│       └── docs/
├── data/
└── templates/
```

宿主 `xmake.lua` 只需要：

```lua
includes("tools/xdtc/xmake.lua")

target("app")
    set_kind("binary")
    add_rules("xdtc.codegen")
    add_files("src/*.c")
```

项目根目录的 `xdtc.lua`：

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

`tools/xdtc/xmake.lua` 自动注册：

```text
xmake xdtc gen      手动生成，默认读取 <project>/xdtc.lua
xdtc.codegen        target 编译前自动生成，同样读取 <project>/xdtc.lua
```

因此可以：

```sh
xmake xdtc gen
xmake
```

## 保持灵活

`xdtc.lua` 是推荐约定，不是强制入口。仍然支持：

```lua
local xdtc = import("xdtc")

-- 直接传配置
xdtc.run({...})

-- 任意配置文件
xdtc.run_file("configs/fpga.lua", {
    base_dir = os.projectdir()
})
```

rule 也能覆盖默认配置：

```lua
add_rules("xdtc.codegen", {
    config = "configs/fpga.lua",
    once = true,
    optional = false
})
```

手动 task：

```sh
xmake xdtc --config=configs/fpga.lua gen
```

如果完全不想使用 `tools/xdtc/xmake.lua` 的 task/rule 集成，也可以只添加模块目录，在自己的 callback 中调用 `xdtc.run()` / `xdtc.run_file()`。

## 最小数据与模板

`data/root.lua`：

```lua
return {
    uart0 = {
        enable = true,
        match = "module.sv.tpl",
        width = 32
    }
}
```

`templates/module.sv.tpl`：

```text
module {{ name }};
    localparam int WIDTH = {{ width }};
endmodule
```

`name` 自动生成；模板还会自动得到 `parent`、`root`、`template`、`output`。

## 生成 C/C++ 源文件时

如果生成的 `.c/.cpp` 在项目加载时还不存在，需要：

```lua
target("app")
    add_rules("xdtc.codegen")
    add_files("src/main.c")
    add_files("build/generated.c", {always_added = true})
```

这是 Xmake 的 source 扫描时序要求。生成 header、Verilog、Tcl、DTS 等不直接进入 C/C++ source list 的文件不需要 `always_added`。

## 快速导航

| 需求 | 文档 |
|---|---|
| clone 到 `tools/xdtc` 后怎么接入 | [USAGE：Xmake 集成](docs/USAGE.md#xmake-集成) |
| 自定义配置路径 / 不使用默认集成 | [USAGE：灵活入口](docs/USAGE.md#灵活入口) |
| `include` / `return` / 数据合并 | [USAGE：数据文件](docs/USAGE.md#数据文件) |
| `get/update/replace/remove` | [USAGE：数据 DSL](docs/USAGE.md#数据-dsl) |
| `enable/match` | [USAGE：数据与模板匹配](docs/USAGE.md#数据与模板匹配) |
| 模板上下文 | [USAGE：模板上下文](docs/USAGE.md#模板上下文) |
| `input_template` / `{{.}}` | [USAGE：input_template](docs/USAGE.md#input_template-输出包装) |
| 内部架构与扩展原则 | [DEVELOPMENT](docs/DEVELOPMENT.md) |
| DTC 原测试迁移情况 | [DTC-TEST-COVERAGE](docs/DTC-TEST-COVERAGE.md) |

## 核心约定

- 所有数据最终合并为唯一 `root`。
- 普通对象自动生成 `name`；数组对象不自动生成 metadata，也不参与模板匹配。
- 节点只有 `enable = true` 且 `match` 命中模板文件名时才渲染。
- 模板当前节点字段直接使用，如 `{{ name }}`，没有 `item` 前缀。
- `parent/root/template/output` 自动注入。
- generator 默认 `escape = false`。
- `input_template` 可选；存在时用 `{{.}}` 包装最终聚合内容，不存在则直接输出。
- 默认项目配置是 `<project>/xdtc.lua`，但公共 API 不依赖这个约定。

## 版本管理

项目版本以 [`modules/xdtc.lua`](modules/xdtc.lua) 中的 `VERSION` 为准；`xdtc.version()` 返回不带 `v` 前缀的 `主版本.次版本.修订号`，Git 发布标签使用 `v` 前缀，例如 `v0.7.0`。仓库的 `xmake.lua` 不设置版本，以免覆盖宿主项目的版本信息。

发布新版本时，修改 `VERSION`，同步本页标题和 [USAGE 中的版本示例](docs/USAGE.md#xdtcversion)，运行下方的完整回归测试；提交后，在该提交上创建同号 Git 标签。版本测试会检查 API 返回值与两处文档展示一致。

## 测试

```sh
XMAKE_ROOT=y /path/to/xmake lua tests/all.lua --root
```

当前回归：数据层 5、模板层 8、generator 6、DTC 兼容 11、config 3、integration 2，加上命令层 9，共 **44/44 PASS**。另外有真实宿主工程 smoke test 验证：

```lua
includes("tools/xdtc/xmake.lua")
```

能够从宿主工程根目录读取 `xdtc.lua`，并在同一次 Xmake 构建中生成并编译新的 C 源文件。

## Attribution

模板语法和部分 parser 设计来自 Aapo Talvensaari 的 `lua-resty-template`。BSD License 保留在：

```text
third_party/lua-resty-template-LICENSE
```
