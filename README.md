# xdtc v0.9.0

xdtc 是运行在 **Xmake 内置 Lua** 上的数据树和代码生成工具。工程用 Lua 描述配置，用模板描述代码；xdtc 展开继承、覆盖和删除操作后，按配置生成文件，也可以把选出的数据交给构建规则或操作脚本。

推荐通过 Xmake Addon 使用。当前工具版本为 **v0.9.0**，对应 Addon **0.9.0**；Addon 与工具发布版本统一。需要支持 `add_addons` 的 Xmake，本机验证版本为 `3.1.1+HEAD.3ba37a0`。xdtc 不需要系统 Lua、Node.js 或其他语言运行时。

## 工程中的文件如何配合

| 文件 | 职责 |
| --- | --- |
| `xmake.lua` | 声明插件、构建目标和规则；使用方决定怎样消费配置 |
| `xdtc.lua` | 选择数据入口、模板输出任务和 action 的脚本及输入对象 |
| `board.lua` | 工程配置数据；可 include 包内默认描述后覆盖差异 |
| `templates/*.tpl` | 把数据转换为 C、头文件或其他文本 |
| 操作脚本 | 定义 `main(data, api, ...)`，使用传入对象执行操作 |

一个工程可以只维护一份 `board.lua`。`include/remove/replace/update` 用于复用与调整已有描述，不要求把应用配置拆成多个文件。所有数据最终形成一棵 root；xdtc 不规定其中的 MCU、串口或工具对象必须放在哪一级。

## 最小接入

在消费工程中创建以下四个文件。

`xmake.lua`：

```lua
add_repositories("kunyi git@github.com:wmem/xmake-addons.git")
add_addons("xdtc 0.9.0")

target("generated")
    set_kind("phony")
    add_rules("@addon/xdtc/codegen", {config = "xdtc.lua"})
target_end()
```

`xdtc.lua`：

```lua
return {
    data = "board.lua",
    tpl = {
        {files = {"templates/mcu.c.tpl"}, out = "build/mcu.c"},
    },
}
```

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

`templates/mcu.c.tpl`：

```c
unsigned mcu_clock_mhz(void)
{
    return {{ clock_mhz }};
}
```

在该工程目录运行：

```sh
xmake xdtc gen     # 按 xdtc.lua 生成 build/mcu.c
xmake xdtc data    # 向 stdout 输出展开后的 return {...} Lua 数据
xmake             # 构建 generated 目标，编译前执行生成规则
```

