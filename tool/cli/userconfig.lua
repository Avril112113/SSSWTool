local AvPath = require "avpath"

local Utils = require "SelenScript.utils"

local UserConfig = require "tool.userconfig"


local CONFIG_SETTERS = {
	["intellisense_autoupdate"] = {
		value_usage = "true|false",
		---@param args string[]
		---@param pos integer
		handler=function(args, pos)
			local value
			if args[pos] == "true" then
				value = true
			elseif args[pos] == "false" then
				value = false
			else
				print("Invalid value, expected 'true' or 'false'")
				return -1
			end
			UserConfig.intellisense_autoupdate_allowed(value)
			print(("Automatic updates are now %s"):format(value and "ENABLED" or "DISABLED"))
			return 0
		end,
	},
	["buildations_whitelist_add"] = {
		value_usage = "<path>",
		---@param args string[]
		---@param pos integer
		handler=function(args, pos)
			local path = args[pos]
			if not AvPath.exists(path) then
				print(("Path dose not exist '%s'"):format(path))
				return -1
			end
			UserConfig.buildactions_whitelist_add(path)
			print(("Whitelisting build actions for '%s'"):format(path))
			print(("Note: there is no command to remove whitelisted paths, manually edit '%s' to do so."):format(UserConfig.CONFIG_PATH))
			return 0
		end,
	},
}


---@param CLI SSWTool.CLI
return function(CLI)
	---@type SSWTool.CLI.Action
	return {
		usage = "<field> <value>",
		---@param args string[]
		---@param pos integer
		handler = function(args, pos)
			if #args < pos then
				print("Possible config options:")
				for field, handler in Utils.sorted_pairs(CONFIG_SETTERS) do
					print(("- %s %s"):format(field, handler.value_usage))
				end
				return 0
			elseif CONFIG_SETTERS[args[pos]] == nil then
				print(("Invalid config field '%s'"):format(args[pos]))
				return -1
			else
				local handler = CONFIG_SETTERS[args[pos]]
				pos = pos + 1
				return handler.handler(args, pos)
			end
		end,
	}
end
