import("core.base.option")
import("core.sandbox.module")

function main()
    -- 旧模块的内部 import 继续从插件私有资源查找，仅影响本次进程。
    local modules = path.join(os.scriptdir(), "runtime/modules")
    assert(
        os.isdir(modules),
        "插件尚未准备：请通过索引仓库安装，或先执行 scripts/prepare-addon.lua"
    )
    module.add_directories(modules)
    import("xdtc.integration", { rootdir = modules }).run(option.get("config"), {
        base_dir = os.projectdir(),
        once = false,
    })
end
