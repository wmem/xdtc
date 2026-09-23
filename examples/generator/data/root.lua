return {
    project = {
        version = "1.0.0"
    },
    soc = {
        uart0 = {
            enable = true,
            match = "module.sv.tpl",
            width = 32,
            body = "logic ready;"
        },
        gpio0 = {
            enable = true,
            match = "module.sv.tpl",
            width = 16,
            body = "logic [15:0] gpio;"
        }
    }
}
