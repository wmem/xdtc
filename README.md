# xdtc v0.5.0

## Xmake Addon 命令

本仓库提供 Addon `xdtc`，安装后可以在消费工程中直接运行 `xmake xdtc`，无需复制工具源码或在工程中 `includes()`。默认读取工程根目录 `xdtc.lua`，`--config=<路径>` 可选择其他配置；相对路径按工程根目录定位，其他目录执行时使用 `-P <工程目录>`。

分发配方位于 [xmake-addons-repo](../xmake-addons-repo/README.md)，由工具自己的 [准备脚本](scripts/prepare-addon.lua)安装运行资源。现有工程内接入入口保持可用。Addon `0.1.1` 同时提供命名空间代码生成规则与核心 API：

```lua
add_repositories("kunyi git@github.com:wmem/xmake-addons.git")
add_addons("xdtc 0.1.x")
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
xmake xdtc
xmake xdtc --config=xdtc.lua
xmake xdtc -P /path/to/project --help
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
xmake xdtc          手动生成，默认读取 <project>/xdtc.lua
xdtc.codegen        target 编译前自动生成，同样读取 <project>/xdtc.lua
```

因此可以：

```sh
xmake xdtc
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
xmake xdtc --config=configs/fpga.lua
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

项目版本以 [`modules/xdtc.lua`](modules/xdtc.lua) 中的 `VERSION` 为准；`xdtc.version()` 返回不带 `v` 前缀的 `主版本.次版本.修订号`，Git 发布标签使用 `v` 前缀，例如 `v0.5.0`。仓库的 `xmake.lua` 不设置版本，以免覆盖宿主项目的版本信息。

发布新版本时，修改 `VERSION`，同步本页标题和 [USAGE 中的版本示例](docs/USAGE.md#xdtcversion)，运行下方的完整回归测试；提交后，在该提交上创建同号 Git 标签。版本测试会检查 API 返回值与两处文档展示一致。

## 测试

```sh
XMAKE_ROOT=y /path/to/xmake lua tests/all.lua --root
```

当前回归：数据层 5、模板层 8、generator 6、DTC 兼容 11、config 3、integration 2，共 **35/35 PASS**。另外有真实宿主工程 smoke test 验证：

```lua
includes("tools/xdtc/xmake.lua")
```

能够从宿主工程根目录读取 `xdtc.lua`，并在同一次 Xmake 构建中生成并编译新的 C 源文件。

## Attribution

模板语法和部分 parser 设计来自 Aapo Talvensaari 的 `lua-resty-template`。BSD License 保留在：

```text
third_party/lua-resty-template-LICENSE
```
