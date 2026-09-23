local projectdir = path.absolute(path.join(os.scriptdir(), ".."))
local xdtc = import("xdtc", {rootdir = path.join(projectdir, "modules"), anonymous = true})
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

local function expect_error(fn, needle)
    local ok, errors = raw_pcall(fn)
    check(not ok, "expected an error")
    local message = tostring(errors)
    check(message:find(needle, 1, true) ~= nil,
          "error did not contain '" .. needle .. "': " .. message)
end

local casedir = path.join(projectdir, "tests/case-generator")
local outdir = path.join(casedir, "out")
os.rm(outdir)
os.mkdir(outdir)

testcase("DTC-style end-to-end generation", function()
    local result = xdtc.run({
        base_dir = casedir,
        data = "data/root.lua",
        tpl = {
            {
                files = {"tpl/**/*.tpl", "tpl/nested/xray.tpl"},
                out = "out/generated.txt"
            },
            {
                files = {"tpl/empty/*.gen"},
                out = "out/empty.txt"
            }
        }
    })

    check(result.root.name == "root", "root name should be generated")
    check(result.root.alpha.name == "alpha", "child name should be generated")
    check(result.root.group.name == "group", "parent name should be generated")
    check(result.root.group.nested.name == "nested", "nested name should be generated")
    check(result.root.alpha.parent == nil, "parent must not be written back into data")
    check(result.root.array_items[1].name == nil, "array objects should not receive metadata")

    local expected = table.concat({
        "XRAY|name=alpha|parent=root|title=alpha <x>|root=root|tpl=xray.tpl",
        "XRAY|name=beta|parent=root|title=beta|root=root|tpl=xray.tpl",
        "XRAY|name=nested|parent=group|title=nested|root=root|tpl=xray.tpl",
        "BASE|name=beta|parent=root|title=beta|version=2.0.0"
    }, "\n")

    equal(result.outputs[1].content, expected, "aggregated rendering order/content")
    equal(io.readfile(path.join(outdir, "generated.txt")), expected, "output file content")
    equal(result.outputs[2].content, "", "unmatched task should be empty")
    equal(io.readfile(path.join(outdir, "empty.txt")), "", "empty output file should be created")
    check(#result.outputs[1].templates == 2, "duplicate discovered template should be removed")
end)

testcase("generate can render an existing root without writing", function()
    local root = xdtc.load(path.join(casedir, "data/root.lua"))
    local outputs = xdtc.generate(root, {
        {
            files = {"tpl/root/base.tpl"},
            out = "out/not-written.txt"
        }
    }, {
        base_dir = casedir,
        write = false
    })
    equal(outputs[1].content, "BASE|name=beta|parent=root|title=beta|version=2.0.0", "existing root generation")
    check(not os.isfile(path.join(outdir, "not-written.txt")), "write=false should not create output")
end)



testcase("input_template wraps final aggregated output", function()
    local root = xdtc.load(path.join(casedir, "data/root.lua"))
    local outputs = xdtc.generate(root, {
        {
            files = {"tpl/root/base.tpl"},
            input_template = "input/wrapper.txt",
            out = "out/wrapped.txt"
        }
    }, {
        base_dir = casedir
    })

    local raw = "BASE|name=beta|parent=root|title=beta|version=2.0.0"
    local expected = table.concat({
        "// generated wrapper begin",
        raw,
        "// literal template syntax stays literal: {{ name }}",
        "// generated wrapper end",
        ""
    }, "\n")

    equal(outputs[1].content, expected, "input_template final content")
    equal(io.readfile(path.join(outdir, "wrapped.txt")), expected, "input_template written content")
    check(outputs[1].input_template_applied == true, "existing input_template should be applied")
    check(outputs[1].input_template:find("input/wrapper.txt", 1, true) ~= nil,
          "result should expose resolved input_template path")
end)

testcase("missing input_template falls back to direct output", function()
    local root = xdtc.load(path.join(casedir, "data/root.lua"))
    local outputs = xdtc.generate(root, {
        {
            files = {"tpl/root/base.tpl"},
            input_template = "input/not-found.txt",
            out = "out/missing-wrapper.txt"
        }
    }, {
        base_dir = casedir
    })

    local expected = "BASE|name=beta|parent=root|title=beta|version=2.0.0"
    equal(outputs[1].content, expected, "missing input_template should preserve raw content")
    equal(io.readfile(path.join(outdir, "missing-wrapper.txt")), expected,
          "missing input_template should write raw content")
    check(outputs[1].input_template_applied == false, "missing input_template must not be applied")
end)

testcase("input_template requires content placeholder when file exists", function()
    local root = xdtc.load(path.join(casedir, "data/root.lua"))
    expect_error(function()
        xdtc.generate(root, {
            {
                files = {"tpl/root/base.tpl"},
                input_template = "input/no-placeholder.txt",
                out = "out/invalid-wrapper.txt"
            }
        }, {
            base_dir = casedir
        })
    end, "input_template must contain {{.}} placeholder")
end)

testcase("duplicate output paths are rejected", function()
    local root = xdtc.load(path.join(casedir, "data/root.lua"))
    expect_error(function()
        xdtc.generate(root, {
            {files = {"tpl/root/base.tpl"}, out = "out/same.txt"},
            {files = {"tpl/nested/xray.tpl"}, out = "out/same.txt"}
        }, {base_dir = casedir, write = false})
    end, "duplicate output file")
end)

print("")
print("xdtc.generator tests: %d passed, %d failed", passed, failed)
if failed > 0 then
    raise("xdtc.generator test suite failed")
end
