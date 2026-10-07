-- 使用真实文件验证分发、路径、展开和脚本失败；不访问硬件。
local modules = path.absolute("../modules", os.scriptdir())
local xdtc = import("xdtc", { rootdir = modules, anonymous = true })
local command = import("xdtc.command", { rootdir = modules, anonymous = true })
local raw_pcall = debug.global("pcall")
local root = os.tmpfile() .. "-xdtc-command"
local directory = path.join(root, "配置 空格")
local configfile = path.join(directory, "xdtc.lua")
local passed, failed = 0, 0
os.mkdir(path.join(directory, "data"))
os.mkdir(path.join(directory, "scripts"))
os.mkdir(path.join(directory, "tpl"))
io.writefile(
    path.join(directory, "data/defaults.lua"),
    "return {node={enable=true,match=\"value.tpl\",value=1},values={1,2},disabled={enable=false}}"
)
io.writefile(
    path.join(directory, "data/root.lua"),
    [[
local defaults = path.absolute("defaults.lua", os.scriptdir())
include(defaults)
replace("values", {})
update("node.value", 42)
return {serial={port="/dev/fixture"}}
]]
)
io.writefile(path.join(directory, "tpl/value.tpl"), "{{value}}")
local function write_config(extra)
    io.writefile(
        configfile,
        "return {data=\"data/root.lua\",tpl={{files={\"tpl/value.tpl\"},out=\"out.txt\"}},"
            .. (extra or "")
            .. "}"
    )
