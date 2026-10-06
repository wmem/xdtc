-- action 声明脚本输入，数据树的组织方式由调用方决定。
local snapshot = import("debug_output")
local raw_pcall = debug.global("pcall")

function validate(name, action)
    if type(name) ~= "string" or name == "" or type(action) ~= "table" then
        raise("xdtc: action must be {script, select}: %s", tostring(name))
    end
    if type(action.script) ~= "string" or action.script == "" then
        raise("xdtc: action '%s' requires a script path", name)
    end
    local selector = action.select
    if type(selector) ~= "string" and type(selector) ~= "function" then
        raise("xdtc: action '%s' requires select (object path or function)", name)
    end
    if type(selector) == "string" and selector ~= "." then
        if
            selector == ""
            or selector:startswith(".")
            or selector:endswith(".")
            or selector:find("..", 1, true)
        then
            raise("xdtc: action '%s' has an invalid select path: %s", name, selector)
        end
    end
end

function select(root, action, name)
    validate(name, action)
    local value = root
    if type(action.select) == "function" then
        -- 筛选函数可重组或补充参数，避免修改后续使用的原始数据。
        local ok, result = raw_pcall(action.select, snapshot.clone(root))
        if not ok then
            raise("xdtc: action '%s' select failed: %s", name, tostring(result))
        end
        value = result
    elseif action.select ~= "." then
        for key in action.select:gmatch("[^.]+") do
            if type(value) ~= "table" or value[key] == nil then
                raise("xdtc: action '%s' select path not found: %s", name, action.select)
            end
            value = value[key]
        end
    end
    if type(value) ~= "table" then
        raise("xdtc: action '%s' select must return an object", name)
    end
    -- 脚本拿到独立对象，不将默认值或运行时修改写回 root。
    return snapshot.clone(value)
end
