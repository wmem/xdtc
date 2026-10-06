# xdtc 开发文档

本文档面向维护和扩展 xdtc 的开发者。用户侧 API 和示例见 [USAGE.md](USAGE.md)。

## 设计目标

xdtc 的核心约束：

1. **唯一运行时是 Xmake 内置 Lua**；不依赖系统 Lua/LuaJIT/Node/OpenResty。
2. 多个 Lua 配置文件最终构建为**唯一 root tree**。
3. 数据配置的开发方式尽量延续原 DTC：`include/get/remove/replace/update/update_root`。
4. 数据节点自身携带 `enable + match`；不另建一套 generator rule database。
5. 模板中当前节点字段直接顶层访问，**不提供 `item` 前缀**。
6. `name` 自动生成；`parent/root/template/output` 在渲染时自动生成。
7. 模板引擎与数据层保持可独立使用。
8. 生成结果必须稳定可重复。
9. 推荐集成应低成本，但 `xdtc.run()` / `run_file()` 等底层入口必须保持独立可用，不能强迫所有项目使用同一种 Xmake 组织方式。

## 源码结构

```text
addon/                         # Addon 对外入口
├── plugins/xdtc/               # gen/data/run/action 命令
├── rules/codegen/xmake.lua     # @addon/xdtc/codegen
├── includes/config/xmake.lua   # 配置引用：select 返回读取函数
└── modules/generator.lua       # @addon.xdtc.generator，转发核心 API
scripts/prepare-addon.lua       # 配方与本地准备共用的资源安装过程
xmake.lua                      # 源码接入：task("xdtc") + rule("xdtc.codegen")
modules/
├── xdtc.lua                 # 公共入口、加载、生成、read_config/select_action/execute
└── xdtc/
    ├── command.lua           # 保留命令与工程 action 分发
    ├── action.lua            # action 声明校验，复用对象选择
    ├── selection.lua         # 对象路径、函数组装和副本隔离
    ├── integration.lua       # 源码规则的 run-once/optional 桥接
    ├── kind.lua              # Lua table 的 array/object 分类
    ├── merge.lua             # deep merge
    ├── pathops.lua           # get/remove/replace/update
    ├── metadata.lua          # 自动 name
    ├── pattern.lua           # * / ? / ** 匹配
    ├── query.lua             # 从 root 收集可渲染节点
    ├── template.lua          # 小型模板 parser/compiler/runtime
    ├── generator.lua         # 模板发现、匹配、context、聚合、写文件
    └── debug_output.lua      # debug snapshot / JSON 输出

tests/
├── dtc_compat_run.lua        # 原 DTC 行为兼容回归
├── config_run.lua            # xdtc.lua / run_file 回归
├── integration_run.lua       # 源码 integration bridge 回归
├── command_run.lua           # 命令与 action 回归
├── selection_run.lua         # 对象读取与目录回归
└── dtc_compat/               # 对应 case fixtures
examples/
third_party/
```

模块依赖关系：

```text
                        xdtc.lua
                     /      |       \
                 loader   metadata  generator
                   |                   |
          kind/merge/pathops       query/pattern
                                       |
                                    template
```

## 总执行流程

### `xdtc.run()`

```text
config.data
    ↓
xdtc.load()
    ↓
执行 entry data file
    ↓
include() 递归加载
    ↓
DSL 修改 shared root
    ↓
每个文件 return object 最后 merge
    ↓
metadata.apply(root)
    ↓
generator.generate()
    ↓
query.collect(root)
    ↓
发现 template files
    ↓
enable + match
    ↓
构造 render context
    ↓
template.compile_file()/render
    ↓
fragment aggregation
    ↓
write output
```

## 配置文件与 Xmake integration

### `xdtc.lua` config loader

`xdtc.load_config()` 使用与 data loader 类似的 Xmake sandbox 执行配置文件，但配置文件只负责返回一个普通 table，不注入 data DSL。

```text
xdtc.lua
    ↓
load_config()
    ↓
return config table
    ↓
run_file()
    ↓
xdtc.run(config)
```

`run_file(config_path, opt)` 的重要约束：

- `config_path` 可以任意指定，不强制文件名；
- `opt.base_dir` 用于解析相对 config path；
- 配置内部默认以配置文件所在目录为基准；显式相对 `config.base_dir` 也相对配置文件解析，`opt.base_dir` 不改变内部路径基准；
- `opt.overrides` 只做 top-level shallow override，不改变原配置文件；
- 直接 `xdtc.run(table)` 始终保留，配置文件不是核心层依赖。

