local AvPath = require "avpath"

local PresetsUtils = require "tool.presets_utils"
local TOOL_PATH = require "tool.tool_path"
local SELENSCRIPT_PATH = require "tool.selenscript_path"


return function(name)
	print(("For build actions, consider adding the following to '.vscode/settings.json' under `Lua.workspace.library`:\n    \"%s\"\n    \"%s\""):format(AvPath.norm(TOOL_PATH), AvPath.norm(SELENSCRIPT_PATH)))
	---@type SSSWTool.NewPreset
	return {
		expect_empty_path = false,
		files = {
			["_buildactions/init.lua"] = {contents=PresetsUtils.read_file("_buildactions/init.lua"):gsub("---@class SSSWTool%.BuildActions\n", "---@class MyBuildActions : SSSWTool.BuildActions\n")},
		},
	}
end
