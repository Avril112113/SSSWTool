local AVPath = require "avpath"
local Utils = require "SelenScript.utils"
local lfs = require "lfs"


---@param path string
local function dir_empty(path)
	local f, s = lfs.dir(path)
	---@diagnostic disable-next-line: redundant-parameter
	return f(s) == nil
end

local PRESETS = {
	addon = require "tool.presets.new_addon",
}


---@param CLI SSWTool.CLI
return function(CLI)
	---@type SSWTool.CLI.Action
	return {
		usage = "addon <path>",
		---@param args string[]
		---@param pos integer
		handler = function(args, pos)
			local project_type = args[pos]
			pos = pos + 1
			if project_type == nil then
				print("Missing required argument #1, project type")
				return -1
			elseif project_type ~= "addon" then
				print("Invalid project type, only \"addon\" is supported currently.")
				return -1
			end
			local path = args[pos] or ""
			pos = pos + 1
			if #path <= 0 then
				print("Missing required argument #2, path")
				return -1
			end
			if #(args[pos] or "") > 0 then
				print(("Excess arguments '%s'"):format(table.concat(args, " ", pos)))
				return -1
			end
			path = AVPath.abs(path)
			if AVPath.exists(path) and not dir_empty(path) then
				print(("Directory is not empty \"%s\""):format(path))
				print("Would you like to continue anyway?")
				io.write("y/n ")
				if io.stdin:read("*l") ~= "y" then
					print("Aborted")
					return -1
				end
			elseif not AVPath.exists(AVPath.base(path)) then
				print(("Directory does not exist \"%s\""):format(AVPath.base(path)))
				return -1
			end
			local name = AVPath.name(path)
			print_info(("Creating new %s project '%s' at \"%s\""):format(project_type, name, path))
			if not AVPath.exists(path) then
				lfs.mkdir(path)
			end
			for filepath, contents in pairs(PRESETS[project_type](name)) do
				local full_filepath = AVPath.join{path, filepath}
				lfs.mkdir(AVPath.base(full_filepath))
				Utils.writeFile(full_filepath, contents)
			end
		end,
	}
end
