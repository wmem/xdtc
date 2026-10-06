-- 读取对象的路径、组合、错误、修改隔离和快速重写回归。
local project = path.absolute("..", os.scriptdir())
local xdtc = import("xdtc", { rootdir = path.join(project, "modules"), anonymous = true })
local raw_pcall = debug.global("pcall")
local directory = os.tmpfile() .. "-配置 引用"
local entry = path.join(directory, "entry/xdtc.lua")
local data = path.join(directory, "data/board.lua")
local passed, failed = 0, 0
os.mkdir(path.directory(entry))
os.mkdir(path.directory(data))
io.writefile(entry, "return {data=\"../data/board.lua\"}")
io.writefile(path.join(directory, "data/defaults.lua"), "return {mcu={chip=\"default\"}}")
local original =
    "include(\"defaults.lua\")\nreplace(\"mcu.chip\", \"gd32f427ve\")\nreturn {tools={debug={frequency=100000}}}"
io.writefile(data, original)

local function test(name, callback)
    local ok, errors = raw_pcall(callback)
    if ok then
        passed = passed + 1
        print("[PASS] %s", name)
    else
        failed = failed + 1
        print("[FAIL] %s: %s", name, errors)
    end
end

test("读取展开对象并返回真实数据目录", function()
    local selected, base = xdtc.read_config(entry, "mcu")
    assert(selected.chip == "gd32f427ve" and base == path.directory(data))
end)
test("根对象和嵌套路径", function()
    assert(xdtc.read_config(entry, ".").mcu.chip == "gd32f427ve")
    assert(xdtc.read_config(entry, "tools.debug").frequency == 100000)
end)
test("函数组装接收展开数据并返回 table", function()
    local selected = xdtc.read_config(entry, function(root)
        return { chip = root.mcu.chip, frequency = root.tools.debug.frequency }
    end)
    assert(selected.chip == "gd32f427ve" and selected.frequency == 100000)
end)
test("选择器和结果修改不污染下一次读取", function()
    local selected = xdtc.read_config(entry, function(root)
        root.mcu.chip = "modified"
        return root.mcu
    end)
    selected.chip = "consumer"
    assert(xdtc.read_config(entry, "mcu").chip == "gd32f427ve")
end)
test("错误路径、标量、nil 和函数异常明确失败", function()
    for _, selector in ipairs({
        "missing",
        "mcu.chip",
        "mcu..chip",
        "",
        function()
            return nil
        end,
        function()
            error("selector failed")
        end,
    }) do
        assert(not raw_pcall(function()
            xdtc.read_config(entry, selector)
        end))
    end
    assert(not raw_pcall(function()
        xdtc.read_config(entry, nil)
    end))
end)
test("调用时重新读取，不缓存旧数据", function()
    io.writefile(data, "return {mcu={chip=\"updated\"}}")
    assert(xdtc.read_config(entry, "mcu").chip == "updated")
    io.writefile(data, original)
end)
test("读取不执行模板或 action", function()
    io.writefile(
        entry,
        "return {data=\"../data/board.lua\",tpl={{files={\"missing.tpl\"},out=\"out.c\"}},actions={bad={}}}"
    )
    assert(xdtc.read_config(entry, "mcu").chip == "gd32f427ve")
    assert(not os.isfile(path.join(path.directory(entry), "out.c")))
end)
os.rm(directory)
print("xdtc.selection tests: %d passed, %d failed", passed, failed)
assert(failed == 0, "配置读取测试失败")
