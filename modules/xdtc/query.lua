-- Collect renderable objects from the final root tree.
-- Arrays are intentionally not traversed, matching DTC.

local kind = import("kind")
local _pairs = debug.global("pairs")
local _table = debug.global("table")
local _tostring = debug.global("tostring")

local function _sorted_object_keys(node)
    local keys = {}
    for key, _ in _pairs(node) do
        if type(key) == "string" or type(key) == "number" then
            keys[#keys + 1] = key
        end
    end
    _table.sort(keys, function(a, b)
        return _tostring(a) < _tostring(b)
    end)
    return keys
end

local function _visit(node, parent, dotted_path, result)
    if not kind.is_object(node) then
        return
    end

    if node.enable == true and type(node.match) == "string" and #node.match > 0 then
        result[#result + 1] = {
            node = node,
            parent = parent,
            path = dotted_path
        }
    end

    for _, key in ipairs(_sorted_object_keys(node)) do
        local value = node[key]
        if kind.is_object(value) then
            local child_path
            if dotted_path == nil or dotted_path == "" then
                child_path = tostring(key)
            else
                child_path = dotted_path .. "." .. tostring(key)
            end
            _visit(value, node, child_path, result)
        end
    end
end

function collect(root)
    local result = {}
    _visit(root, nil, "root", result)
    return result
end
