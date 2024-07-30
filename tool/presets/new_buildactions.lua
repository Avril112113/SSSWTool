local PresetsUtils = require "tool.presets_utils"


return function(name)
	---@type SSSWTool.NewPreset
	return {
		expect_empty_path = false,
		files = {
			["_buildactions/init.lua"] = {contents=PresetsUtils.read_file("_buildactions/init.lua"):gsub("---@class SSSWTool%.BuildActions\n", "---@class MyBuildActions : SSSWTool.BuildActions\n")},
		},
	}
end
