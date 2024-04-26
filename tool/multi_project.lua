local Utils = require "SelenScript.utils"
local AVPath = require "avpath"

local Config = require "tool.config"
local Project = require "tool.project"


---@class SSSWTool.MultiProject
---@field config_path string # Normalized path to the project config file.
---@field project_path string # Normalized path to the project.
---@field projects (SSSWTool.Project|SSSWTool.MultiProject)[]
---@field config SSSWTool.Config
local MultiPorject = {}
MultiPorject.__index = MultiPorject


---@param config_path string
function MultiPorject.new(config_path)
	local self = setmetatable({}, MultiPorject)
	self.config_path = AVPath.norm(config_path)
	self.project_path = AVPath.base(config_path)

	self.projects = {}
	self.config = Config.new()
	local ok, err, code = self.config:read(config_path)
	if not ok then
		return nil, err, code
	end
	if type(self.config.data) == "table" and type(self.config.data[1]) == "table" then
		print_info(("Multi Project config '%s'"):format(config_path))
		for i, v in ipairs(self.config.data) do
			if type(v) == "string" then
				self:createMultiProject(self.project_path .. "/" .. v, ("'%s' index %s"):format(config_path, i))
			else
				Utils.merge(Project.getDefaultConfig(self, false), v, false)
				self:createProject(v, ("'%s' index %s"):format(config_path, i))
			end
		end
	else
		Utils.merge(Project.getDefaultConfig(self, true), self.config.data, false)
		self:createProject(self.config.data, config_path)
	end
	return self
end

---@param project_config SSSWTool.Project.Config
---@param project_path string
function MultiPorject:createProject(project_config, project_path)
	local project, err = Project.new(self, project_config)
	if not project or err then
		if err then
			print_error(("%s: %s"):format(project_config.name or project_path, err:gsub(".-:.-: ", "")))
			return nil
		else
			error("ERROR project == nil")
		end
	else
		print_info(("Loaded config for %s"):format(project_config.name or project_path))
	end
	table.insert(self.projects, project)
	return project
end

---@param config_path string
---@param project_path string
function MultiPorject:createMultiProject(config_path, project_path)
	local multiproject = MultiPorject.new(config_path)
	table.insert(self.projects, multiproject)
	return multiproject
end

---@return {[1]:SSSWTool.Project|SSSWTool.MultiProject,[2]:any[]}[]
function MultiPorject:build()
	local results = {}
	for _, project in ipairs(self.projects) do
		print()
		print_info(("Building '%s'"):format(project.config.name or AVPath.relative(project.config_path, self.project_path)))
		local result = {project:build()}
		table.insert(results, {project, result})
	end
	return results
end


return MultiPorject
