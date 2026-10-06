local projectdir = path.absolute(path.join(os.scriptdir(), ".."))
local suites = {
    "run.lua",
    "template_run.lua",
    "generator_run.lua",
    "dtc_compat_run.lua",
    "config_run.lua",
    "integration_run.lua",
    "command_run.lua",
}

for _, suite in ipairs(suites) do
    os.execv(os.programfile(), { "lua", path.join(projectdir, "tests", suite), "--root" }, {
        envs = { XMAKE_ROOT = os.getenv("XMAKE_ROOT") or "y" },
    })
end

cprint("${bright green}all xdtc test suites passed${clear}")