### Addon 接入

推荐接入通过索引配方安装，运行资源由 scripts/prepare-addon.lua 准备到插件私有目录；核心源码只维护在 modules 中。addon/modules/generator.lua 注册私有模块目录并继承公共 API，命令和规则调用同一实现。

Addon 的代码生成规则直接调用 run_file，在 on_prepare 中每次生成内存结果，再比较内容决定是否写文件；不使用源码规则的 run-once／optional 桥接。CLI 默认相对启动目录定位入口，规则以工程根目录定位；配置内部路径统一由 load_config 规范化。详细路径约定见 [使用文档](USAGE.md#命令动作与路径基准)。

配置域辅助接口 xdtc_config(file) 在声明时固定入口路径；select(selector) 只创建读取函数。调用方需要把配置域回调绑定到脚本环境，并显式调用，函数才通过 read_config 加载和选择数据，返回 table 和实际数据目录。工具不接管调用方的规则生命周期，不自动执行 add_rules 中的函数。

### 根 `xmake.lua` 集成入口

仓库根 `xmake.lua` 是 drop-in convenience layer，不属于 data/template 核心。宿主工程通过 `includes("tools/xdtc/xmake.lua")` 引入；该文件不调用 `set_project()` / `set_version()`，因此不会修改宿主项目元数据。它做两件事：

```text
task("xdtc")
rule("xdtc.codegen")
```

rule 使用 `on_prepare`，保证生成动作发生在编译命令之前。

`modules/xdtc/integration.lua` 负责共享执行逻辑：

```text
config path resolve
    ↓
optional missing check
    ↓
run-once cache (default)
    ↓
xdtc.run_file()
```

rule extra config：

```lua
add_rules("xdtc.codegen", {
    config = "configs/fpga.lua",
    once = true,
    optional = false
})
```

默认 `once=true` 的原因是多个 target 常常共享同一套 codegen；在同一个 Xmake 进程中重复生成既浪费时间，也可能产生并发写同一输出的问题。需要 target-specific 生成时允许显式 `once=false`。

### generated source 的 Xmake 时序

`on_prepare` 在编译之前，但 Xmake 的 source file 收集发生得更早。若生成的 `.c/.cpp` 在 project load 时不存在，必须由上层 target 使用：

```lua
add_files("build/generated.c", {always_added = true})
```

否则 Xmake 会在 codegen 执行前就把不存在的源文件从 source list 中丢掉。这个规则属于 Xmake 集成约束，不应通过 generator 猜测或自动修改 target source list。

## Data loader

入口在：

```text
modules/xdtc.lua
```

### 每次 load 的 state

```lua
{
    root = {},
    loaded_files = {},
    loading_stack = {},
    file_stack = {}
}
```

职责：

- `root`：所有数据文件共享的唯一数据树；
- `loaded_files`：避免同一规范化文件重复执行；
- `loading_stack`：检测 circular include；
- `file_stack`：让 `include()` 和 `os.scriptdir()` 基于当前数据文件解析。

### 文件路径

所有输入路径最终通过 normalize + absolute 处理。

Windows 下比较路径时转 lowercase，用于重复 include 和循环检测。

### Data sandbox

xdtc 不使用外部 Lua runtime。它通过 Xmake 内置 Lua 执行数据文件，并为脚本构造独立 environment。

基础环境来自：

```lua
import("core.sandbox.sandbox")
sandbox.builtin_modules()
```

然后注入：

```text
include
get
remove
replace
update
update_root / updateRoot
get_root
```

并移除：

```text
import
debug
```

`os.scriptdir()` 会被重新包装，使其返回**当前数据文件**目录。

实现目前使用 Xmake 内部能力：

```text
debug.global("loadfile")
debug.setfenv
core.sandbox.sandbox
```

这是最重要的 Xmake 兼容风险点。升级 Xmake 时，优先运行完整测试确认这些内部 API 仍然可用。

### Data file return

脚本通过 raw `loadfile` 加载，设置 env 后执行。

返回值允许：

```text
nil
object table
```

不允许返回 array/scalar。

返回 object 的 merge 发生在该文件顶层语句执行完之后。

## table kind 规则

`kind.lua` 当前规则：

```lua
array  = type(v) == "table" and v[1] ~= nil
object = type(v) == "table" and v[1] == nil
```

这是一个刻意保持简单的约束。

因此开发时必须注意：

- 正常连续数组：支持；
- 空 table `{}`：视为 object；
- 稀疏数组且 `[1] == nil`：会视为 object；
- 混合 table：不要作为公共数据格式使用。

如果未来修改 kind 判定，必须重新评估 merge、pathops、metadata、query 全部行为。

## Merge 语义

`merge.merge_into(target, source)`：

```text
object + object    -> recursive merge
array  + array     -> source replaces target
scalar + same kind -> source replaces target
kind mismatch      -> error
```

目标是尽早暴露配置结构错误，而不是隐式将 object/array/scalar 互相覆盖。

## Path operations

`pathops.lua` 使用 dotted path：

```text
soc.uart0.width
items.2.name
```

数组 index 使用 Lua 1-based。

行为：

- `get`：严格读取，不存在报错；
- `remove`：缺失路径忽略；
- `replace`：允许创建缺失 object parent；
- `update(object)`：允许创建目标对象并 deep merge；
- `update(non-object)`：目标必须已经存在并且 kind 相同。

## Metadata

`metadata.apply(root)`：

- root 默认 `name = "root"`；
- 每个普通 object 如果没有 `name`，使用它在父 object 中的 key；
- 已有 `name` 不覆盖；
- arrays 不递归。

metadata 只写 `name`，**不写 parent pointer**，防止数据树产生循环引用。

## Candidate query

`query.collect(root)` 只遍历 ordinary object。

节点满足：

```lua
node.enable == true
and type(node.match) == "string"
and #node.match > 0
```

就加入 render candidate：

```lua
{
    node = node,
    parent = parent,
    path = dotted_path
}
```

### 稳定顺序

Lua object table 没有可靠 insertion order，因此 query 将 string/number key 转成可比较形式后按字典序遍历。

这是 reproducible generation 的设计要求。

如果用户需要显式业务顺序，应在数据中使用 array，并在模板中遍历 array；generator 不遍历 array 创建 render candidate。

## Pattern 语义

### 数据 `match`

只与 template basename 匹配：

```text
*  任意字符数
?  一个字符
```

### task `files`

路径 glob：

```text
*   当前 segment 任意字符数
?   当前 segment 一个字符
**  零个或多个 path segment
```

`generator.discover()`：

1. 按 pattern 声明顺序展开；
2. 单个 pattern 的结果排序；
3. 全局去重，保留首次出现顺序。

## Template engine

`template.lua` 是纯 Lua parser/compiler/runtime，语法来自 `lua-resty-template` 的思路，但删除 OpenResty/ngx 依赖并收缩运行环境。

### 语法

```text
{{ expr }}     表达式输出
{* expr *}     raw 输出
{% code %}     Lua statement/control flow
{# comment #}  注释
```

代码标签只有在**独占一行**时才会裁剪该行周围空白，避免行内条件破坏 Verilog/SystemVerilog 排版。

### compile model

```text
template source
    ↓
parse/compile to Lua source
    ↓
load generated chunk
    ↓
restricted runtime environment
    ↓
renderer(context) -> string
```

### runtime boundary

模板可以访问 context 和少量 Lua 基础函数/库。

模板不暴露 Xmake `import`、文件/进程 API、`debug`、`require`、`ngx`。

原则：

> template 只做纯渲染；IO 和 orchestration 属于 generator。

### escape

独立 template engine 默认 `escape = true`，保留 lua-resty-template 风格。

generator 明确按代码生成场景设置默认 `escape = false`。

## Generator

`generator.generate(root, tasks, opt)` 是数据树与 template engine 的桥接层。

### Task validation

每个 task 必须：

```lua
{
    files = {"..."},
    out = "...",
    input_template = "...", -- optional
    escape = false          -- optional
}
```

不同 task 不能指向同一个规范化 output path。

### Render context

当前 node 的字段先复制到 context，但以下 key 是系统保留：

```text
parent
root
template
output
```

随后系统强制写入：

```lua
context.parent = entry.parent
context.root = root
context.template = {
    name = path.filename(template_path),
    path = template_path
}
context.output = {
    path = output_path
}
```

因此系统值始终覆盖数据里的同名字段。

这里刻意不提供：

```text
item
```

模板应直接写：

```text
{{ name }}
{{ width }}
{{ parent.name }}
{{ root.project.version }}
```

### Fragment 聚合

每个模板按 candidate 顺序渲染。每个 fragment 末尾 `\r/\n` 被裁掉，然后所有 fragment 用一个 `\n` 连接。

聚合完成后才处理 `input_template`：

```text
fragments
   ↓ concat
raw content
   ↓ optional input_template {{.}} substitution
final content
   ↓
out
```

`input_template` 的设计边界：

- 未配置：直接返回 raw content；
- 配置但文件不存在：直接返回 raw content；
- 文件存在：只做字面量 `{{.}}` 替换；
- 至少需要一个 `{{.}}`，否则报错；
- 多个 `{{.}}` 全部替换；
- 不调用 template engine，不解释其他 `{{ ... }}` / `{% ... %}`；
- 插入内容不递归处理。

实现必须在**所有普通模板已经完成渲染与聚合之后**执行，不能按 fragment 单独包装，否则多个匹配节点会生成多个 wrapper。

没有 template 或没有 match 时，raw content 为 `""`；如果存在 `input_template`，仍会把空字符串替换到 `{{.}}` 后写 wrapper；否则在 `write ~= false` 时写出空文件。

### Debug information

每个 output result 带内部 debug trace。为保持 v0.3 兼容，同时提供 path trace 和 DTC 风格对象快照：

```lua
debug = {
    {
        template = "/abs/path/a.tpl",
        matched_paths = {
            "root.soc.uart0",
            "root.soc.uart1"
        },

        templatePath = "/abs/path/a.tpl",
        matchedObjects = { ... }
    }
}
```

`xdtc.run()` 可通过 `debug_data_out` / `debug_match_out`（以及 DTC 兼容别名 `debugDataOut` / `debugMatchOut`）直接写 JSON。

- debug data 在 metadata 注入前快照；
- debug match 在 metadata 后生成，因此对象含自动 `name`；
- `parent` 从未写回 root，所以匹配对象快照没有循环引用。

debug 输出必须复用 generator 已产生的 trace，不要重新实现一套 matching。

## 公共 API 边界

稳定公共入口：

```text
xdtc.version
xdtc.load_config
xdtc.load_data
xdtc.read_config
xdtc.select_action
xdtc.execute
xdtc.run_file
xdtc.load
xdtc.build
xdtc.generate
xdtc.run

xdtc.template.render
xdtc.template.render_file
xdtc.template.compile
xdtc.template.compile_file
xdtc.template.parse
xdtc.template.output
xdtc.template.escape
xdtc.template.clear_cache
```

`xdtc.generator` 的 helper 当前可 import，但优先视为较低层 API；修改时应先检查 examples/tests 是否已有外部依赖。

`xdtc.integration` 是源码接入的底层桥接；源码消费者通过仓库根 xmake.lua 注册 task/rule，自定义流程才直接调用它。Addon 消费者使用命名空间规则或 `@addon.xdtc.generator`，不需要依赖 integration 模块。配置引用接口的精确返回值与调用方式见 [使用文档](USAGE.md#xmake-配置引用接口)。

## 设计不变量

后续修改应尽量保持：

1. `root` 只有一份，所有 include 共用；
2. data file 的 return 最后 merge；
3. arrays replace，不 deep merge；
4. arrays 不参与 metadata/query traversal；
5. 自动 `name` 不覆盖用户显式 `name`；
6. 不在 root 中保存 `parent` 引用；
7. template context 无 `item`；
8. `parent/root/template/output` 为保留变量；
9. generator 默认 raw code output (`escape=false`)；
10. 普通 object candidate traversal 必须 deterministic；
11. `input_template` 只作用于最终聚合内容，只识别字面量 `{{.}}`，不做二次模板执行；
12. 不增加外部运行时依赖；
13. 默认 `xdtc.lua` / task / rule 只是 convenience layer，不能让核心 `xdtc.run()` 依赖 Xmake target/rule 状态。

## 开发与测试

### 完整测试

包根目录：

```sh
xmake lua tests/all.lua
```

等价于：

```sh
xmake lua tests/run.lua
xmake lua tests/template_run.lua
xmake lua tests/generator_run.lua
xmake lua tests/dtc_compat_run.lua
xmake lua tests/config_run.lua
xmake lua tests/integration_run.lua
xmake lua tests/command_run.lua
xmake lua tests/selection_run.lua
```

### DTC 兼容回归

`tests/dtc_compat_run.lua` 从原 DTC `test/test.js` 迁移核心行为，作为独立回归层。迁移矩阵见 [`DTC-TEST-COVERAGE.md`](DTC-TEST-COVERAGE.md)。

这层测试的目的不是模拟 JavaScript/EJS，而是锁定用户已经形成的 DTC 开发语义：include、路径操作、metadata、enable/match、wildcard、空输出、debug 输出及错误边界。

### 测试分层

```text
tests/run.lua            data loader / DSL / merge / metadata
tests/template_run.lua   template parser/compiler/runtime
tests/generator_run.lua  discovery / matching / context / aggregation / input_template
tests/command_run.lua    子命令、动作、路径和快速重写回归
tests/selection_run.lua  配置对象读取、组合、目录和修改隔离
tests/config_run.lua     standalone xdtc.lua / load_config / run_file
tests/integration_run.lua Xmake integration bridge / run-once / optional
```

新功能应放到对应层测试；跨层行为再补 generator 端到端测试。2026-10-06 在上述本机环境运行八个源码套件，58 项检查通过。真实 Addon 安装、命名空间导入和配置域引用由 [索引集成测试](https://github.com/wmem/xmake-addons/blob/master/tests/test_addons.py)验证，源码测试不替代插件分发验证。

### 本地准备插件

索引配方和本地开发共用准备脚本。在仓库根目录执行：

```sh
xmake lua scripts/prepare-addon.lua /tmp/xdtc-addon-stage
xmake addon --install /tmp/xdtc-addon-stage
```

输出目录必须尚不存在。直接从原始源码目录或 Git URL 安装，不会执行索引配方的准备过程，因而不能假定私有运行资源已经齐全；本地阶段用于开发验证，版本化消费通过索引配方安装。

### 示例 smoke test

```text
examples/basic/
examples/template/
examples/generator/
examples/integration/
```

`examples/integration/` 额外验证源码方式的 Xmake 接入：默认 `xdtc.lua`、手动 task、`on_prepare` rule，以及“生成的 C 源文件在本次构建中参与编译”。在本仓库内运行嵌套 example 时可使用：

```sh
# 从仓库根目录进入示例，显式选择它自己的配置文件。
cd examples/integration
xmake xdtc -P "$PWD" -F "$PWD/xmake.lua" gen
xmake f -P "$PWD" -F "$PWD/xmake.lua" -m release -y
xmake -P "$PWD" -F "$PWD/xmake.lua"
./build/linux/x86_64/release/demo
```

对用户可见 API 有修改时，至少同步更新对应 example 和 `docs/USAGE.md`。

## 扩展建议

### 增加新的数据 DSL

1. 如果只是 path/tree 操作，优先实现到 `pathops.lua`；
2. 在 `_make_environment()` 中注入 DSL；
3. 保持数据脚本无需 `import("xdtc")`；
4. 添加 data-layer test；
5. 更新 USAGE 的快速索引和 DSL 节。

### 增加 generator matching 能力

优先拆到：

```text
pattern.lua
query.lua
```

不要让复杂 matching 逻辑堆进 template engine。

### 增加模板功能

判断它是否真的是“文本渲染能力”。

- 是：进入 `template.lua`；
- 文件发现/IO/输出：属于 generator；
- 数据解析/修改：属于 data layer。

保持模板 engine 独立非常重要。

## 兼容性关注点

最需要关注的是 Xmake 内部 Lua/sandbox API，而不是普通 Lua 语法。

升级 Xmake 后重点验证：

```text
core.sandbox.sandbox
debug.global("loadfile")
debug.setfenv
sandbox.builtin_modules()
```

然后执行全量回归。

## 第三方来源

模板语法和部分 parser 设计来源于 `lua-resty-template`。

License：

```text
third_party/lua-resty-template-LICENSE
```

修改 template parser 时不要删除该 attribution/license。

## action 输入选择

`modules/xdtc/action.lua` 校验 action 声明；`selection.lua` 负责点分路径、函数组装和副本隔离，供 action 和 read_config 共用。command.lua 在执行 action 前调用公共 select_action，应用读取器可复用同一接口。
选择只作用于动作输入，gen/data 和 run 的数据语义保持不变。
测试入口为 tests/command_run.lua，覆盖树改组后脚本保持不变、空对象、异常和修改隔离。


## 配置引用的调用边界

addon/includes/config/xmake.lua 创建配置引用和零参数读取函数；它不读取文件。使用方在脚本域绑定并调用回调后，公共 read_config 执行 load_config → load_data → selection.select，并返回所选 table 和实际数据入口目录。每次调用重新读取，不保存展开树缓存；使用方可以按自己的规则生命周期保存结果。

board:select 的组装函数接收独立 root，返回 table；board:select 自身返回读取函数。这两个函数的职责和返回类型不同。read_config／select_action 立即返回 table，也不等价于配置引用。错误路径、标量或 nil 结果必须失败，不自动回退 root。对应测试为 tests/selection_run.lua；辅助接口的实际消费由索引集成测试覆盖。
