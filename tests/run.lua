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

testcase("basic DTC-style data build", function()
    local root = xdtc.load(path.join(projectdir, "tests/case-basic/data/root.lua"))
    check(root.name == "root", "root metadata")
    check(root.meta.version == "1.0.0", "root merge")
    check(root.meta.extra == "added-by-update", "update object")
    check(root.meta.patched_by_side_effect == true, "update_root")
    check(root.meta.detail_title_before_update == "detail-from-sub", "get before update")
    check(root.meta.second_lookup_name == "second-item", "1-based array lookup")
    check(root.modules.obsolete == nil, "remove")
    check(root.modules.detail.title == "detail-updated-by-root", "scalar update")
    check(root.modules.detail.patched_by_side_effect == "yes", "get returns live object")
    check(root.docs.item.note == "created-before-merge", "replace before final merge")
    check(root.docs.item.title == "detail-from-root", "deep merge after replace")
    check(root.modules.name == "modules", "nested metadata")
    check(root.lookup.items[1].name == "first-item", "array preserved")
end)

testcase("metadata can be disabled", function()
    local root = xdtc.load(path.join(projectdir, "tests/case-basic/data/root.lua"), {metadata = false})
    check(root.name == nil, "root should not receive metadata")
    check(root.modules.name == nil, "nested object should not receive metadata")
end)

testcase("circular include detection", function()
    expect_error(function()
        xdtc.load(path.join(projectdir, "tests/case-circular/data/root.lua"))
    end, "circular include detected")
end)

testcase("merge type conflict", function()
    expect_error(function()
        xdtc.load(path.join(projectdir, "tests/case-errors/data/type-conflict.lua"))
    end, "cannot merge mismatched values")
end)

testcase("update scalar requires existing path", function()
    expect_error(function()
        xdtc.load(path.join(projectdir, "tests/case-errors/data/update-missing.lua"))
    end, "target path does not exist")
end)

print("")
print("xdtc tests: %d passed, %d failed", passed, failed)
if failed > 0 then
    raise("xdtc test suite failed")
end
