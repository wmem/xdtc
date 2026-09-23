-- Debug snapshot helpers used by xdtc.run() and tests.

local kind = import("kind")
local json = import("core.base.json")
local _pairs = debug.global("pairs")

local function _clone(value)
    if kind.is_array(value) or json.is_marked_as_array(value) then
        local result = {}
        json.mark_as_array(result)
        for index, item in ipairs(value) do
            result[index] = _clone(item)
        end
        return result
    end

    if kind.is_object(value) then
        local result = {}
        for key, item in _pairs(value) do
            result[key] = _clone(item)
        end
        return result
    end

    return value
end

function clone(value)
    return _clone(value)
end

function array(value)
    value = value or {}
    json.mark_as_array(value)
    return value
end

function write_json(filepath, value)
    local dir = path.directory(filepath)
    if dir and #dir > 0 and not os.isdir(dir) then
        os.mkdir(dir)
    end
    io.writefile(filepath, json.encode(value, {pretty = true}) .. "\n")
end
