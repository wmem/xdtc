local projectdir = path.absolute(path.join(os.scriptdir(), ".."))
local moduledir = path.join(projectdir, "modules")
local cases = path.join(projectdir, "tests/dtc_compat")
local xdtc = import("xdtc", {rootdir = moduledir, anonymous = true})
local pathops = import("xdtc.pathops", {rootdir = moduledir, anonymous = true})
local query = import("xdtc.query", {rootdir = moduledir, anonymous = true})
local json = import("core.base.json", {anonymous = true})
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
        raise("test assertion failed: %s\nexpected: %s\nactual:   %s", message, tostring(expected), tostring(actual))
    end
end

local function contains(text, expected, message)
    check(tostring(text):find(expected, 1, true) ~= nil,
          message .. "\nactual: " .. tostring(text))
end

local function testcase(name, fn)
    local ok, errors = raw_pcall(fn)
    if ok then
        passed = passed + 1
        cprint("${bright green}[PASS]${clear} DTC %s", name)
    else
        failed = failed + 1
        cprint("${bright red}[FAIL]${clear} DTC %s", name)
        print(errors)
    end
end

local function expect_error(fn, needle, message)
    local ok, errors = raw_pcall(fn)
    check(not ok, message or "expected an error")
    contains(errors, needle, message or "error text mismatch")
end

