add_moduledirs("../../modules")

task("show_data")
    set_menu {
        usage = "xmake show_data",
        description = "Show the xdtc root tree"
    }
    on_run(function()
        local xdtc = import("xdtc")
        local root = xdtc.load(path.join(os.projectdir(), "data/root.lua"))
        print(root)
    end)
