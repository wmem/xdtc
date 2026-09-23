local kind = import("kind")
local _pairs = debug.global("pairs")

local function _decorate(current, name)
    if not kind.is_object(current) then
        return
    end

    if current.name == nil then
        current.name = name
    end

    for key, value in _pairs(current) do
        if kind.is_object(value) then
            _decorate(value, tostring(key))
        end
    end
end

function apply(root)
    _decorate(root, "root")
    return root
end
