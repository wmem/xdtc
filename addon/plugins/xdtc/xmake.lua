-- 全局命令只声明参数，不加载消费工程的配置或生成文件。
task("xdtc")
set_category("plugin")
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
        { nil, "command", "v", nil, "保留命令 gen/data/run，或 actions 中的动作名" },
        { nil, "arguments", "vs", nil, "run 的脚本路径及传给脚本的位置参数" },
    },
})
on_run("main")
