-- xdtc.template
-- Tiny code-generation-oriented template engine for Xmake's embedded Lua.
-- Syntax is intentionally close to lua-resty-template:
--   {{ expr }}  escaped expression output (or raw when opt.escape == false)
--   {* expr *}  raw expression output
--   {% code %}  Lua statements
--   {# ... #}   comment

local _raw_load = debug.global("load")
local _raw_pcall = debug.global("pcall")
local _raw_pairs = debug.global("pairs")
local _raw_ipairs = debug.global("ipairs")
local _raw_next = debug.global("next")
local _raw_select = debug.global("select")
local _raw_tostring = debug.global("tostring")
local _raw_tonumber = debug.global("tonumber")
local _raw_type = debug.global("type")
local _raw_assert = debug.global("assert")
local _raw_error = debug.global("error")
local _raw_setmetatable = debug.global("setmetatable")
local _raw_rawget = debug.global("rawget")
local _raw_math = debug.global("math")
local _raw_string = debug.global("string")
local _raw_table = debug.global("table")
local _setfenv = debug.setfenv

local _cache = {}

local HTML_ENTITIES = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&#39;",
    ["/"] = "&#47;"
}

local function _output(value)
    if value == nil then
        return ""
    end
    if _raw_type(value) == "function" then
        return _output(value())
    end
    return _raw_tostring(value)
end

local function _escape(value)
    if _raw_type(value) ~= "string" then
        return _output(value)
    end
    return (_raw_string.gsub(value, "[\">/<'&]", HTML_ENTITIES))
end

local function _trim(value)
    return (_raw_string.gsub(_raw_string.gsub(value, "^%s+", ""), "%s+$", ""))
end

local function _rstrip_inline_whitespace(value)
    return (_raw_string.gsub(value, "[ \t\v\0]+$", ""))
end

local function _quote(value)
    return _raw_string.format("%q", value)
end

