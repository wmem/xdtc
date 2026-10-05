-- 全局命令只声明参数，不加载消费工程的配置或生成文件。
task("xdtc")
set_category("plugin")
set_menu({
    usage = "xmake xdtc [options]",
    description = "根据数据和模板生成文件",
    options = {
        { "c", "config", "kv", "xdtc.lua", "配置文件，路径相对于工程根目录" },
    },
})
on_run("main")
