return {
    meta = {
        version = "2.0.0"
    },
    alpha = {
        enable = true,
        match = "x*.tpl",
        title = "alpha <x>",
        root = "must-not-shadow-system-root"
    },
    beta = {
        enable = true,
        match = "*.tpl",
        title = "beta"
    },
    group = {
        nested = {
            enable = true,
            match = "xray.tpl",
            title = "nested"
        },
        disabled = {
            enable = false,
            match = "xray.tpl",
            title = "disabled"
        }
    },
    array_items = {
        {
            enable = true,
            match = "xray.tpl",
            title = "array-item-must-not-render"
        }
    }
}
