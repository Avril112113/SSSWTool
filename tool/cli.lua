require "tool.cli_print"
local Build = require "tool.build"


local CLI = {}


---@alias SSWTool.CLI.Action {help:string?,usage:string?,handler:fun(args:string[],pos:integer):integer?}
---@type table<string,SSWTool.CLI.Action>
CLI.actions = {
	help = {
		usage = "[action]",
		---@param args string[]
		---@param pos integer
		handler = function(args, pos)
			---@param name string
			---@param action SSWTool.CLI.Action
			local function print_action(name, action)
				local usage_part = action.usage and " " .. action.usage or ""
				if action.help == nil or #action.help == 0 then
					print(("%s%s"):format(name, usage_part))
				elseif action.help:find("\n") then
					local indent = "    "
					print(("%s%s\n%s%s"):format(name, usage_part, indent, action.help:gsub("\n", "\n"..indent)))
				else
					print(("%s%s - %s"):format(name, usage_part, action.help))
				end
			end
			if args[pos] then
				local name = args[pos]
				-- pos = pos + 1
				local action = CLI.actions[name]
				if action == nil then
					print(("Action '%s' does not exist."):format(name))
					return -1
				end
				print_action(name, action)
				return 0
			else
				local names = {}
				for name, _ in pairs(CLI.actions) do
					table.insert(names, name)
				end
				table.sort(names)
				for _, name in ipairs(names) do
					local action = CLI.actions[name]
					if action.help or action.usage then
						print_action(name, action)
					end
				end
			end
		end,
	},
	build = {
		help = "Build a SW addon project.",
		usage = "[path=./]",
		---@param args string[]
		---@param pos integer
		handler = function(args, pos)
			local addon_dir = args[pos] or "./"
			pos = pos + 1
			Build.build(addon_dir)
		end,
	},
}


---@param args string[]
function CLI.process(args)
	if #args <= 0 then
		CLI.actions.help.handler(args, 1)
		return -1
	end
	local action = CLI.actions[args[1]]
	if action == nil then
		print(("Action '%s' does not exist."):format(args[1]))
		return -1
	end
	return action.handler(args, 2)
end


return CLI
