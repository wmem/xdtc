local projectdir = path.absolute(path.join(os.scriptdir(), ".."))
local xdtc = import("xdtc", { rootdir = path.join(projectdir, "modules"), anonymous = true })
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
        raise(
            "test assertion failed: %s\nexpected: %s\nactual:   %s",
            message,
            tostring(expected),
            tostring(actual)
        )
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

local casedir = path.join(projectdir, "tests/case-config")
local outdir = path.join(casedir, "out")
os.rm(outdir)

testcase("load_config returns declarative config", function()
    local config, filepath = xdtc.load_config("xdtc.lua", { base_dir = casedir })
    equal(config.data, "data/root.lua", "config data")
    equal(config.tpl[1].out, "out/generated.txt", "config output")
    check(path.is_absolute(filepath), "resolved config path should be absolute")
end)

testcase("run_file resolves entry using supplied base_dir", function()
    local result = xdtc.run_file("xdtc.lua", { base_dir = casedir })
    equal(result.outputs[1].content, "uart0:32", "rendered content")
    equal(io.readfile(path.join(outdir, "generated.txt")), "uart0:32", "written output")
end)

testcase("run_file supports top-level overrides", function()
    os.rm(path.join(outdir, "override.txt"))
    local result = xdtc.run_file("custom.lua", {
        base_dir = casedir,
        overrides = {
            write = true,
            tpl = {
                {
                    files = { "tpl/*.tpl" },
                    out = "out/override.txt",
                },
            },
        },
    })
    equal(result.outputs[1].content, "uart0:32", "override content")
    equal(io.readfile(path.join(outdir, "override.txt")), "uart0:32", "override output")
end)

print("")
print("xdtc.config tests: %d passed, %d failed", passed, failed)
if failed > 0 then
    raise("xdtc.config test suite failed")
end
