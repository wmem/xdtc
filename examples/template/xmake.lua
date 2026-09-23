add_moduledirs("../../modules")

task("render")
    set_menu {
        usage = "xmake render",
        description = "Render a small SystemVerilog template"
    }
    on_run(function()
        local template = import("xdtc.template")
        local result = template.render_file(path.join(os.projectdir(), "templates/module.sv.tpl"), {
            name = "uart",
            params = {
                {name = "WIDTH", value = 32},
                {name = "DEPTH", value = 16}
            },
            body = "logic ready;"
        })
        io.writefile(path.join(os.projectdir(), "generated.sv"), result)
        print(result)
    end)
