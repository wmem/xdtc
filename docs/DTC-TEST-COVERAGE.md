# DTC 测试兼容矩阵

这份文档记录原 DTC `test/test.js` 与 xdtc 回归测试之间的对应关系。

目标不是保留 JavaScript/EJS 实现细节，而是锁定已经形成的 DTC 开发语义，避免后续重构破坏使用习惯。

## 迁移结果

| DTC case | xdtc | 状态 | 说明 |
|---|---|---|---|
| `runVersionCase` | `DTC version` | 已迁移 | `xdtc.version()` 必须为 `x.y.z` |
| `runScriptGlobalsCase` | `DTC data-script DSL is scoped and include is relative` | 已迁移/适配 | Lua 版不修改真正 `_G`；测试 DSL 可用、相对 include 正确且执行后不泄漏 |
| `runUpdateRootCase` | `DTC updateRoot` | 已迁移 | 保留 camelCase `updateRoot()` 兼容别名，同时支持 `update_root()` |
| `runReplaceAndUpdateEdgeCase` | `DTC replace/update edge cases` | 已迁移 | 覆盖对象深合并、标量同类型更新及错误边界 |
| `runBasicCase` | `DTC basic DTC workflow plus debug outputs` | 已迁移 | 数据合并、get/remove/replace/update、metadata、匹配、输出、debug data、debug match |
| `runEmptyOutputCase` | `DTC empty output` | 已迁移 | 无匹配时仍创建空输出文件 |
| `runCustomDelimitersCase` | — | 不迁移 | 这是 EJS 特有分隔符配置；xdtc 模板语言固定为 lua-resty-template 风格，不兼容 EJS 语法 |
| `runWildcardCase` | `DTC wildcard matching` | 已迁移 | `*`、`?`、`**` 发现/匹配语义 |
| `runEnableFilterCase` | `DTC enable filter` | 已迁移 | 只有 `enable = true` 参与候选收集 |
| `runGetMissingCase` | `DTC get missing path` | 已迁移 | 不存在路径立即报错 |
| `runTypeMismatchCase` | `DTC merge type mismatch` | 已迁移 | 冲突路径必须出现在错误信息中 |
| `runCircularIncludeCase` | `DTC circular include` | 已迁移 | include 栈检测循环引用 |

因此，原 DTC 的 12 个顶层 case 中，**11 个语义 case 已迁移**；唯一未迁移的是 EJS 专属的自定义 delimiter。

## 有意保留的 Lua 差异

### 数组下标

DTC/JavaScript：

```text
lookup.items.1.name   # 第二项
```

xdtc/Lua：

```text
lookup.items.2.name   # 第二项
```

Lua 数组保持 1-based，不做额外的 0-based 模拟层。

### 对象遍历顺序

JavaScript 普通对象有明确的属性枚举顺序；Lua table 不提供等价的插入顺序保证。

xdtc 对普通对象 key 使用字典序遍历，确保生成结果可重复。因此 `case-basic` 中两个 `detail.tpl` 匹配对象的顺序与原 DTC 可能不同，但每次运行稳定一致。

### 模板当前节点

原 DTC/EJS：

```text
<%= item.name %>
```

xdtc：

```text
{{ name }}
```

当前节点字段直接注入模板作用域；`parent`、`root`、`template`、`output` 仍由系统自动提供。

## Debug 输出兼容

`xdtc.run()` 支持推荐的 Lua 风格名称：

```lua
debug_data_out = "debug/global-data.json"
debug_match_out = "debug/match-data.json"
```

也支持原 DTC 名称：

```lua
debugDataOut = "debug/global-data.json"
debugMatchOut = "debug/match-data.json"
```

语义与 DTC 保持一致：

- global data 在自动 `name` metadata 注入前输出；
- match data 在 metadata 注入后输出；
- `matchedObjects` 不包含 `parent`，避免形成循环引用。

## 运行

完整回归：

```sh
XMAKE_ROOT=y /path/to/xmake lua tests/all.lua --root
```

只运行 DTC 兼容层：

```sh
XMAKE_ROOT=y /path/to/xmake lua tests/dtc_compat_run.lua --root
```
