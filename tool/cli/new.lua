local AVPath = require "avpath"
local Utils = require "SelenScript.utils"
local lfs = require "lfs"


---@param path string
local function dir_empty(path)
	local f, s = lfs.dir(path)
	---@diagnostic disable-next-line: redundant-parameter
	return f(s) == nil
end

---@class SSSWTool.NewPreset.File
---@field contents string
---@field replace boolean?

---@class SSSWTool.NewPreset
---@field expect_empty_path boolean
---@field files table<string,SSSWTool.NewPreset.File>

local PRESETS = {
	addon = require "tool.presets.new_addon",
	buildactions = require "tool.presets.new_buildactions",
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
			if project_type == nil or PRESETS[project_type] == nil then
				print("Invalid argument #1, expected one of the following:")
				for name, _ in pairs(PRESETS) do
					print(("- %s"):format(name))
				end
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
			local name = AVPath.name(path)
			local preset = PRESETS[project_type](name)
			if not AVPath.exists(AVPath.base(path)) then
				print(("Directory does not exist \"%s\""):format(AVPath.base(path)))
				return -1
			end
			print_info(("Creating %s files for '%s' at \"%s\""):format(project_type, name, path))
			if not AVPath.exists(path) then
				lfs.mkdir(path)
			end
			for filepath, data in pairs(preset.files) do
				local full_filepath = AVPath.join{path, filepath}
				local already_exists = AVPath.exists(full_filepath)
				if already_exists and data.replace ~= true then
					print_warn(("Skipped '%s' as it already exists."):format(filepath))
				else
					if already_exists then
						print_info(("Replacing '%s'."):format(filepath))
					else
						print_info(("Writing '%s'."):format(filepath))
					end
					lfs.mkdir(AVPath.base(full_filepath))
					Utils.writeFile(full_filepath, data.contents)
				end
			end
		end,
	}
end
