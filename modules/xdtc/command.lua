-- 命令分发与数据／模板实现分离；具体动作由消费工程注册。
local xdtc = import("xdtc")
local action = import("xdtc.action")
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
    for name, declaration in raw_pairs(actions) do
        if reserved[name] then
            raise("xdtc: action cannot override reserved command: %s", name)
        end
        action.validate(name, declaration)
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
    local script, forwarded, data
    if command == "run" then
        if #args == 0 then
            raise("xdtc: run requires a script path")
        end
        script, forwarded = args[1], table.slice(args, 2)
        data = xdtc.load_data(config)
    else
        local declaration = actions[command]
        if not declaration then
            raise("xdtc: unknown action: %s", command)
        end
        script, forwarded = declaration.script, args
        data = xdtc.select_action(config, command, xdtc.load_data(config))
    end
    return xdtc.execute(script, data, forwarded, { base_dir = config.base_dir })
end
