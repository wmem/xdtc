-- 通过真实脚本验证 API 参数、按需渲染、路径与执行间隔离。
local project = path.absolute("..", os.scriptdir())
local xdtc = import("xdtc", { rootdir = path.join(project, "modules"), anonymous = true })
local command = import("xdtc.command", {
    rootdir = path.join(project, "modules"),
    anonymous = true,
})
local raw_pcall = debug.global("pcall")
local root = os.tmpfile() .. "-脚本 API"
local directory = path.join(root, "入口 空格")
local scripts = path.join(root, "共享脚本 中文")
local config = path.join(directory, "xdtc.lua")
local script = path.join(scripts, "render.lua")
local file = path.join(scripts, "templates/value.tpl")
local passed, failed = 0, 0
os.mkdir(directory)
os.mkdir(path.directory(file))
io.writefile(path.join(directory, "data.lua"), "return {settings={value=\"a < b\"},unused=true}")
io.writefile(file, "value={{ value }}")
io.writefile(
    config,
    [[return {
    data = "data.lua",
    tpl = {{files = {"missing.tpl"}, out = "must-not-generate.c"}},
    actions = {render = {script = "../共享脚本 中文/render.lua", select = "settings"}},
}]]
)
io.writefile(
    script,
    [[assert(api == nil, "API 只通过第二个参数提供")
function main(data, api, mode, marker)
    assert(type(api) == "table" and type(api.template.render_file) == "function")
    if mode == "run" then
        assert(data.unused == true and data.name == nil)
        return marker, api.template.render("{{ value }}", data.settings, {escape = false})
    end
    assert(data.unused == nil and data.settings == nil and data.name == nil)
    if mode == "file" then
        return api.template.render_file("templates/value.tpl", data, {escape = false})
    end
    return api.template.render("{{ value }}", data), marker
end]]
)

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

test("run 的第二个参数为 API，位置参数从第三个开始", function()
    local marker, content = command.run(config, "run", {
        "../共享脚本 中文/render.lua",
        "run",
        "forwarded",
    })
    assert(marker == "forwarded" and content == "a < b")
end)
test("action 渲染任意选中 table，不要求节点匹配字段", function()
    local content, marker = command.run(config, "render", { "string", "forwarded" })
    assert(content == "a &lt; b" and marker == "forwarded")
    assert(not os.isfile(path.join(directory, "must-not-generate.c")))
end)
test("文件模板相对脚本目录，绝对路径直接使用", function()
    assert(command.run(config, "render", { "file" }) == "value=a < b")
    io.writefile(
        path.join(scripts, "absolute.lua"),
        [[function main(data, api, file)
    return api.template.render_file(file, data, {escape = false})
end]]
    )
    assert(xdtc.execute(path.join(scripts, "absolute.lua"), { value = 42 }, { file }) == "value=42")
end)
test("同一进程重写模板后读取最新内容", function()
    io.writefile(file, "updated={{ value }}")
    assert(command.run(config, "render", { "file" }) == "updated=a < b")
    io.writefile(file, "value={{ value }}")
end)
test("API 对象与路径绑定在各次脚本执行间独立", function()
    local isolated = path.join(root, "另一个脚本/check.lua")
    os.mkdir(path.directory(isolated))
    io.writefile(path.join(path.directory(isolated), "local.tpl"), "local={{ value }}")
    io.writefile(
        isolated,
        [[function main(data, api)
    assert(api.template.extra == nil)
    local result = api.template.render_file("local.tpl", data)
    api.template.extra = true
    api.template.render_file = function() error("不能影响下一次执行") end
    return result
end]]
    )
    assert(xdtc.execute(isolated, { value = 1 }) == "local=1")
    assert(xdtc.execute(isolated, { value = 2 }) == "local=2")
    assert(command.run(config, "render", { "file" }) == "value=a < b")
end)
test("脚本可以忽略 API，xdtc 不自动渲染或写文件", function()
    local unused = path.join(scripts, "unused.lua")
    io.writefile(unused, "function main(data) return data.value end")
    assert(xdtc.execute(unused, { value = "unused" }) == "unused")
    assert(not os.isfile(path.join(directory, "must-not-generate.c")))
end)
test("模板缺失、语法错误和渲染错误向调用方传播", function()
    local bad = path.join(scripts, "bad.lua")
    io.writefile(
        bad,
        [[function main(data, api, file)
    return api.template.render_file(file, data)
end]]
    )
    io.writefile(path.join(scripts, "syntax.tpl"), "{% if then %}")
    io.writefile(path.join(scripts, "runtime.tpl"), "{{ missing.value }}")
    for _, item in ipairs({
        { file = "absent.tpl", message = "template file not found" },
        { file = "syntax.tpl", message = "failed to compile" },
        { file = "runtime.tpl", message = "render failed" },
        { file = "", message = "expects a non-empty path string" },
    }) do
        local ok, errors = raw_pcall(function()
            xdtc.execute(bad, {}, { item.file })
        end)
        assert(not ok and tostring(errors):find(item.message, 1, true), tostring(errors))
    end
end)

os.rm(root)
print("xdtc.script_api tests: %d passed, %d failed", passed, failed)
assert(failed == 0, "脚本 API 测试失败")
