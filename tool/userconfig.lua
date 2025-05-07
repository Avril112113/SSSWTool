local AvPath = require "avpath"
local jit = require "jit"

local Config = require "tool.config"

local CONFIG_PATH
if jit.os == "Windows" then
	CONFIG_PATH = AvPath.join{os.getenv("APPDATA"), ".ssswtool.json"}
elseif jit.os == "Linux" then
	CONFIG_PATH = AvPath.join{os.getenv("HOME"), ".ssswtool.json"}
else
	error("Unknown OS for user config path " .. jit.os)
end

local UserConfig = {}
UserConfig.CONFIG_PATH = CONFIG_PATH
UserConfig._config = Config.new()
UserConfig._config:read(CONFIG_PATH)

---@param set boolean?
---@return boolean?
function UserConfig.intellisense_autoupdate_allowed(set)
	local data = UserConfig._config.data
	if set ~= nil then
		data["intellisense_autoupdate_allowed"] = not not set
		UserConfig._config:save(CONFIG_PATH)
	end
	return data["intellisense_autoupdate_allowed"]
end


---@param path string
function UserConfig.buildactions_whitelist_add(path)
	path = AvPath.abs(path)
	local data = UserConfig._config.data
	data["buildactions_whitelist"] = data["buildactions_whitelist"] or {}
	if type(data["buildactions_whitelist"]) ~= "table" then
		print_error("UserConfig error: 'buildactions_whitelist' is not a table, it has been reset.")
		data["buildactions_whitelist"] = {}
	end
	table.insert(data["buildactions_whitelist"], path)
	UserConfig._config:save(CONFIG_PATH)
end

---@param path string
function UserConfig.buildactions_whitelist_check(path)
	path = AvPath.abs(path)
	local data = UserConfig._config.data
	data["buildactions_whitelist"] = data["buildactions_whitelist"] or {}
	if type(data["buildactions_whitelist"]) ~= "table" then
		print_error("UserConfig error: 'buildactions_whitelist' is not a table, it has been reset.")
		data["buildactions_whitelist"] = {}
	end
	for _, whitelisted_path in pairs(data["buildactions_whitelist"]) do
		if AvPath.common{whitelisted_path, path}:sub(1, #whitelisted_path) == whitelisted_path then
			return true
		end
	end
	return false
end


return UserConfig
