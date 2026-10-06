local kind = import("xdtc.kind")
local merge = import("xdtc.merge")
local pathops = import("xdtc.pathops")
local metadata = import("xdtc.metadata")
local generator = import("xdtc.generator")
local debug_output = import("xdtc.debug_output")
local action = import("xdtc.action")
local selection = import("xdtc.selection")
local sandbox = import("core.sandbox.sandbox")

local _raw_loadfile = debug.global("loadfile")
local _raw_pcall = debug.global("pcall")
local _raw_pairs = debug.global("pairs")
local _raw_ipairs = debug.global("ipairs")
local _setfenv = debug.setfenv

local VERSION = "0.8.0"

local function _normalize_file(filepath, base_dir)
    if type(filepath) ~= "string" or #filepath == 0 then
        raise("xdtc: expected a non-empty file path")
    end
    if not path.is_absolute(filepath) then
        filepath = path.join(base_dir or os.workingdir(), filepath)
    end
    return path.normalize(path.absolute(filepath))
end

local function _comparable_path(filepath)
    filepath = path.normalize(filepath)
    if is_host("windows") then
        return filepath:lower()
    end
    return filepath
end

local function _copy_table(source)
    local result = {}
    for key, value in _raw_pairs(source) do
        result[key] = value
    end
    return result
end

local function _new_state()
    return {
        root = {},
        loaded_files = {},
        loading_stack = {},
        file_stack = {},
    }
end

local _load_module

