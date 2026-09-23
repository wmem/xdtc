-- DTC-style data/template matching and output aggregation.

local kind = import("kind")
local metadata = import("metadata")
local pattern = import("pattern")
local query = import("query")
local template_engine = import("template")
local debug_output = import("debug_output")

local _pairs = debug.global("pairs")
local _pcall = debug.global("pcall")
local _table = debug.global("table")
local _tostring = debug.global("tostring")

local RESERVED_CONTEXT_KEYS = {
    parent = true,
    root = true,
    template = true,
    output = true
}

local function _nonempty_string(value)
    return type(value) == "string" and #value > 0
end

local function _resolve(base_dir, filepath)
    if not _nonempty_string(filepath) then
        raise("xdtc.generator: expected a non-empty path string")
    end
    if path.is_absolute(filepath) then
        return path.normalize(path.absolute(filepath))
    end
    return path.normalize(path.absolute(path.join(base_dir, filepath)))
end

local function _comparable(filepath)
    local value = path.normalize(filepath)
    if is_host("windows") then
        return value:lower()
    end
    return value
end

local function _slash(filepath)
    return filepath:gsub("\\", "/")
end

local function _dirname_before_wildcard(absolute_pattern)
    local normalized = _slash(path.normalize(absolute_pattern))
    local wildcard_pos = normalized:find("[*?]")
    if not wildcard_pos then
        return path.directory(absolute_pattern), path.filename(absolute_pattern)
    end

    local prefix = normalized:sub(1, wildcard_pos - 1)
    local slash_pos = prefix:match("^.*()/")
    if not slash_pos then
        return ".", normalized
    end

    local root = normalized:sub(1, slash_pos - 1)
    if root == "" then
        root = "/"
    end
    local relative_pattern = normalized:sub(slash_pos + 1)
    return path.normalize(root), relative_pattern
end

