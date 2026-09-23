local projectdir = path.absolute(path.join(os.scriptdir(), ".."))
local template = import("xdtc.template", {rootdir = path.join(projectdir, "modules"), anonymous = true})
local raw_pcall = debug.global("pcall")

local passed = 0
local failed = 0

local function check(condition, message)
    if not condition then
        raise("test assertion failed: %s", message)
    end
end

local function equal(actual, expected, message)
    if actual ~= expected then
        raise("test assertion failed: %s\nexpected: %s\nactual:   %s", message, expected, actual)
    end
end

local function testcase(name, fn)
    local ok, errors = raw_pcall(fn)
    if ok then
        passed = passed + 1
        cprint("${bright green}[PASS]${clear} %s", name)
    else
        failed = failed + 1
        cprint("${bright red}[FAIL]${clear} %s", name)
        print(errors)
    end
end

testcase("expressions, code, comments and raw output", function()
    local source = [[
Hello {{ name }}
{# this line is removed #}
{% if enabled then %}
count={{ #items }}
{% for _, value in ipairs(items) do %}
- {{ value }}
{% end %}
{% end %}
raw={* raw *}
]]
    local result = template.render(source, {
        name = "world",
        enabled = true,
        items = {"a", "b"},
        raw = "a < b && c > d"
    })
    equal(result, "Hello world\ncount=2\n- a\n- b\nraw=a < b && c > d\n", "basic template render")
end)

testcase("escaped output matches lua-resty-template style", function()
    equal(template.render("{{ value }}", {value = [[<&\"'/]]}), "&lt;&amp;\\&quot;&#39;&#47;", "escaped expression")
    equal(template.render("{* value *}", {value = [[<&\"'/]]}), [[<&\"'/]], "raw expression")
end)

testcase("escape can be disabled for code generation", function()
    equal(template.render("{{ value }}", {value = "a < b"}, {escape = false}), "a < b", "escape=false")
end)

testcase("echo helper", function()
    equal(template.render("{% echo('A', 1, nil, 'B') %}", {}), "A1B", "echo")
end)

testcase("escaped opener", function()
    equal(template.render([[\{{ name }}]], {name = "ignored"}), "{{ name }}", "escaped opener")
end)

testcase("file rendering", function()
    local filepath = path.join(projectdir, "tests/case-template/templates/module.sv.tpl")
    local result = template.render_file(filepath, {
        name = "uart",
        params = {
            {name = "WIDTH", value = 32},
            {name = "DEPTH", value = 16}
        },
        body = "logic a < b;"
    })
    equal(result, "module uart #(\n    parameter WIDTH = 32,\n    parameter DEPTH = 16\n);\n\nlogic a < b;\nendmodule\n", "file render")
end)

testcase("compiled template can be reused with different contexts", function()
    local render = template.compile("{{ value }}", {escape = false})
    equal(render({value = "one"}), "one", "first context")
    equal(render({value = "two"}), "two", "second context")
end)

testcase("template errors identify chunk", function()
    local ok, errors = raw_pcall(function()
        template.render("{% if then %}", {}, {chunkname = "@broken.tpl"})
    end)
    check(not ok, "invalid template should fail")
    local message = tostring(errors)
    check(message:find("broken.tpl", 1, true) ~= nil, "error should contain chunk name")
end)

print("")
print("xdtc.template tests: %d passed, %d failed", passed, failed)
if failed > 0 then
    raise("xdtc.template test suite failed")
end
