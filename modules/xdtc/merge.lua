local kind = import("kind")
local _pairs = debug.global("pairs")

local function _format_path(dotted_path)
    if dotted_path and #dotted_path > 0 then
        return dotted_path
    end
    return "root"
end

-- Recursively merge source into target.
-- Objects merge recursively, arrays replace, scalars replace only when kinds match.
function merge_into(target, source, dotted_path)
    if not kind.is_object(source) then
        raise("xdtc: merge source must be an object at %s", _format_path(dotted_path))
    end
    if not kind.is_object(target) then
        raise("xdtc: merge target must be an object at %s", _format_path(dotted_path))
    end

    for key, source_value in _pairs(source) do
        local next_path = dotted_path and #dotted_path > 0 and (dotted_path .. "." .. tostring(key)) or tostring(key)
        local target_value = target[key]

        if target_value == nil then
            target[key] = source_value
        else
            local target_kind = kind.kind(target_value)
            local source_kind = kind.kind(source_value)

            if target_kind == "object" and source_kind == "object" then
                merge_into(target_value, source_value, next_path)
            elseif target_kind == "array" and source_kind == "array" then
                target[key] = source_value
            elseif target_kind ~= "object" and target_kind ~= "array" and target_kind == source_kind then
                target[key] = source_value
            else
                raise("xdtc: cannot merge mismatched values at %s (%s ~= %s)",
                      _format_path(next_path), target_kind, source_kind)
            end
        end
    end
    return target
end
