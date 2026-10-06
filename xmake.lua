-- xdtc drop-in Xmake integration.
--
-- Recommended consumer usage:
--     includes("tools/xdtc/xmake.lua")
--
-- This file intentionally does not call set_project()/set_version(), so it can
-- be included from a host project without changing that project's metadata.
-- It registers:
--     task("xdtc")          -> gen/data/run 或工程注册的动作
--     rule("xdtc.codegen") -> automatic generation in target on_prepare

local _xdtc_root = path.normalize(path.absolute(os.scriptdir()))
add_moduledirs(path.join(_xdtc_root, "modules"))

task("xdtc")
set_menu({
    usage = "xmake xdtc [options] <gen|data|run|action> [args]",
    description = "展开配置、生成文件或执行工程动作",
    options = {
        {
            "c",
            "config",
            "kv",
            "xdtc.lua",
            "配置文件，默认相对当前目录；-P 显式选择工程目录",
        },
        { nil, "command", "v", nil, "gen/data/run 或动作名" },
        { nil, "arguments", "vs", nil, "脚本及位置参数" },
    },
})
on_run(function()
    import("core.base.option")
    import("xdtc.command").run(
        option.get("config"),
        option.get("command"),
        option.get("arguments"),
        {
            base_dir = option.get("project") and os.projectdir() or os.workingdir(),
        }
    )
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
        optional = optional,
    })
end)
