-- action 声明脚本输入，数据树的组织方式由调用方决定。
local selection = import("selection")

function validate(name, action)
    if type(name) ~= "string" or name == "" or type(action) ~= "table" then
        raise("xdtc: action must be {script, select} or {entry, select}: %s", tostring(name))
    end
    if action.script ~= nil and action.entry ~= nil then
        raise("xdtc: action '%s' cannot provide both script and entry", name)
    end
    if action.entry ~= nil then
        if type(action.entry) ~= "function" then
            raise("xdtc: action '%s' entry must be a function", name)
        end
    elseif type(action.script) ~= "string" or action.script == "" then
        raise("xdtc: action '%s' requires a script path or entry function", name)
    end
    selection.validate(action.select, "action '" .. name .. "'")
end

function select(root, action, name)
    validate(name, action)
    return selection.select(root, action.select, "action '" .. name .. "'")
end