end
write_config("actions={inspect={script=\"scripts/check.lua\",select=\".\"}}")
io.writefile(
    path.join(directory, "scripts/check.lua"),
    [[
function main(config, api, expected)
    assert(type(api.template.render) == "function")
    assert(config.name == nil and config.serial.name == nil)
    assert(config.node.value == 42 and #config.values == 0 and config.disabled.enable == false)
    assert(config.serial.port == "/dev/fixture")
    assert(os.scriptdir():endswith("scripts"))
    return expected or "checked"
end
]]
)

local function check(condition, message)
    assert(condition, message)
end
local function expect_error(fn, needle)
    local ok, errors = raw_pcall(fn)
    check(
        not ok and tostring(errors):find(needle, 1, true),
        "expected " .. needle .. "; ok=" .. tostring(ok) .. "; error=" .. tostring(errors)
    )
end
local function testcase(name, fn)
    local ok, errors = raw_pcall(fn)
    if ok then
        passed = passed + 1
        cprint("${green}[PASS]${clear} %s", name)
    else
        failed = failed + 1
        cprint("${red}[FAIL]${clear} %s", name)
        print(errors)
    end
end

testcase("配置查找目录不改变内部相对路径", function()
    local result = command.run("配置 空格/xdtc.lua", "gen", {}, { base_dir = root })
    check(result.outputs[1].content == "42", "渲染失败")
    check(io.readfile(path.join(directory, "out.txt")) == "42", "输出目录错误")
    check(not os.isfile(path.join(root, "out.txt")), "不应输出到查找目录")
end)
testcase("run 展开完整数据并转发位置参数", function()
    check(
        command.run(configfile, "run", { "scripts/check.lua", "argument" }) == "argument",
        "参数未传递"
    )
end)
testcase("action 使用同一数据及脚本接口", function()
    check(command.run(configfile, "inspect", {}) == "checked", "动作失败")
    write_config("actions={pairs={script=\"scripts/check.lua\",select=\".\"}}")
    check(command.run(configfile, "pairs", {}) == "checked", "动作名不应触发增强 pairs")
    write_config("actions={inspect={script=\"scripts/check.lua\",select=\".\"}}")
end)
testcase("绝对路径与显式相对 base_dir", function()
    io.writefile(
        path.join(root, "absolute.lua"),
        "return {base_dir=\"配置 空格\",data=\"data/root.lua\",actions={inspect={script="
            .. string.format("%q", path.join(directory, "scripts/check.lua"))
            .. ",select=\".\"}}}"
    )
    check(
        command.run(path.join(root, "absolute.lua"), "inspect", {}) == "checked",
        "绝对路径失败"
    )
end)
testcase("未知动作及保留名称拒绝覆盖", function()
    expect_error(function()
        command.run(configfile, "unknown", {})
    end, "unknown action")
    write_config("actions={gen=\"scripts/check.lua\"}")
    expect_error(function()
        command.run(configfile, "gen", {})
    end, "reserved command")
    write_config("actions={inspect={script=\"scripts/check.lua\",select=\".\"}}")
end)
testcase("命令参数及配置错误明确报错", function()
    expect_error(function()
        command.run(configfile, nil, {})
    end, "expected gen")
    expect_error(function()
        command.run(configfile, "run", {})
    end, "requires a script")
    expect_error(function()
        command.run(configfile, "gen", { "extra" })
    end, "does not accept")
    expect_error(function()
        command.run(path.join(root, "absent.lua"), "data", {})
    end, "config file not found")
    write_config("actions={inspect={}}")
    expect_error(function()
        command.run(configfile, "inspect", {})
    end, "requires a script path")
    write_config("actions={inspect={script=\"scripts/check.lua\",select=\".\"}}")
end)
testcase("脚本缺失、缺少 main 和执行失败", function()
    expect_error(function()
        command.run(configfile, "run", { "absent.lua" })
    end, "script file not found")
    io.writefile(path.join(directory, "scripts/bad.lua"), "function helper() end")
    expect_error(function()
        command.run(configfile, "run", { "scripts/bad.lua" })
    end, "must define main")
    io.writefile(
        path.join(directory, "scripts/fail.lua"),
        "function main(config) raise(\"action failed\") end"
    )
    expect_error(function()
        command.run(configfile, "run", { "scripts/fail.lua" })
    end, "action failed")
end)
testcase("数据展开不生成文件或添加 metadata", function()
    local data = xdtc.load_data(xdtc.load_config(configfile))
    check(
        data.node.value == 42 and data.name == nil and data.disabled.enable == false,
        "数据错误"
    )
    check(#data.values == 0, "replace 未生效")
end)
testcase("action 选择子对象并转发参数", function()
    io.writefile(
        path.join(directory, "scripts/serial.lua"),
        [[
function main(serial, api, argument)
    assert(type(api.template.render_file) == "function")
    assert(serial.port == "/dev/fixture" and serial.serial == nil and serial.node == nil)
    return argument
end
]]
    )
    write_config("actions={serial={script=\"scripts/serial.lua\",select=\"serial\"}}")
    check(
        command.run(configfile, "serial", { "forwarded" }) == "forwarded",
        "子对象或参数错误"
    )
end)
testcase("嵌套对象路径与空对象", function()
    local config = { actions = { nested = { script = "unused.lua", select = "tools.serial" } } }
    check(
        xdtc.select_action(config, "nested", { tools = { serial = { port = "nested" } } }).port
            == "nested",
        "嵌套选择错误"
    )
    config.actions.nested.select = "values"
    check(
        debug.global("next")(xdtc.select_action(config, "nested", { values = {} })) == nil,
        "空对象应允许"
    )
end)
testcase("函数组合输入并在对象树改组后保持脚本不变", function()
    local script = path.join(directory, "scripts/serial.lua")
    local before = io.readfile(script)
    io.writefile(
        path.join(directory, "data/moved.lua"),
        "return {board={console={device=\"/dev/fixture\"}}}"
    )
    io.writefile(
        configfile,
        [[return {
data="data/moved.lua",
actions={serial={script="scripts/serial.lua",select=function(root)
    return {port=root.board.console.device}
end}}
}]]
    )
    check(
        command.run(configfile, "serial", { "moved" }) == "moved",
        "改组后未使用新的选择"
    )
    check(io.readfile(script) == before, "不应修改脚本")
    write_config("actions={inspect={script=\"scripts/check.lua\",select=\".\"}}")
end)
testcase("选择和脚本输入不修改原始数据", function()
    local root = { serial = { port = "original" } }
    local config = { actions = { inspect = { script = "unused.lua", select = "." } } }
    local selected = xdtc.select_action(config, "inspect", root)
    selected.serial.port = "changed"
    check(root.serial.port == "original", "root 选择应隔离修改")
    config.actions.inspect.select = function(data)
        data.serial.port = "mapped"
        return data.serial
    end
    selected = xdtc.select_action(config, "inspect", root)
    check(
        selected.port == "mapped" and root.serial.port == "original",
        "函数修改不应影响 root"
    )
    selected.port = "script"
    check(root.serial.port == "original", "脚本修改不应影响 root")
end)
testcase("未填写 select 和旧字符串声明明确拒绝", function()
    for _, action in ipairs({ { script = "unused.lua" }, "unused.lua" }) do
        expect_error(function()
            xdtc.select_action({ actions = { inspect = action } }, "inspect", {})
        end, type(action) == "table" and "requires select" or "must be {script, select}")
    end
end)
testcase("非法路径、缺失对象及标量不会回退 root", function()
    for _, selector in ipairs({ "", ".serial", "serial.", "tools..serial" }) do
        expect_error(function()
            xdtc.select_action(
                { actions = { inspect = { script = "unused.lua", select = selector } } },
                "inspect",
                {}
            )
        end, "invalid select path")
    end
    expect_error(function()
        xdtc.select_action(
            { actions = { inspect = { script = "unused.lua", select = "absent" } } },
            "inspect",
            {}
        )
    end, "select path not found")
    expect_error(function()
        xdtc.select_action(
            { actions = { inspect = { script = "unused.lua", select = "port" } } },
            "inspect",
            { port = false }
        )
    end, "select must return an object")
end)
testcase("函数异常和无对象返回值包含动作名称", function()
    for _, selector in ipairs({
        function()
            error("selector failed")
        end,
        function()
            return nil
        end,
        function()
            return false
        end,
    }) do
        expect_error(function()
            xdtc.select_action(
                { actions = { inspect = { script = "unused.lua", select = selector } } },
                "inspect",
                {}
            )
        end, "action 'inspect'")
    end
end)
testcase("同一进程快速改写数据及脚本读取新内容", function()
    local entry = path.join(directory, "data/changing.lua")
    io.writefile(entry, "return {value=1}")
    check(xdtc.load(entry).value == 1, "初始数据失败")
    io.writefile(entry, "return {value=2}")
    check(xdtc.load(entry).value == 2, "读取了旧数据缓存")
    local script = path.join(directory, "scripts/changing.lua")
    io.writefile(script, "function main(config) return 1 end")
    check(xdtc.execute(script, {}) == 1, "初始脚本失败")
    io.writefile(script, "function main(config) return 2 end")
    check(xdtc.execute(script, {}) == 2, "读取了旧脚本缓存")
end)
os.rm(root)
print("xdtc.command tests: %d passed, %d failed", passed, failed)
if failed > 0 then
    raise("xdtc.command test suite failed")
end
