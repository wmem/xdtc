add_moduledirs("../../modules")

task("codegen")
    set_menu {
        usage = "xmake codegen",
        description = "Generate code with DTC-style xdtc matching"
    }
    on_run(function()
        local xdtc = import("xdtc")
        local result = xdtc.run({
            base_dir = os.projectdir(),
            data = "data/root.lua",
            tpl = {
                {
                    files = {"templates/module.sv.tpl"},
                    input_template = "templates/output.sv.in",
                    out = "build/generated.sv"
                }
            }
        })
        print("generated: %s", result.outputs[1].output)
    end)
