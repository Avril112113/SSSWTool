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

return function(name)
	return {
		["ssswtool.json"] = SSSWTOOL_JSON_FMT:format(name),
		["script.lua"] = SCRIPT,
	}
end
