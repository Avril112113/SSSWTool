local Utils = require "SelenScript.utils"
local AvPath = require "avpath"


local presets_path = AvPath.join{require "tool.tool_path", "presets"}

local PresetsUtils = {}


---@param path string
---@param binary boolean?
function PresetsUtils.read_file(path, binary)
	return Utils.readFile(AvPath.join{presets_path, path}, binary)
end


return PresetsUtils