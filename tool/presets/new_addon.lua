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
	---@type SSSWTool.NewPreset
	return {
		expect_empty_path = true,
		files = {
			["ssswtool.json"] = {contents=SSSWTOOL_JSON_FMT:format(name)},
			["script.lua"] = {contents=SCRIPT},
			[".gitignore"] = {contents=GITIGNORE},
			[".vscode/settings.json"] = {contents=VSCODE_SETTINGS},
		},
	}
end
