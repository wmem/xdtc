-- 配置域只声明来源与选择；返回的读取函数必须由使用方在脚本环境中调用。
function xdtc_config(file)
    local config_file = path.absolute(file or "xdtc.lua", os.scriptdir())
    return {
        select = function(self, selector)
            return function()
                local generator = import("@addon.xdtc.generator")
                return generator.read_config(config_file, selector)
            end
        end,
        select_action = function(self, name)
            return function()
                local generator = import("@addon.xdtc.generator")
                return generator.read_action_config(config_file, name)
            end
        end,
    }
end