local function _relative_from_root(filepath, root)
    local f = _slash(path.normalize(filepath))
    local r = _slash(path.normalize(root)):gsub("/+$", "")
    if f == r then
        return ""
    end
    local prefix = r .. "/"
    if f:sub(1, #prefix) == prefix then
        return f:sub(#prefix + 1)
    end
    return path.filename(f)
end

local function _expand_pattern(base_dir, file_pattern)
    local absolute_pattern = _resolve(base_dir, file_pattern)
    if not pattern.has_wildcards(file_pattern) and not pattern.has_wildcards(absolute_pattern) then
        if os.isfile(absolute_pattern) then
            return {absolute_pattern}
        end
        return {}
    end

    local search_root, relative_pattern = _dirname_before_wildcard(absolute_pattern)
    if not os.isdir(search_root) then
        return {}
    end

    local candidates = os.files(path.join(search_root, "**"))
    local result = {}
    for _, filepath in ipairs(candidates) do
        local relative = _relative_from_root(filepath, search_root)
        if pattern.match_path(relative, relative_pattern) then
            result[#result + 1] = path.normalize(path.absolute(filepath))
        end
    end
    _table.sort(result)
    return result
end

function discover(base_dir, file_patterns)
    if type(file_patterns) ~= "table" or #file_patterns == 0 then
        raise("xdtc.generator: task.files must be a non-empty array")
    end

    local files = {}
    local seen = {}
    for index, file_pattern in ipairs(file_patterns) do
        if not _nonempty_string(file_pattern) then
            raise("xdtc.generator: task.files[%d] must be a non-empty string", index)
        end
        for _, filepath in ipairs(_expand_pattern(base_dir, file_pattern)) do
            local key = _comparable(filepath)
            if not seen[key] then
                seen[key] = true
                files[#files + 1] = filepath
            end
        end
    end
    return files
end

local function _context(entry, root, template_path, output_path)
    local context = {}
    for key, value in _pairs(entry.node) do
        if not RESERVED_CONTEXT_KEYS[key] then
            context[key] = value
        end
    end

    -- System-generated context always wins over same-named data fields.
    context.parent = entry.parent
    context.root = root
    context.template = {
        name = path.filename(template_path),
        path = template_path
    }
    context.output = {
        path = output_path
    }
    return context
end

local function _trim_fragment(text)
    return (text:gsub("[\r\n]+$", ""))
end

local function _replace_all_plain(text, needle, replacement)
    local parts = {}
    local offset = 1
    local count = 0

    while true do
        local first, last = text:find(needle, offset, true)
        if not first then
            parts[#parts + 1] = text:sub(offset)
            break
        end
        parts[#parts + 1] = text:sub(offset, first - 1)
        parts[#parts + 1] = replacement
        offset = last + 1
        count = count + 1
    end

    return _table.concat(parts), count
end

local function _apply_input_template(content, input_template)
    if input_template == nil or not os.isfile(input_template) then
        return content, false
    end

    local wrapper = io.readfile(input_template)
    if wrapper == nil then
        raise("xdtc.generator: failed to read input_template: %s", input_template)
    end

    local wrapped, count = _replace_all_plain(wrapper, "{{.}}", content)
    if count == 0 then
        raise("xdtc.generator: input_template must contain {{.}} placeholder: %s", input_template)
    end
    return wrapped, true
end

function matches(entry, template_name)
    return entry.node.enable == true
       and type(entry.node.match) == "string"
       and #entry.node.match > 0
       and pattern.match_segment(template_name, entry.node.match)
end

function render_task(root, entries, template_files, output_file, opt)
    opt = opt or {}
    local fragments = {}
    local debug_entries = {}

    for _, template_path in ipairs(template_files) do
        local template_name = path.filename(template_path)
        local matched = {}
        for _, entry in ipairs(entries) do
            if matches(entry, template_name) then
                matched[#matched + 1] = entry
            end
        end

        local names = {}
        local objects = debug_output.array({})
        for _, entry in ipairs(matched) do
            names[#names + 1] = entry.path
            objects[#objects + 1] = debug_output.clone(entry.node)
        end
        debug_entries[#debug_entries + 1] = {
            -- Keep the original v0.3 debug fields for compatibility.
            template = template_path,
            matched_paths = names,
            -- DTC-compatible debug fields.
            templatePath = template_path,
            matchedObjects = objects
        }

        local compile_opt = {
            escape = opt.escape == true,
            cache = opt.cache ~= false
        }
        local renderer = template_engine.compile_file(template_path, compile_opt)

        for _, entry in ipairs(matched) do
            local ok, rendered = _pcall(renderer, _context(entry, root, template_path, output_file))
            if not ok then
                raise("xdtc.generator: template render failed for %s at data path %s: %s",
                      template_path, entry.path, _tostring(rendered))
            end
            fragments[#fragments + 1] = _trim_fragment(rendered)
        end
    end

    return {
        content = _table.concat(fragments, "\n"),
        debug = debug_entries
    }
end

local function _ensure_parent(filepath)
    local dir = path.directory(filepath)
    if dir and #dir > 0 and not os.isdir(dir) then
        os.mkdir(dir)
    end
end

local function _validate_tasks(base_dir, tasks)
    if type(tasks) ~= "table" or #tasks == 0 then
        raise("xdtc.generator: tasks/tpl must be a non-empty array")
    end

    local outputs = {}
    local normalized = {}
    for index, task in ipairs(tasks) do
        if not kind.is_object(task) then
            raise("xdtc.generator: task[%d] must be an object", index)
        end
        if type(task.files) ~= "table" or #task.files == 0 then
            raise("xdtc.generator: task[%d].files must be a non-empty array", index)
        end
        if not _nonempty_string(task.out) then
            raise("xdtc.generator: task[%d].out must be a non-empty string", index)
        end

        local output_file = _resolve(base_dir, task.out)
        local key = _comparable(output_file)
        if outputs[key] then
            raise("xdtc.generator: duplicate output file is not allowed: %s", output_file)
        end
        outputs[key] = true
        if task.escape ~= nil and type(task.escape) ~= "boolean" then
            raise("xdtc.generator: task[%d].escape must be a boolean when provided", index)
        end
        if task.input_template ~= nil and not _nonempty_string(task.input_template) then
            raise("xdtc.generator: task[%d].input_template must be a non-empty string when provided", index)
        end

        local input_template
        if task.input_template ~= nil then
            input_template = _resolve(base_dir, task.input_template)
        end

        normalized[#normalized + 1] = {
            files = task.files,
            output_file = output_file,
            input_template = input_template,
            escape = task.escape
        }
    end
    return normalized
end

-- Generate one or more DTC-style template tasks from an already-built root tree.
-- tasks format: { {files = {"tpl/*.tpl"}, input_template = "wrapper.in", out = "out/generated.sv"}, ... }
function generate(root, tasks, opt)
    opt = opt or {}
    if not kind.is_object(root) then
        raise("xdtc.generator: root must be an object")
    end

    if opt.metadata ~= false then
        metadata.apply(root)
    end

    local base_dir = path.normalize(path.absolute(opt.base_dir or os.workingdir()))
    local normalized_tasks = _validate_tasks(base_dir, tasks)
    local entries = query.collect(root)
    local results = {}

    for index, task in ipairs(normalized_tasks) do
        local files = discover(base_dir, task.files)
        local effective_escape = opt.escape
        if task.escape ~= nil then
            effective_escape = task.escape
        end
        local rendered = render_task(root, entries, files, task.output_file, {
            escape = effective_escape,
            cache = opt.cache
        })

        local final_content, input_template_applied = _apply_input_template(
            rendered.content, task.input_template)

        if opt.write ~= false then
            _ensure_parent(task.output_file)
            io.writefile(task.output_file, final_content)
        end

        results[#results + 1] = {
            index = index,
            output = task.output_file,
            templates = files,
            input_template = task.input_template,
            input_template_applied = input_template_applied,
            content = final_content,
            debug = rendered.debug
        }
    end

    return results
end