local function _make_environment(state)
    local env = _copy_table(sandbox.builtin_modules())

    -- Keep data files declarative. Dependency loading is controlled by xdtc.include().
    env.import = nil
    env.debug = nil

    -- Use normal Lua iteration for arbitrary user data tables. Xmake's enhanced
    -- pairs()/ipairs() treat fields named "pairs"/"ipairs" as iterator methods.
    env.pairs = _raw_pairs
    env.ipairs = _raw_ipairs

    -- os.scriptdir() must refer to the current data file rather than xdtc.lua.
    local env_os = _copy_table(env.os)
    env_os.scriptdir = function()
        local current_file = state.file_stack[#state.file_stack]
        return current_file and path.directory(current_file) or os.workingdir()
    end
    env.os = env_os

    env.include = function(target_path)
        if type(target_path) ~= "string" or #target_path == 0 then
            raise("xdtc: include() expects a non-empty path string")
        end
        local current_file = state.file_stack[#state.file_stack]
        if not current_file then
            raise("xdtc: include() can only be used while a data file is being evaluated")
        end
        local resolved = _normalize_file(target_path, path.directory(current_file))
        _load_module(resolved, state)
    end

    env.get = function(dotted_path)
        return pathops.get(state.root, dotted_path)
    end

    env.remove = function(dotted_path)
        pathops.remove(state.root, dotted_path)
    end

    env.replace = function(dotted_path, value)
        pathops.replace(state.root, dotted_path, value)
    end

    env.update = function(dotted_path, patch)
        pathops.update(state.root, dotted_path, patch)
    end

    env.update_root = function(patch)
        if not kind.is_object(patch) then
            raise("xdtc: update_root() expects an object patch")
        end
        merge.merge_into(state.root, patch)
    end

    -- Compatibility spelling with the original JavaScript DTC API.
    env.updateRoot = env.update_root

    env.get_root = function()
        return state.root
    end

    return env
end

_load_module = function(filepath, state)
    filepath = _normalize_file(filepath)
    local comparable = _comparable_path(filepath)

    if state.loaded_files[comparable] then
        return
    end

    local cycle_start
    for index, loading in ipairs(state.loading_stack) do
        if loading == comparable then
            cycle_start = index
            break
        end
    end
    if cycle_start then
        local cycle = {}
        for i = cycle_start, #state.loading_stack do
            table.insert(cycle, state.loading_stack[i])
        end
        table.insert(cycle, comparable)
        raise("xdtc: circular include detected: %s", table.concat(cycle, " -> "))
    end

    if not os.isfile(filepath) then
        raise("xdtc: data file not found: %s", filepath)
    end

    table.insert(state.loading_stack, comparable)
    table.insert(state.file_stack, filepath)

    local function _leave()
        table.remove(state.file_stack)
        table.remove(state.loading_stack)
    end

    local script, load_errors = _raw_loadfile(filepath, "bt", { nocache = true })
    if not script then
        _leave()
        raise("xdtc: failed to load data file %s: %s", filepath, load_errors)
    end

    _setfenv(script, _make_environment(state))
    local ok, exported = _raw_pcall(script)
    if not ok then
        _leave()
        raise("xdtc: failed to evaluate data file %s: %s", filepath, tostring(exported))
    end

    if exported ~= nil then
        if not kind.is_object(exported) then
            _leave()
            raise("xdtc: data file must return an object or nil: %s", filepath)
        end
        local merge_ok, merge_errors = _raw_pcall(function()
            merge.merge_into(state.root, exported)
        end)
        if not merge_ok then
            _leave()
            raise("xdtc: failed to merge data file %s: %s", filepath, tostring(merge_errors))
        end
    end

    state.loaded_files[comparable] = true
    _leave()
end

-- Build a root data tree from an entry Lua file.
-- opt.metadata defaults to true, matching the original DTC behavior.
function load(entry_path, opt)
    opt = opt or {}
    local state = _new_state()
    local entry = _normalize_file(entry_path)
    _load_module(entry, state)

    if opt.on_before_metadata ~= nil then
        if type(opt.on_before_metadata) ~= "function" then
            raise("xdtc: load().on_before_metadata must be a function when provided")
        end
        opt.on_before_metadata(debug_output.clone(state.root))
    end

    if opt.metadata ~= false then
        metadata.apply(state.root)
    end
    return state.root
end

function version()
    return VERSION
end

-- Load a standalone xdtc configuration file.
-- The file is ordinary Lua executed in an Xmake sandbox and must return a table.
function load_config(config_path, opt)
    opt = opt or {}
    local base_dir = opt.base_dir or os.workingdir()
    local filepath = _normalize_file(config_path or "xdtc.lua", base_dir)

    if not os.isfile(filepath) then
        raise("xdtc: config file not found: %s", filepath)
    end

    local env = _copy_table(sandbox.builtin_modules())
    env.debug = nil
    env.pairs = _raw_pairs
    env.ipairs = _raw_ipairs

    -- Make os.scriptdir() useful inside xdtc.lua even though the file is
    -- evaluated by xdtc rather than by Xmake's project interpreter.
    local env_os = _copy_table(env.os)
    env_os.scriptdir = function()
        return path.directory(filepath)
    end
    env.os = env_os

    local script, load_errors = _raw_loadfile(filepath, "bt", { nocache = true })
    if not script then
        raise("xdtc: failed to load config file %s: %s", filepath, load_errors)
    end

    _setfenv(script, env)
    local ok, config = _raw_pcall(script)
    if not ok then
        raise("xdtc: failed to evaluate config file %s: %s", filepath, tostring(config))
    end
    if not kind.is_object(config) then
        raise("xdtc: config file must return an object: %s", filepath)
    end

    -- 查找入口的目录与配置内部路径的目录分开；内部默认相对配置文件。
    config.base_dir =
        _normalize_file(config.base_dir or path.directory(filepath), path.directory(filepath))
    return config, filepath
end

-- Run xdtc from a standalone configuration file.
-- opt.base_dir 只控制配置入口查找；内部路径默认相对配置文件。
-- opt.overrides 可浅层覆盖配置，不修改原文件。
function run_file(config_path, opt)
    opt = opt or {}
    local loaded, filepath = load_config(config_path or "xdtc.lua", {
        base_dir = opt.base_dir,
    })

    local config = _copy_table(loaded)
    if opt.overrides ~= nil then
        if not kind.is_object(opt.overrides) then
            raise("xdtc: run_file().overrides must be an object when provided")
        end
        for key, value in _raw_pairs(opt.overrides) do
            config[key] = value
        end
    end

    config.base_dir = _normalize_file(config.base_dir, path.directory(filepath))

    return run(config)
end

-- 展开任务配置的数据入口，不添加模板元数据，也不执行生成任务。
function load_data(config)
    if type(config) ~= "table" or type(config.data) ~= "string" or config.data == "" then
        raise("xdtc: config.data must be a non-empty string")
    end
    return load(_normalize_file(config.data, config.base_dir), { metadata = false })
end

-- 立即读取选定对象；配置域的 xdtc_config():select() 返回回调，由使用方延迟调用。
function read_config(config_path, selector, opt)
    local description = load_config(config_path, opt)
    local root = load_data(description)
    local data = selection.select(root, selector, "configuration")
    local directory = path.directory(_normalize_file(description.data, description.base_dir))
    return data, directory
end

-- 应用读取器和命令分发复用 action 的输入选择，不依赖 root 的布局。
function select_action(config, name, root)
    local selected = config.actions and config.actions[name]
    if not selected then
        raise("xdtc: unknown action: %s", tostring(name))
    end
    return action.select(root, selected, name)
end

-- 执行脚本接收调用方提供的数据；路径由调用入口解析。
function execute(script_path, data, args, opt)
    opt = opt or {}
    local filepath = _normalize_file(script_path, opt.base_dir)
    if not os.isfile(filepath) then
        raise("xdtc: script file not found: %s", filepath)
    end
    -- import 的模块缓存之外还有秒级文件缓存；先刷新编译结果。
    local chunk, errors = _raw_loadfile(filepath, "bt", { nocache = true })
    if not chunk then
        raise("xdtc: failed to load script %s: %s", filepath, errors)
    end
    local script = import(path.basename(filepath), {
        rootdir = path.directory(filepath),
        anonymous = true,
        nocache = true,
    })
    if type(script.main) ~= "function" then
        raise("xdtc: script must define main(config): %s", filepath)
    end
    return script.main(data, table.unpack(args or {}))
end

function build(entry_path, opt)
    return load(entry_path, opt)
end

-- Generate DTC-style template tasks from an already built root.
function generate(root, tasks, opt)
    return generator.generate(root, tasks, opt)
end

-- End-to-end DTC-style workflow.
-- config = {data = "data/root.lua", tpl = {{files = {...}, input_template = "...", out = "..."}}, base_dir = "..."}
function run(config)
    if type(config) ~= "table" then
        raise("xdtc: run() expects a config table")
    end
    if type(config.data) ~= "string" or #config.data == 0 then
        raise("xdtc: run().data must be a non-empty string")
    end
    if type(config.tpl) ~= "table" or #config.tpl == 0 then
        raise("xdtc: run().tpl must be a non-empty array")
    end

    local base_dir = path.normalize(path.absolute(config.base_dir or os.workingdir()))
    local data_entry = config.data
    if not path.is_absolute(data_entry) then
        data_entry = path.join(base_dir, data_entry)
    end

    local function _debug_path(snake_name, camel_name)
        local value = config[snake_name]
        if value == nil then
            value = config[camel_name]
        end
        if value == nil or value == "" then
            return nil
        end
        if type(value) ~= "string" then
            raise("xdtc: run().%s must be a string when provided", snake_name)
        end
        if path.is_absolute(value) then
            return path.normalize(path.absolute(value))
        end
        return path.normalize(path.absolute(path.join(base_dir, value)))
    end

    local debug_data_out = _debug_path("debug_data_out", "debugDataOut")
    local debug_match_out = _debug_path("debug_match_out", "debugMatchOut")
    local raw_root
    local root = load(data_entry, {
        metadata = config.metadata ~= false,
        on_before_metadata = function(snapshot)
            raw_root = snapshot
        end,
    })

    if debug_data_out then
        debug_output.write_json(debug_data_out, raw_root or {})
    end

    local outputs = generator.generate(root, config.tpl, {
        base_dir = base_dir,
        metadata = false,
        escape = config.escape,
        cache = config.cache,
        write = config.write,
    })

    local debug_match = debug_output.array({})
    for _, output in ipairs(outputs) do
        for _, entry in ipairs(output.debug or {}) do
            debug_match[#debug_match + 1] = {
                templatePath = entry.templatePath or entry.template,
                matchedObjects = entry.matchedObjects or {},
            }
        end
    end
    if debug_match_out then
        debug_output.write_json(debug_match_out, debug_match)
    end

    return {
        root = root,
        outputs = outputs,
        debug_data = raw_root,
        debug_match = debug_match,
    }
end
