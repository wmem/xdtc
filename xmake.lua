-- xdtc drop-in Xmake integration.
--
-- Recommended consumer usage:
--     includes("tools/xdtc/xmake.lua")
--
-- This file intentionally does not call set_project()/set_version(), so it can
-- be included from a host project without changing that project's metadata.
-- It registers:
--     task("xdtc")          -> manual generation, default <project>/xdtc.lua
--     rule("xdtc.codegen") -> automatic generation in target on_prepare

local _xdtc_root = path.normalize(path.absolute(os.scriptdir()))
add_moduledirs(path.join(_xdtc_root, "modules"))

task("xdtc")
    set_menu {
        usage = "xmake xdtc [options]",
        description = "Generate files using xdtc",
        options = {
            {'c', "config", "kv", "xdtc.lua", "Set the xdtc configuration file."}
        }
    }
    on_run(function()
        import("core.base.option")
        local integration = import("xdtc.integration")
        integration.run(option.get("config") or "xdtc.lua", {
            base_dir = os.projectdir(),
            once = false
        })
    end)

rule("xdtc.codegen")
    on_prepare(function(target)
        local integration = import("xdtc.integration")

        local config = target:extraconf("rules", "xdtc.codegen", "config") or "xdtc.lua"
        local once = target:extraconf("rules", "xdtc.codegen", "once")
        local optional = target:extraconf("rules", "xdtc.codegen", "optional")

        if once == nil then
            once = true
        end
        if optional == nil then
            optional = false
        end

        integration.run(config, {
            base_dir = os.projectdir(),
            once = once,
            optional = optional
        })
    end)
