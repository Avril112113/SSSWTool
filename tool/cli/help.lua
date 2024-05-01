---@param CLI SSWTool.CLI
return function(CLI)
	---@type SSWTool.CLI.Action
	return {
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
	}
end