local Utils = require "SelenScript.utils"
local AvPath = require "avpath"


---@diagnostic disable-next-line: param-type-mismatch
local presets_path = AvPath.join{AvPath.base(package.searchpath("tool.init", package.path)), "presets"}

local PresetsUtils = {}


---@param path string
---@param binary boolean?
function PresetsUtils.read_file(path, binary)
	return Utils.readFile(AvPath.join{presets_path, path}, binary)
end


return PresetsUtils