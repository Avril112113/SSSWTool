local MultiProject = require "tool.multi_project"


---@param CLI SSWTool.CLI
return function(CLI)
	---@type SSWTool.CLI.Action
	return {
		help = "Build a SW addon project.",
		usage = "[path=./]",
		---@param args string[]
		---@param pos integer
		handler = function(args, pos)
			local addon_dir = args[pos] or "./"
			pos = pos + 1
			local multi_project, err = MultiProject.new(addon_dir .. "/ssswtool.json")
			if not multi_project or err then
				print_error(err or "FAIL project ~= nil")
				return -1
			end
			multi_project:build()
			-- TODO: Check for any projects that failed to build and return -1 if so.
			return 0
		end,
	}
end