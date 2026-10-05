-- 公开既有生成 API；核心仍从插件私有资源加载，不复制实现。
import("core.sandbox.module")
local modules = path.join(os.scriptdir(), "../plugins/xdtc/runtime/modules")
module.add_directories(modules)
inherit("xdtc", { rootdir = modules })
