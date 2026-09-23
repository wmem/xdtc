-- Xmake project integration helpers for xdtc.
-- Keeps the build-system glue separate from the data/template core.

local xdtc = import("xdtc")

local _ran = {}

local function _resolve(base_dir, filepath)
    base_dir = path.normalize(path.absolute(base_dir or os.projectdir()))
    filepath = filepath or "xdtc.lua"
    if not path.is_absolute(filepath) then
        filepath = path.join(base_dir, filepath)
    end
    return path.normalize(path.absolute(filepath)), base_dir
end

local function _key(filepath)
    if is_host("windows") then
        return filepath:lower()
    end
    return filepath
end

-- Run one xdtc config file from an Xmake project.
--
-- opt.once     : default true; execute the same resolved config only once in
--                the current Xmake process. Useful when several targets share
--                the same code-generation config.
-- opt.optional : default false; if true, a missing config file is ignored.
-- opt.base_dir : base used to resolve config_path and as xdtc.run_file base.
-- opt.overrides: shallow top-level overrides passed to xdtc.run_file().
function run(config_path, opt)
    opt = opt or {}
    local filepath, base_dir = _resolve(opt.base_dir, config_path)

    if not os.isfile(filepath) then
        if opt.optional == true then
            return nil
        end
        raise("xdtc.integration: config file not found: %s", filepath)
    end

    local once = opt.once ~= false
    local cache_key = _key(filepath)
    if once and _ran[cache_key] ~= nil then
        return _ran[cache_key]
    end

    local result = xdtc.run_file(filepath, {
        base_dir = base_dir,
        overrides = opt.overrides
    })

    if once then
        _ran[cache_key] = result
    end
    return result
end

-- Primarily useful for tests or unusual long-lived Xmake scripts.
function reset()
    _ran = {}
end
