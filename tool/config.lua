local json = require "json"

local Utils = require "SelenScript.utils"


---@class SSSWTool.Config
---@field _validate fun(config:SSSWTool.Config, data:table)?
local Config = {}
Config.__index = Config


---@param default table?
---@param validate fun(config:SSSWTool.Config, data:table)?
function Config.new(default, validate)
	local self = setmetatable({}, Config)
	self._validate = validate
	self.data = default and Utils.shallowcopy(default) or {}
	if validate then
		local ok, err = pcall(validate, self, self.data)
		if not ok then
			error(("Failed to validate config '%s'\n%s"):format("<DEFAULT>", err:gsub(".-:.-: ", "")))
		end
	end
	return self
end

--- Siliently ignores file not found errors and does not reset config.
---@param path string
function Config:read(path)
	local f, msg, code = io.open(path, "r")
	if not f then
		-- If file not found, then we just keep the config we have (should be default)
		if code == 2 then
			return true
		end
		return false, msg, code
	end
	local src, err = f:read("*a")
	f:close()
	if err then
		return false, ("Failed to read config '%s'\n%s"):format(path, err)
	end
	local ok, data = pcall(json.decode, src)
	if not ok then
		return false, ("Failed to parse config '%s'\n%s"):format(path, data:gsub(".-:.-: ", ""))
	end
	if self._validate then
		local ok, err = pcall(self._validate, self, data)
		if not ok then
			return false, ("Failed to validate config '%s'\n%s"):format(path, err:gsub(".-:.-: ", ""))
		end
	end
	self.data = data
	return true
end

--- Saves the config data to the given path.
---@param path string
function Config:save(path)
	local f, msg, code = io.open(path, "w")
	if not f then
		return false, ("Failed to write config '%s'\n%s"):format(path, msg)
	end
	f:write(json.encode(self.data))
	return true
end


return Config
