rule("codegen")
on_prepare(function(target)
	import("core.package.addon")
	local generator = import("@self.generator")
	local name = "@addon/" .. addon.owner() .. "/codegen"
	local config = target:extraconf("rules", name, "config") or "xdtc.lua"
	local result = generator.run_file(config, {
		base_dir = os.projectdir(),
		overrides = { write = false },
	})
	-- 每次构建检查数据和模板，只有内容变化才写入，保留正常增量编译。
	for _, output in ipairs(result.outputs) do
		if not os.isfile(output.output) or io.readfile(output.output) ~= output.content then
			os.mkdir(path.directory(output.output))
			io.writefile(output.output, output.content)
		end
	end
end)
rule_end()
