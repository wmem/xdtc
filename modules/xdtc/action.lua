-- action 声明脚本输入，数据树的组织方式由调用方决定。
local selection = import("selection")

function validate(name, action)
    if type(name) ~= "string" or name == "" or type(action) ~= "table" then
        raise("xdtc: action must be {script, select}: %s", tostring(name))
    end
    if type(action.script) ~= "string" or action.script == "" then
        raise("xdtc: action '%s' requires a script path", name)
    end
    selection.validate(action.select, "action '" .. name .. "'")
end

function select(root, action, name)
    validate(name, action)
    return selection.select(root, action.select, "action '" .. name .. "'")
end
