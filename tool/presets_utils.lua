local lfs = require "lfs"
local AvPath = require "avpath"

local Utils = require "SelenScript.utils"


local PRESETS_PATH = AvPath.join{require "tool.tool_path", "presets"}

local PresetsUtils = {}
PresetsUtils.PRESETS_PATH = PRESETS_PATH


---@param path string
function PresetsUtils.exists(path)
	path = AvPath.join{PRESETS_PATH, path}
	return AvPath.exists(path)
end


---@param path string
---@param binary boolean?
function PresetsUtils.read_file(path, binary)
	path = AvPath.join{PRESETS_PATH, path}
	return Utils.readFile(path, binary)
end

---@param path string
---@param data string
---@param binary boolean?
function PresetsUtils.write_file(path, data, binary)
	path = AvPath.join{PRESETS_PATH, path}
	lfs.mkdir(AvPath.base(path))
	Utils.writeFile(path, data, binary)
end


return PresetsUtils