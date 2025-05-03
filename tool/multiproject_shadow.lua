--- LuaLanes compatible
---@class SSSWTool.MultiProjectShadow
---@field project_path string # Normalized path to the project.
---@field config_path string # Normalized path to the project config file.
local MultiProjectShadow = {}
MultiProjectShadow.__index = MultiProjectShadow

---@param multiproject SSSWTool.MultiProject
---@return SSSWTool.MultiProjectShadow
function MultiProjectShadow._from_multiproject(multiproject)
	return setmetatable({
		project_path = multiproject.project_path,
		config_path = multiproject.config_path,
	}, MultiProjectShadow)
end


return MultiProjectShadow
