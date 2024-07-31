local lfs = require "lfs"
local AVPath = require "avpath"

local Utils = require "SelenScript.utils"

local PresetsUtils = require "tool.presets_utils"


local SSSWTOOL_JSON_FMT = [[
{
	"name": "%s",
	"entrypoint": "script.lua",
	"src": ["."],
	"out": "{SW_SAVE}/data/missions/{NAME}/script.lua",
	"transformers": {
		"tracing": false
	}
}
]]

local SCRIPT = [[
--- Called when the script is initialized (whenever creating or loading a world.)
---@param is_world_create boolean Only returns true when the world is first created.
function onCreate(is_world_create)
	debug.log("Loaded")
end

--- Called every game tick
---@param game_ticks number the number of ticks since the last onTick call (normally 1, while sleeping 400.)
function onTick(game_ticks)
end

--- Called when the world is exited.
function onDestroy()
end
]]

local GITIGNORE = [[
/_build/
]]

local VSCODE_SETTINGS = [[
{
	"Lua.runtime.version": "Lua 5.3",
	"Lua.runtime.pathStrict": true,
	"Lua.workspace.checkThirdParty": false,
	"Lua.runtime.path": [
		"?.lua",
		"?/init.lua"
	]
}
]]

return function(name)
	local json = require "json"
	local http = require "socket.http"
	local ltn12 = require "ltn12"

	local should_update_intellisense = false

	local ok, err = pcall(function()
		local intellisense_updated_time = lfs.attributes(AVPath.join{PresetsUtils.PRESETS_PATH, "addon", "intellisense.lua"}, "modification")
		---@diagnostic disable-next-line: cast-type-mismatch
		---@cast intellisense_updated_time integer?
		if intellisense_updated_time == nil then
			should_update_intellisense = true
		else
			print_info("Checking if intellisense information has updated...")
			local sink, parts = ltn12.sink.table()
			http.TIMEOUT = 0.5
			http.request{
				method = "GET",
				url = "https://api.github.com/repos/Cuh4/StormworksAddonLuaDocumentation/commits?path=docs%2Fintellisense.lua&page=1&per_page=1",
				sink = sink,
			}
			local response = json.decode(table.concat(parts))
			local last_commit_time = os.time(Utils.parse_github_timestamp(response[1].commit.committer.date)) + Utils.timezone_offset

			should_update_intellisense = intellisense_updated_time < last_commit_time
		end
	end)
	if not ok then
		print_error("Failed to check for intellisense update: ()\n" .. tostring(err))
	end

	if should_update_intellisense then
		print_info("Updating intellisense information...")
		local sink, parts = ltn12.sink.table()
		http.request{
			method = "GET",
			url = "https://raw.githubusercontent.com/Cuh4/StormworksAddonLuaDocumentation/main/docs/intellisense.lua",
			sink = sink,
		}
		local response = table.concat(parts)
		PresetsUtils.write_file("addon/intellisense.lua", response)
	end


	---@type SSSWTool.NewPreset
	return {
		expect_empty_path = true,
		files = {
			["ssswtool.json"] = {contents=SSSWTOOL_JSON_FMT:format(name)},
			["script.lua"] = {contents=SCRIPT},
			["intellisense.lua"] = {replace=true, contents=PresetsUtils.read_file("addon/intellisense.lua")},
			[".gitignore"] = {contents=GITIGNORE},
			[".vscode/settings.json"] = {contents=VSCODE_SETTINGS},
		},
	}
end