local function endswith(value, suffix)
    return value:sub(-#suffix) == suffix
end

local function clean(case_name)
    os.rm(path.join(cases, case_name, "out"))
    os.rm(path.join(cases, case_name, "debug"))
end

testcase("version", function()
    local version = xdtc.version()
    check(type(version) == "string" and #version > 0, "version should be non-empty")
    check(version:match("^%d+%.%d+%.%d+$") ~= nil, "version should use x.y.z")
    local readme = io.readfile(path.join(projectdir, "README.md"))
    check(readme:find("# xdtc v" .. version .. "\n", 1, true) == 1,
          "README title should match xdtc.version()")
    local usage = io.readfile(path.join(projectdir, "docs/USAGE.md"))
    check(usage:find("print(xdtc.version()) -- " .. version, 1, true) ~= nil,
          "USAGE version example should match xdtc.version()")
end)

testcase("data-script DSL is scoped and include is relative", function()
    local original_include = debug.global("include")
    local original_update_root = debug.global("updateRoot")
    local root = xdtc.load(path.join(cases, "case-script-globals/data/root.lua"))

    check(root.child.loaded == true, "include should resolve relative to current data file")
    check(root.meta.fromInstallTest == true, "updateRoot compatibility alias should work")
    check(debug.global("include") == original_include, "data DSL include must not leak into global Lua")
    check(debug.global("updateRoot") == original_update_root, "data DSL updateRoot must not leak into global Lua")
end)

testcase("updateRoot", function()
    local root = xdtc.load(path.join(cases, "case-update-root/data/root.lua"))
    equal(root.meta.version, "1.0.0", "updateRoot should preserve later compatible fields")
    equal(root.meta.name, "demo", "updateRoot should merge an existing object")
    check(root.flags.enabled == true, "updateRoot should create missing top-level objects")

    expect_error(function()
        xdtc.load(path.join(cases, "case-update-root/data/invalid.lua"))
    end, "update_root() expects an object patch", "updateRoot should reject scalar patch")
end)

testcase("replace/update edge cases", function()
    local root = {
        meta = {
            version = "1.0.0",
            nested = {
                enabled = true
            }
        }
    }

    pathops.replace(root, "meta.version", "2.0.0")
    equal(root.meta.version, "2.0.0", "replace scalar")

    pathops.update(root, "meta", {
        nested = {
            name = "demo"
        }
    })
    check(root.meta.nested.enabled == true, "update object should preserve old fields")
    equal(root.meta.nested.name, "demo", "update object should add fields")

    pathops.update(root, "meta.version", "3.0.0")
    equal(root.meta.version, "3.0.0", "update scalar with same kind")

    expect_error(function()
        pathops.replace({meta = "text"}, "meta.version", "2.0.0")
    end, "replace() cannot create nested property through non-object path: meta", "replace through scalar")

    expect_error(function()
        pathops.update({meta = "text"}, "meta", {version = "2.0.0"})
    end, "update() target must be an object: meta", "update object into scalar")

    expect_error(function()
        pathops.update({meta = 1}, "meta", "bad-patch")
    end, "update() value kind mismatch at meta", "update scalar kind mismatch")

    expect_error(function()
        pathops.update({}, "meta.version", "3.0.0")
    end, "update() target path does not exist for non-object value: meta.version", "update missing scalar")
end)

testcase("basic DTC workflow plus debug outputs", function()
    clean("case-basic")
    local casedir = path.join(cases, "case-basic")
    local root = xdtc.load(path.join(casedir, "data/root.lua"))
    local matched = query.collect(root)

    equal(root.name, "root", "root name")
    check(root.parent == nil, "root should not store parent")
    equal(root.modules.name, "modules", "automatic child name")
    check(root.modules.parent == nil, "ordinary objects should not store parent")
    check(root.modules.obsolete == nil, "remove")
    equal(root.modules.detail.title, "detail-updated-by-root", "scalar update")
    equal(root.modules.detail.patchedBySideEffect, "yes", "get returns live object")
    equal(root.meta.extra, "added-by-update", "object update")
    equal(root.meta.detailTitleBeforeUpdate, "detail-from-sub", "get before update")
    equal(root.meta.secondLookupName, "second-item", "1-based array lookup")
    check(root.meta.patchedBySideEffect == true, "updateRoot side effect")
    equal(root.docs.item.note, "created-before-merge", "replace before return merge")
    check(root.docs.item.parent == nil, "child should not store parent")
    equal(#matched, 3, "only enable=true object nodes should be render candidates")

    local result = xdtc.run({
        base_dir = casedir,
        data = "data/root.lua",
        debugDataOut = "debug/global-data.json",
        debugMatchOut = "debug/match-data.json",
        tpl = {
            {
                files = {"tpl/*.tpl"},
                out = "out/generated.txt"
            }
        }
    })

    -- Lua object traversal is deliberately deterministic by sorted key, unlike JS insertion order.
    local expected = table.concat({
        "DETAIL|name=item|parent=docs|title=detail-from-root|version=1.0.0",
        "DETAIL|name=detail|parent=modules|title=detail-updated-by-root|version=1.0.0",
        "MAIN|name=modules|parent=root|title=main-from-root|version=1.0.0"
    }, "\n")
    equal(io.readfile(path.join(casedir, "out/generated.txt")), expected, "basic rendered output")
    equal(result.outputs[1].content, expected, "returned rendered output")

    local debug_data = json.decode(io.readfile(path.join(casedir, "debug/global-data.json")))
    check(debug_data.name == nil, "debug data should be captured before automatic name metadata")
    check(debug_data.parent == nil, "debug data should not contain parent")
    check(debug_data.modules.obsolete == nil, "debug data should reflect remove")
    equal(debug_data.modules.detail.title, "detail-updated-by-root", "debug data scalar update")
    equal(debug_data.modules.detail.patchedBySideEffect, "yes", "debug data live-object patch")
    equal(debug_data.meta.extra, "added-by-update", "debug data object update")
    equal(debug_data.meta.secondLookupName, "second-item", "debug data array get")
    check(debug_data.meta.patchedBySideEffect == true, "debug data updateRoot")
    equal(debug_data.docs.item.note, "created-before-merge", "debug data replace")
    equal(debug_data.docs.item.title, "detail-from-root", "debug data final merge")

    local debug_match = json.decode(io.readfile(path.join(casedir, "debug/match-data.json")))
    equal(#debug_match, 2, "debug match should contain one record per discovered template")
    check(endswith(debug_match[1].templatePath, "/detail.tpl"), "first debug match template")
    equal(#debug_match[1].matchedObjects, 2, "detail.tpl matched objects")
    check(debug_match[1].matchedObjects[1].parent == nil, "debug match object must not contain parent")
    equal(debug_match[1].matchedObjects[1].name, "item", "deterministic sorted traversal first detail item")
    equal(debug_match[1].matchedObjects[2].name, "detail", "second detail item")
    check(endswith(debug_match[2].templatePath, "/main.tpl"), "second debug match template")
    equal(#debug_match[2].matchedObjects, 1, "main.tpl matched objects")
    equal(debug_match[2].matchedObjects[1].name, "modules", "main match name")
end)

testcase("empty output", function()
    clean("case-empty-output")
    local casedir = path.join(cases, "case-empty-output")
    xdtc.run({
        base_dir = casedir,
        data = "data/root.lua",
        debug_match_out = "debug/match-data.json",
        tpl = {{files = {"tpl/*.tpl"}, out = "out/generated.txt"}}
    })
    equal(io.readfile(path.join(casedir, "out/generated.txt")), "", "no matches should create an empty file")
    local debug_text = io.readfile(path.join(casedir, "debug/match-data.json"))
    contains(debug_text, '"matchedObjects": []', "zero-match debug list should remain a JSON array")
end)

testcase("wildcard matching", function()
    clean("case-wildcard")
    local casedir = path.join(cases, "case-wildcard")
    xdtc.run({
        base_dir = casedir,
        data = "data/root.lua",
        tpl = {{files = {"tpl/**/*.tpl"}, out = "out/generated.txt"}}
    })
    local expected = table.concat({
        "XRAY|alpha|alpha",
        "XRAY|beta|beta",
        "XRAY|nested|nested",
        "BASE|beta|beta"
    }, "\n")
    equal(io.readfile(path.join(casedir, "out/generated.txt")), expected, "wildcard rendered output")
end)

testcase("enable filter", function()
    clean("case-enable-filter")
    local casedir = path.join(cases, "case-enable-filter")
    local root = xdtc.load(path.join(casedir, "data/root.lua"))
    equal(#query.collect(root), 1, "only enable=true should enter candidate list")

    xdtc.run({
        base_dir = casedir,
        data = "data/root.lua",
        tpl = {{files = {"tpl/*.tpl"}, out = "out/generated.txt"}}
    })
    equal(io.readfile(path.join(casedir, "out/generated.txt")), "ENABLED|enabledItem|render-me", "enable filter output")
end)

testcase("get missing path", function()
    expect_error(function()
        xdtc.load(path.join(cases, "case-get-missing/data/root.lua"))
    end, "get() path does not exist: meta", "get should fail immediately for missing path")
end)

testcase("merge type mismatch", function()
    expect_error(function()
        xdtc.load(path.join(cases, "case-type-mismatch/data/root.lua"))
    end, "cannot merge mismatched values at conflict", "merge mismatch should name conflict path")
end)

testcase("circular include", function()
    expect_error(function()
        xdtc.load(path.join(cases, "case-circular/data/root.lua"))
    end, "circular include detected", "circular include should fail")
end)

print("")
print("xdtc DTC compatibility tests: %d passed, %d failed", passed, failed)
if failed > 0 then
    raise("xdtc DTC compatibility test suite failed")
end
