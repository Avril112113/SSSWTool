require "tool.cli_print"

---@alias SSWTool.CLI.Action {help:string?,usage:string?,handler:fun(args:string[],pos:integer):integer?}

---@class SSWTool.CLI
local CLI = {}

---@type table<string,SSWTool.CLI.Action>
CLI.actions = {
	help = require("tool.cli.help")(CLI),
	build = require("tool.cli.build")(CLI),
}

---@param args string[]
function CLI.process(args)
	if #args <= 0 then
		CLI.actions.help.handler(args, 1)
		return -1
	end
	local action = CLI.actions[args[1]]
	if action == nil then
		print(("Invalid action '%s'.\nTry 'help' for available actions."):format(args[1]))
		return -1
	end
	return action.handler(args, 2)
end

return CLI
