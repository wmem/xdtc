-- 命令分发与数据／模板实现分离；具体动作由消费工程注册。
local xdtc = import("xdtc")
local reserved = { gen = true, data = true, run = true }
local raw_pairs = debug.global("pairs")

function run(config_path, command, args, opt)
    opt = opt or {}
    args = args or {}
    if type(command) ~= "string" or command == "" then
        raise("xdtc: expected gen, data, run or a registered action")
    end
    local config = xdtc.load_config(config_path or "xdtc.lua", { base_dir = opt.base_dir })
    local actions = config.actions or {}
    if type(actions) ~= "table" then
        raise("xdtc: config.actions must be a table")
    end
    for name, script in raw_pairs(actions) do
        if reserved[name] then
            raise("xdtc: action cannot override reserved command: %s", name)
        end
        if type(name) ~= "string" or name == "" or type(script) ~= "string" or script == "" then
            raise("xdtc: actions must map names to script paths")
        end
    end
    if command == "gen" or command == "data" then
        if #args ~= 0 then
            raise("xdtc: %s does not accept positional arguments", command)
        end
        if command == "gen" then
            return xdtc.run(config)
        end
        local data = xdtc.load_data(config)
        io.write("return " .. string.serialize(data, { orderkeys = true }) .. "\n")
        return data
    end
    local script, forwarded
    if command == "run" then
        if #args == 0 then
            raise("xdtc: run requires a script path")
        end
        script, forwarded = args[1], table.slice(args, 2)
    else
        script, forwarded = actions[command], args
        if not script then
            raise("xdtc: unknown action: %s", command)
        end
    end
    return xdtc.execute(script, xdtc.load_data(config), forwarded, { base_dir = config.base_dir })
end