local function _append_literal(parts, literal)
    if literal ~= nil and literal ~= "" then
        parts[#parts + 1] = "___[#___+1]=" .. _quote(literal) .. "\n"
    end
end

local function _find_tag_end(source, start_pos, closer)
    return _raw_string.find(source, closer, start_pos, true)
end

local function _parse(source, opt)
    if _raw_type(source) ~= "string" then
        raise("xdtc.template: template source must be a string")
    end

    opt = opt or {}
    local escaped_by_default = opt.escape ~= false
    local parts = {
        "context=... or {}\n",
        "local ___={}\n",
        "local function echo(...)\n",
        "  for i=1,select('#', ...) do ___[#___+1]=__xtpl.output(select(i, ...)) end\n",
        "end\n"
    }

    local pos = 1
    local search_pos = 1
    while true do
        local open_pos = _raw_string.find(source, "{", search_pos, true)
        if not open_pos then
            _append_literal(parts, _raw_string.sub(source, pos))
            break
        end

        -- Backslash escapes a template opener: \\{{ -> {{, etc.
        if open_pos > 1 and _raw_string.sub(source, open_pos - 1, open_pos - 1) == "\\" then
            if pos <= open_pos - 2 then
                _append_literal(parts, _raw_string.sub(source, pos, open_pos - 2))
            end
            _append_literal(parts, "{")
            pos = open_pos + 1
            search_pos = open_pos + 1
        else
            local marker = _raw_string.sub(source, open_pos + 1, open_pos + 1)
            local closer
            local mode
            if marker == "{" then
                closer, mode = "}}", "expr"
            elseif marker == "*" then
                closer, mode = "*}", "raw"
            elseif marker == "%" then
                closer, mode = "%}", "code"
            elseif marker == "#" then
                closer, mode = "#}", "comment"
            end

            if not closer then
                search_pos = open_pos + 1
            else
                local body_start = open_pos + 2
                local close_pos = _find_tag_end(source, body_start, closer)
                if not close_pos then
                    raise("xdtc.template: unclosed template tag near byte %d", open_pos)
                end

                local close_end = close_pos + #closer
                local standalone = false
                if mode == "code" or mode == "comment" then
                    local before_line = _raw_string.match(_raw_string.sub(source, 1, open_pos - 1), "([^\r\n]*)$") or ""
                    local after_line = _raw_string.match(_raw_string.sub(source, close_end), "^([^\r\n]*)") or ""
                    standalone = _raw_string.match(before_line, "^[ \t\v\0]*$") ~= nil
                        and _raw_string.match(after_line, "^[ \t\v\0]*$") ~= nil
                end

                if standalone then
                    -- Only a code/comment tag that occupies the whole line trims that line.
                    local literal = _raw_string.sub(source, pos, open_pos - 1)
                    literal = _rstrip_inline_whitespace(literal)
                    _append_literal(parts, literal)
                else
                    _append_literal(parts, _raw_string.sub(source, pos, open_pos - 1))
                end

                local body = _trim(_raw_string.sub(source, body_start, close_pos - 1))
                if mode == "expr" then
                    parts[#parts + 1] = "___[#___+1]=__xtpl.value((" .. body .. ")," .. (escaped_by_default and "true" or "false") .. ")\n"
                elseif mode == "raw" then
                    parts[#parts + 1] = "___[#___+1]=__xtpl.value((" .. body .. "),false)\n"
                elseif mode == "code" then
                    if body ~= "" then
                        parts[#parts + 1] = body .. "\n"
                    end
                end

                local next_pos = close_end
                if standalone then
                    while _raw_string.sub(source, next_pos, next_pos) == " " or _raw_string.sub(source, next_pos, next_pos) == "\t" do
                        next_pos = next_pos + 1
                    end
                    if _raw_string.sub(source, next_pos, next_pos) == "\r" and _raw_string.sub(source, next_pos + 1, next_pos + 1) == "\n" then
                        next_pos = next_pos + 2
                    elseif _raw_string.sub(source, next_pos, next_pos) == "\n" then
                        next_pos = next_pos + 1
                    end
                end
                pos = next_pos
                search_pos = next_pos
            end
        end
    end

    parts[#parts + 1] = "return table.concat(___)\n"
    return _raw_table.concat(parts)
end

local function _new_environment(runtime)
    local env = {
        __xtpl = runtime,
        assert = _raw_assert,
        error = _raw_error,
        ipairs = _raw_ipairs,
        math = _raw_math,
        next = _raw_next,
        pairs = _raw_pairs,
        select = _raw_select,
        string = _raw_string,
        table = _raw_table,
        tonumber = _raw_tonumber,
        tostring = _raw_tostring,
        type = _raw_type
    }

    return _raw_setmetatable(env, {
        __index = function(t, key)
            local context = _raw_rawget(t, "context")
            if context ~= nil then
                local value = context[key]
                if value ~= nil then
                    return value
                end
            end
            return nil
        end
    })
end

local function _compile(source, opt)
    opt = opt or {}
    local parsed = _parse(source, opt)
    local chunkname = opt.chunkname or "@xdtc-template"
    local cache_key = opt.cache_key
    if cache_key ~= nil then
        cache_key = _raw_tostring(cache_key) .. "|escape=" .. _raw_tostring(opt.escape ~= false)
        if _cache[cache_key] ~= nil then
            return _cache[cache_key]
        end
    end

    local runtime = {
        output = _output,
        escape = _escape,
        value = function(value, escaped)
            if escaped then
                return _escape(value)
            end
            return _output(value)
        end
    }

    local chunk, load_errors = _raw_load(parsed, chunkname)
    if not chunk then
        raise("xdtc.template: failed to compile %s: %s", chunkname, _raw_tostring(load_errors))
    end
    _setfenv(chunk, _new_environment(runtime))

    local renderer = function(context)
        if context ~= nil and _raw_type(context) ~= "table" then
            raise("xdtc.template: render context must be a table or nil")
        end
        local ok, result = _raw_pcall(chunk, context or {})
        if not ok then
            raise("xdtc.template: render failed for %s: %s", chunkname, _raw_tostring(result))
        end
        return result
    end

    if cache_key ~= nil then
        _cache[cache_key] = renderer
    end
    return renderer
end

function parse(source, opt)
    return _parse(source, opt)
end

function compile(source, opt)
    return _compile(source, opt)
end

function render(source, context, opt)
    return _compile(source, opt)(context)
end

function compile_file(filepath, opt)
    if _raw_type(filepath) ~= "string" or #filepath == 0 then
        raise("xdtc.template: compile_file() expects a non-empty path string")
    end
    local absolute = path.normalize(path.absolute(filepath))
    if not os.isfile(absolute) then
        raise("xdtc.template: template file not found: %s", absolute)
    end
    local source = io.readfile(absolute)
    local file_opt = {}
    if opt then
        for key, value in _raw_pairs(opt) do
            file_opt[key] = value
        end
    end
    file_opt.chunkname = "@" .. absolute
    if file_opt.cache_key == nil and file_opt.cache ~= false then
        -- Include source in the key so edits during a long-running process recompile.
        file_opt.cache_key = absolute .. "\0" .. source
    end
    return _compile(source, file_opt)
end

function render_file(filepath, context, opt)
    return compile_file(filepath, opt)(context)
end

function output(value)
    return _output(value)
end

function escape(value)
    return _escape(value)
end

function clear_cache()
    _cache = {}
end
