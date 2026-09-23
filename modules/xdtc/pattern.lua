-- Shared wildcard matching used by template discovery and data-node match rules.
-- Semantics follow DTC: * and ? match within one segment; ** matches zero or more path segments.

local _string = debug.global("string")
local _table = debug.global("table")

function has_wildcards(pattern)
    return type(pattern) == "string" and (pattern:find("*", 1, true) ~= nil or pattern:find("?", 1, true) ~= nil)
end

function match_segment(text, pattern)
    if type(text) ~= "string" or type(pattern) ~= "string" then
        return false
    end

    local ti, pi = 1, 1
    local star_pi = nil
    local star_ti = nil
    local text_len, pattern_len = #text, #pattern

    while ti <= text_len do
        local pc = pi <= pattern_len and pattern:sub(pi, pi) or nil
        local tc = text:sub(ti, ti)

        if pc == "?" or pc == tc then
            ti = ti + 1
            pi = pi + 1
        elseif pc == "*" then
            star_pi = pi
            star_ti = ti
            pi = pi + 1
        elseif star_pi ~= nil then
            star_ti = star_ti + 1
            ti = star_ti
            pi = star_pi + 1
        else
            return false
        end
    end

    while pi <= pattern_len and pattern:sub(pi, pi) == "*" do
        pi = pi + 1
    end
    return pi > pattern_len
end

local function _split(value)
    value = value:gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", "")
    local result = {}
    for part in value:gmatch("[^/]+") do
        result[#result + 1] = part
    end
    return result
end

local function _match_path(path_parts, pattern_parts, path_index, pattern_index)
    if pattern_index > #pattern_parts then
        return path_index > #path_parts
    end

    local token = pattern_parts[pattern_index]
    if token == "**" then
        if pattern_index == #pattern_parts then
            return true
        end
        for i = path_index, #path_parts + 1 do
            if _match_path(path_parts, pattern_parts, i, pattern_index + 1) then
                return true
            end
        end
        return false
    end

    if path_index > #path_parts then
        return false
    end
    if not match_segment(path_parts[path_index], token) then
        return false
    end
    return _match_path(path_parts, pattern_parts, path_index + 1, pattern_index + 1)
end

function match_path(filepath, pattern)
    if type(filepath) ~= "string" or type(pattern) ~= "string" then
        return false
    end
    return _match_path(_split(filepath), _split(pattern), 1, 1)
end
