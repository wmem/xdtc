-- 每次脚本执行单独创建能力对象；数据、命令参数和脚本能力分别传入。
local template = import("template")

function new(directory)
    return {
        template = {
            render = function(source, data, opt)
                return template.render(source, data, opt)
            end,
            render_file = function(file, data, opt)
                if type(file) ~= "string" or file == "" then
                    raise("xdtc.api.template: render_file() expects a non-empty path string")
                end
                -- 模板与动作脚本可以随包一起移动，绝对路径直接使用。
                return template.render_file(path.absolute(file, directory), data, opt)
            end,
        },
    }
end
