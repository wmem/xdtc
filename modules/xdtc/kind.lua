-- xdtc value-kind helpers.

function is_array(value)
    return type(value) == "table" and value[1] ~= nil
end

function is_object(value)
    return type(value) == "table" and value[1] == nil
end

function kind(value)
    local value_type = type(value)
    if value_type ~= "table" then
        return value_type
    end
    if is_array(value) then
        return "array"
    end
    return "object"
end

function is_scalar(value)
    return type(value) ~= "table"
end
