set_project("xdtc-integration-example")
set_languages("c11")

-- This example lives under the xdtc repository itself. In a consumer project,
-- the normal form is: includes("tools/xdtc/xmake.lua")
includes("../../xmake.lua")

target("demo")
    set_kind("binary")
    add_rules("xdtc.codegen")
    add_files("src/main.c")
    -- The file does not exist when Xmake first scans the project. Keep it in
    -- the source list so on_prepare can generate it before compilation.
    add_files("build/generated.c", {always_added = true})
