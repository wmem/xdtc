local projectdir = path.absolute(path.join(os.scriptdir(), ".."))
local integration = import("xdtc.integration", {rootdir = path.join(projectdir, "modules"), anonymous = true})
local raw_pcall = debug.global("pcall")

local passed = 0
local failed = 0

local function check(condition, message)
    if not condition then
        raise("test assertion failed: %s", message)
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

testcase("integration defaults to once per config", function()
    integration.reset()
    local a = integration.run("xdtc.lua", {base_dir = casedir, once = true})
    local b = integration.run("xdtc.lua", {base_dir = casedir, once = true})
    check(a == b, "same config should return cached result")
end)

testcase("integration optional config may be absent", function()
    integration.reset()
    local result = integration.run("does-not-exist.lua", {
        base_dir = casedir,
        optional = true
    })
    check(result == nil, "optional missing config should return nil")
end)

print("")
print("xdtc.integration tests: %d passed, %d failed", passed, failed)
if failed > 0 then
    raise("xdtc.integration test suite failed")
end