Addon 的命令和代码生成规则不需要复制源码或 `includes()`。规则每次构建读取数据和模板，仅在内容变化时写入输出；缺失输出会重新生成，错误会阻止构建。这个示例只生成文件；若要将生成的 C/C++ 编入目标，显式加入 `add_files("build/mcu.c", {always_added = true})`，详见 [Xmake 集成](docs/USAGE.md#xmake-集成)。

## 命令与工程动作

| 命令 | 输入和行为 |
| --- | --- |
| `xmake xdtc gen` | 按 `tpl` 生成文件 |
| `xmake xdtc data` | 展开完整数据，输出可加载的 Lua 文本 |
| `xmake xdtc run scripts/check.lua arg` | 把完整数据交给脚本的 `main(root, api, ...)` |
| `xmake xdtc inspect arg` | 从 `actions.inspect` 选择脚本和输入对象后执行 |

`gen/data/run` 是保留命令；其他名称由工程声明。没有子命令会报错，不隐式生成。选项放在子命令前，例如 `xmake xdtc --config=configs/xdtc.lua gen`。

`data/run/action` 不增加模板 metadata，不写生成文件；脚本自己产生的副作用由脚本负责。action 用 `{script, select}` 声明，select 支持 root、子对象和函数组装。脚本只需维护输入字段约定，数据树改组时修改选择即可。完整用法和错误约定见 [命令、动作与路径基准](docs/USAGE.md#命令动作与路径基准)。

run 和 action 均调用 `main(data, api, ...)`：第一个参数为数据，第二个为本次执行的能力对象，其余为命令行位置参数。脚本自行决定是否调用 `api.template.render/render_file`；xdtc 不注入全局 api，也不自动渲染。已有接收位置参数的脚本需要将它们移到第三个参数开始，详见 [脚本 API](docs/USAGE.md#脚本-api)。

## 给构建规则提供配置

Addon 0.9.0 提供配置引用接口。下面是调用已定义的 `my.firmware`、`my.tools` 规则的片段：

```lua
includes("@addon/xdtc/config")
if type(xdtc_config) ~= "function" then
    return -- 首次安装声明的插件后，Xmake 会重新读取工程。
end
local board = xdtc_config("xdtc.lua")

add_rules("my.firmware", {
    config = board:select("mcu"),
})
add_rules("my.tools", {
    config = board:select_action("toolconfig"),
})
```

**`board:select()` 和 `board:select_action()` 返回读取函数，不返回 table，也不会自动执行。** 使用方在脚本域绑定并显式调用函数，才取得选中的 table 和数据文件目录。`select` 用字符串选择已有对象或用函数组装对象；`select_action` 复用 `xdtc.lua` 中对应 action 的筛选，仅读取输入，不执行脚本；xdtc 不替规则解释字段。使用方完整代码见 [配置引用接口](docs/USAGE.md#xmake-配置引用接口)。

在 `on_load/on_run` 等脚本域需要立即读取时，可以直接使用公开 API：

```lua
local xdtc = import("@addon.xdtc.generator")
local mcu, directory = xdtc.read_config("xdtc.lua", "mcu", {
    base_dir = os.projectdir(),
})
```

这里 `read_config()` 立即返回 table，与配置引用的读取函数不同。生成、选择和脚本执行 API 见 [公共 API](docs/USAGE.md#公共-api)。

## 路径与数据约定

CLI 默认从启动目录找 `xdtc.lua`，显式 `-P` 时从所选工程目录查找。任务配置内的数据、模板、输出和 action 脚本路径默认相对该配置文件；数据 DSL 的 `include()` 相对当前数据文件。绝对路径直接使用，普通数据字符串不自动转换为路径。

生成时，节点只有 `enable = true` 且 `match` 命中模板才渲染。当前节点字段直接用于 `{{ field }}`，自动上下文包括 `name/parent/root/template/output`；数组中的对象不作为独立模板节点。精确规则见 [数据与模板匹配](docs/USAGE.md#数据与模板匹配)和 [模板上下文](docs/USAGE.md#模板上下文)。

## 阅读入口

| 需要了解什么 | 文档 |
| --- | --- |
| 安装插件、自动生成、把生成源码编入目标 | [USAGE：Xmake 集成](docs/USAGE.md#xmake-集成) |
| gen/data/run/action、对象筛选和相对路径 | [USAGE：命令、动作与路径基准](docs/USAGE.md#命令动作与路径基准) |
| 配置引用返回的函数如何被规则调用 | [USAGE：配置引用接口](docs/USAGE.md#xmake-配置引用接口) |
| include、覆盖、删除和合并 | [USAGE：数据文件](docs/USAGE.md#数据文件)、[数据 DSL](docs/USAGE.md#数据-dsl) |
| 模板语法和输出包装 | [USAGE：模板语法](docs/USAGE.md#模板语法)、[input_template](docs/USAGE.md#input_template-输出包装) |
| 不使用 Addon，直接接入源码 | [USAGE：源码方式接入](docs/USAGE.md#源码方式接入) |
| 内部职责、扩展和测试入口 | [DEVELOPMENT](docs/DEVELOPMENT.md) |
| 原 DTC 行为对应关系 | [DTC 测试兼容矩阵](docs/DTC-TEST-COVERAGE.md) |

## 开发与验证

工具源码版本以 [modules/xdtc.lua](modules/xdtc.lua) 的 `VERSION` 为准。发布代码版本时同步本页标题和 USAGE 的版本示例，在已验证提交上创建对应 Git 标签，如 `v0.9.0`。Addon 配方由 [插件索引仓库](https://github.com/wmem/xmake-addons/blob/master/README.md)发布同号版本，固定对应工具源码发布提交；更新文档不需要改变运行时版本。

在工具仓库根目录执行 `xmake lua tests/all.lua`。回归覆盖数据、模板、生成、DTC 行为、任务配置、源码集成、命令和配置对象读取；套件入口与验证说明见 [开发文档](docs/DEVELOPMENT.md#开发与测试)。Addon 的真实安装与消费验证位于 [索引集成测试](https://github.com/wmem/xmake-addons/blob/master/tests/test_addons.py)，v0.9.0／Addon 0.3.0 的结果见 [脚本 API 验证](https://github.com/wmem/xmake-addons/blob/master/tests/validation-xdtc-script-api.json)。

本地插件准备和示例运行方法见 [开发文档](docs/DEVELOPMENT.md#开发与测试)。模板实现的来源及许可证见 [lua-resty-template 许可证](third_party/lua-resty-template-LICENSE)和 [LICENSE](LICENSE)。
