-- 字符串选择已有对象，函数组装对象；返回独立数据，不修改调用方的数据树。
local snapshot = import("debug_output")
local raw_pcall = debug.global("pcall")

function validate(selector, context)
    if type(selector) ~= "string" and type(selector) ~= "function" then
        raise("xdtc: %s requires select (object path or function)", context)
    end
    if type(selector) == "string" and selector ~= "." then
        if
            selector == ""
            or selector:startswith(".")
            or selector:endswith(".")
            or selector:find("..", 1, true)
        then
            raise("xdtc: %s has an invalid select path: %s", context, selector)
        end
    end
end

function select(root, selector, context)
    context = context or "configuration"
    validate(selector, context)
    local value = root
    if type(selector) == "function" then
        local ok, result = raw_pcall(selector, snapshot.clone(root))
        if not ok then
            raise("xdtc: %s select failed: %s", context, tostring(result))
        end
        value = result
    elseif selector ~= "." then
        for key in selector:gmatch("[^.]+") do
            if type(value) ~= "table" or value[key] == nil then
                raise("xdtc: %s select path not found: %s", context, selector)
            end
            value = value[key]
        end
    end
    if type(value) ~= "table" then
        raise("xdtc: %s select must return an object", context)
    end
    return snapshot.clone(value)
end
