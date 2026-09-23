local kind = import("kind")
local merge = import("merge")

local function _parts(dotted_path, opname)
    if type(dotted_path) ~= "string" or #dotted_path == 0 then
        raise("xdtc: %s() expects a non-empty dotted path string", opname)
    end

    local result = {}
    for part in dotted_path:gmatch("[^.]+") do
        if #part > 0 then
            table.insert(result, part)
        end
    end
    if #result == 0 then
        raise("xdtc: %s() expects a valid dotted path string", opname)
    end
    return result
end

local function _is_array_index(part)
    if not part:match("^[1-9][0-9]*$") then
        return false
    end
    return true
end

local function _join(parts, last)
    local result = {}
    for i = 1, last do
        table.insert(result, parts[i])
    end
    return table.concat(result, ".")
end

function get(target, dotted_path)
    local parts = _parts(dotted_path, "get")
    local current = target

    for i, key in ipairs(parts) do
        local current_kind = kind.kind(current)
        local current_path = _join(parts, i)

        if current_kind == "array" then
            if not _is_array_index(key) then
                raise("xdtc: get() cannot access array with non-numeric/zero index: %s", current_path)
            end
            local index = tonumber(key)
            if current[index] == nil then
                raise("xdtc: get() path does not exist: %s", current_path)
            end
            current = current[index]
        elseif current_kind == "object" then
            if current[key] == nil then
                raise("xdtc: get() path does not exist: %s", current_path)
            end
            current = current[key]
        else
            raise("xdtc: get() cannot continue through non-container path: %s", _join(parts, i - 1))
        end
    end
    return current
end

function remove(target, dotted_path)
    local parts = _parts(dotted_path, "remove")
    local current = target

    for i = 1, #parts - 1 do
        if not kind.is_object(current) then
            return
        end
        current = current[parts[i]]
        if current == nil then
            return
        end
    end

    if kind.is_object(current) then
        current[parts[#parts]] = nil
    end
end

function replace(target, dotted_path, value)
    if value == nil then
        raise("xdtc: replace() does not accept nil; use remove() to delete a value")
    end

    local parts = _parts(dotted_path, "replace")
    local current = target

    for i = 1, #parts - 1 do
        local key = parts[i]
        if current[key] == nil then
            current[key] = {}
        elseif not kind.is_object(current[key]) then
            raise("xdtc: replace() cannot create nested property through non-object path: %s", _join(parts, i))
        end
        current = current[key]
    end

    current[parts[#parts]] = value
end

function update(target, dotted_path, patch)
    if patch == nil then
        raise("xdtc: update() does not accept nil")
    end

    local parts = _parts(dotted_path, "update")
    local current = target

    for i = 1, #parts - 1 do
        local key = parts[i]
        if current[key] == nil then
            current[key] = {}
        elseif not kind.is_object(current[key]) then
            raise("xdtc: update() cannot create nested property through non-object path: %s", _join(parts, i))
        end
        current = current[key]
    end

    local target_key = parts[#parts]
    local full_path = table.concat(parts, ".")

    if kind.is_object(patch) then
        if current[target_key] == nil then
            current[target_key] = {}
        elseif not kind.is_object(current[target_key]) then
            raise("xdtc: update() target must be an object: %s", full_path)
        end
        merge.merge_into(current[target_key], patch, full_path)
        return
    end

    if current[target_key] == nil then
        raise("xdtc: update() target path does not exist for non-object value: %s", full_path)
    end

    local target_kind = kind.kind(current[target_key])
    local patch_kind = kind.kind(patch)
    if target_kind ~= patch_kind then
        raise("xdtc: update() value kind mismatch at %s (%s ~= %s)", full_path, target_kind, patch_kind)
    end
    current[target_key] = patch
end
