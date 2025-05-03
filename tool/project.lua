local lfs = require "lfs"
local AVPath = require "avpath"
local Lanes = require "lanes"
local WorkerPool = require "avlanesutils.pool"

local Emitter = require "SelenScript.emitter.emitter"
local Utils = require "SelenScript.utils"
local ASTNodes = require "SelenScript.parser.ast_nodes"

local ProjectShadow = require "tool.project_shadow"
local UserConfig = require "tool.userconfig"


---@param path string
---@param mode "file or directory"|LuaFileSystem.AttributeMode
local function path_is(path, mode)
	local attributes = lfs.attributes(path)
	return attributes ~= nil and (attributes.mode == mode or (mode == "file or directory" and (mode == "file" or mode == "directory")))
end


---@class SSSWTool.Project : SSSWTool.ProjectShadow
---@field multiproject SSSWTool.MultiProject
---@field buildactions SSSWTool.BuildActions?
local Project = Utils.shallowcopy(ProjectShadow)
Project.__name = "Project"
Project.__index = Project

Project.MULTITHREADED_BUILD = true

---@param data table
function Project.validate_config(data)
	---@param tbl any
	---@param key_type type|(fun(value:any):boolean)
	---@param value_type type|(fun(value:any):boolean)
	local function table_of(tbl, key_type, value_type)
		if type(tbl) ~= "table" then return false end
		for i, v in pairs(tbl) do
			if type(key_type) == "function" then
				if not key_type(i) then return false end
			else
				if type(i) ~= key_type then return false end
			end
			if type(value_type) == "function" then
				if not value_type(v) then return false end
			else
				if type(v) ~= value_type then return false end
			end
		end
		return true
	end
	assert(type(data) == "table", "Config ROOT expected table")
	assert(type(data.name) == "string", "Config field 'name' expected string")
	assert(type(data.src) == "string" or table_of(data.src, "number", "string"), "Config field 'src' expected string or string[]")
	assert(data.out == nil or type(data.out) == "string" or table_of(data.out, "number", "string"), "Config field 'out' expected string or string[] or nil/null")
end

---@param multiproject SSSWTool.MultiProject
---@param infer_name boolean
function Project.getDefaultConfig(multiproject, infer_name)
	return {
		name = infer_name and AVPath.name(multiproject.project_path) or nil,
		src = ".",
		entrypoint = "script.lua",
		transformers = Project.DEFAULT_TRANSFORMERS,
	}
end


---@param multiproject SSSWTool.MultiProject
---@param config SSSWTool.Project.Config
function Project.new(multiproject, config)
	local self = setmetatable({}, Project)
	self.multiproject = multiproject
	local ok, err = pcall(Project.validate_config, config)
	if not ok then return nil, err end
	self.config = config
	return self
end

function Project:__tostring()
	if self == Project then
		return ("<%s>"):format(Project.__name)
	end
	return ("<%s %p '%s'>"):format(Project.__name, self, self.config and self.config.name)
end

function Project:get_buildactions_init_path()
	return AVPath.join{self.multiproject.project_path, "_buildactions", "init.lua"}
end

function Project:has_buildactions()
	return AVPath.exists(self:get_buildactions_init_path())
end

function Project:ask_buildactions_whitelist()
	print_warn("Build actions are not whitelisted for this directory, would you like to add this project to the whitelist?")
	io.write("y/n ")
	if io.read("*l") == "y" then
		print_info("Whitelisting build actions for '%s'")
		UserConfig.buildactions_whitelist_add(self.multiproject.project_path)
		return true
	end
	return false
end

function Project:_setup_buildactions_env()
	local package_path = package.path
	local buildactions_folder = AVPath.base(self:get_buildactions_init_path())
	package.path = package.path .. (";%s/?.lua;%s/?/init.lua;"):format(buildactions_folder, buildactions_folder)
	return function()
		package.path = package_path
	end
end

function Project:load_buildactions()
	local buildactions_file = self:get_buildactions_init_path()
	print_info(("Loading build actions from '%s'"):format(buildactions_file))
	local revert_buildactions_env = self:_setup_buildactions_env()
	local load_buildactions, err = loadfile(buildactions_file, "t", setmetatable({}, {__index=_G}))
	revert_buildactions_env()
	if err or not load_buildactions then
		print_error("Failed to load build actions:\n" .. tostring(err))
		return false
	end
	local revert_buildactions_env = self:_setup_buildactions_env()
	local ok, buildactions = xpcall(load_buildactions, debug.traceback)
	revert_buildactions_env()
	if not ok then
		print_error("Failed to load build actions:\n" .. tostring(buildactions))
		return false
	elseif type(buildactions) ~= "table" then
		print_error("Failed to load build actions:\nBuild actions didn't return a table.")
		return false
	end
	self.buildactions = buildactions
end

---@param name string
---@param ... any
function Project:call_buildaction(name, ...)
	local f = self.buildactions and self.buildactions[name]
	if not f then return true end
	local revert_buildactions_env = self:_setup_buildactions_env()
	local ok, msg = xpcall(f, debug.traceback, self.multiproject, self, ...)
	revert_buildactions_env()
	if not ok then
		print_error(("Error in build action '%s'\n%s"):format(name, msg))
		return false
	end
	return true
end

function Project:_ensure_workers()
	self._project_shadow = self._project_shadow or setmetatable(ProjectShadow._from_multiproject(self), nil)
	self._worker_pool = self._worker_pool or WorkerPool.new(6, function()
		require "tool.cli_print"
		local AVPath = require "avpath"
		AVPath.SEPERATOR = "/"
	end)
end

function Project:_cleanup_workers()
	self._worker_pool:cancel()
	self._worker_pool = nil
end

---@param parser_factory fun():SelenScript.Parser
---@param file_path string
---@return SelenScript.ASTNodes.Source?, (SelenScript.ASTNodes.LineComment|SelenScript.ASTNodes.LongComment)[], SelenScript.Error[]
function Project:parse_file(parser_factory, file_path)
	return self._worker_pool:collect(self:parse_file_future(parser_factory, file_path))
end

---@param parser_factory fun():SelenScript.Parser
---@param file_path string
---@return AvLanesUtils.Pool.WorkId
function Project:parse_file_future(parser_factory, file_path)
	self:_ensure_workers()
	local project_shadow = self._project_shadow
	return self._worker_pool:work(function()
		local project_shadow = setmetatable(project_shadow, require "tool.project_shadow")
		return project_shadow:parse_file(parser_factory, file_path)
	end)
end

---@param transformer_order string[]
---@param parser_factory fun():SelenScript.Parser
---@param ast SelenScript.ASTNodes.Source
---@param stage "file"|"post"
---@return boolean
function Project:transform_file_ast(transformer_order, parser_factory, ast, stage)
	local status, new_ast = self._worker_pool:collect(self:transform_file_ast_future(transformer_order, parser_factory, ast, stage))
	for i, v in pairs(new_ast) do
		ast[i] = v
	end
	return status
end

---@param transformer_order string[]
---@param parser_factory fun():SelenScript.Parser
---@param ast SelenScript.ASTNodes.Source
---@param stage "file"|"post"
---@return AvLanesUtils.Pool.WorkId
function Project:transform_file_ast_future(transformer_order, parser_factory, ast, stage)
	self:_ensure_workers()
	local project_shadow = self._project_shadow
	return self._worker_pool:work(function()
		local project_shadow = setmetatable(project_shadow, require "tool.project_shadow")
		return project_shadow:transform_file_ast(transformer_order, parser_factory, ast, stage), ast
	end)
end

function Project:build()
	local time_start = os.clock()

	local entry_file_name = self.config.entrypoint or "script.lua"
	local entry_file_path = self:findSrcFile(entry_file_name)
	if not entry_file_path then
		print(("Missing entry file '%s'"):format(entry_file_name))
		return -1
	end

	local underscore_build_path = AVPath.join{self.multiproject.project_path, "_build"}
	lfs.mkdir(underscore_build_path)

	local has_buildactions = self:has_buildactions()
	local allowed_buildactions = has_buildactions and UserConfig.buildactions_whitelist_check(self.multiproject.project_path)
	if has_buildactions and not allowed_buildactions then
		allowed_buildactions = self:ask_buildactions_whitelist()
	end
	if has_buildactions and not allowed_buildactions then
		print_error("Build actions not whitelisted for this directory, this may cause issues for this project.")
	elseif has_buildactions then
		self:load_buildactions()
	end

	if not self:call_buildaction("pre_build") then print_error("Build stopped, see above.") return false end

	local function parser_factory()
		local Parser = require "SelenScript.parser.parser"
		-- print_info("Creating parser")
		local parser, errors = Parser.new({
			selenscript=false,
		})
		if #errors > 0 then
			print_error("-- Parser creation Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error((v.id or "NO_ID") .. ": " .. v.msg)
			end
			print_error("Build stopped, see above.")
			error("STOP_BUILD_QUIET")
		end
		if parser == nil or #errors > 0 then
			error("Failed to create parser.")
		end
		return parser
	end

	self:_ensure_workers()

	local ast, comments
	do
		local errors
		ast, comments, errors = self:parse_file(parser_factory, entry_file_path)
		if #errors > 0 then
			self:_cleanup_workers()
			return false
		end
		assert(ast, "Invalid `ast`?\n= " .. tostring(ast))
	end
	---@cast ast -boolean

	if not self:transform_file_ast(Project.TRANSFORM_ORDER_POST, parser_factory, ast, "post") then
		self:_cleanup_workers()
		return false
	end

	self:_cleanup_workers()

	if not self:call_buildaction("post_transform", ast) then print_error("Build stopped, see above.") return false end

	do
		-- Add comment at beginning of file to disable all diagnostics of the file.
		-- This isn't required but is nice to have.
		table.insert(ast.block.block, 1, ASTNodes.LineComment{
			_parent = ast.block.block,
			prefix = "---",
			value = "@diagnostic disable",
		})
	end

	local script_out
	do
		print_info("Emitting Lua")
		local emitter_time_start = os.clock()
		---@type SelenScript.LuaEmitterConfig|{}
		local emitter_config = {
			luacats_source=true,
		}
		local emitter_lua = Emitter.new("lua", emitter_config)
		local script_out_source_map
		script_out, script_out_source_map = emitter_lua:generate(ast, {
			get_source_path = function(path)
				if path:match("^<SSSWTOOL>/") then
					return path
				end
				return ("../%s"):format(AVPath.relative(path, self.multiproject.project_path))
			end
		})
		print_info(("Finished emitting in %.3fs."):format(os.clock()-emitter_time_start))
		print_info("Writing to '_build'")
		Utils.writeFile(AVPath.join{underscore_build_path, self.config.name .. ".lua"}, script_out)
	end

	if not self:call_buildaction("post_build") then print_error("Build stopped, see above.") return false end

	if self.config.out ~= nil then
		local sw_save_path
		if jit.os == "Windows" then
			local appdata_path = os.getenv("appdata")
			if appdata_path and #appdata_path > 0 then
				sw_save_path = appdata_path .. "\\StormWorks"
			end
		end
		local outs = type(self.config.out) == "string" and {self.config.out} or self.config.out
		if #outs > 0 then
			print_info("Writing configured output files.")
		end
		---@diagnostic disable-next-line: param-type-mismatch
		for _, out in ipairs(outs) do
			---@cast out string
			if out:find("{SW_SAVE}") and not sw_save_path then
				print_warn(("Writing to '%s' failed as '{SW_SAVE}' is not available. (Currently, only Windows is supported for this)"):format(out))
			else
				local SEP = jit.os == "Windows" and "\\" or "/"
				out = out:gsub("{SW_SAVE}", sw_save_path):gsub("{NAME}", self.config.name):gsub("[\\/]", SEP)
				local dir_path = out:match("^(.*)"..SEP)
				if not path_is(dir_path, "directory") then
					print_warn(("Directory does not exist '%s'"):format(dir_path))
				else
					print_info(("Writing '%s'"):format(out))
					Utils.writeFile(out, script_out)
				end
			end
		end
	end

	print_info(("Finished build in %.3fs."):format(os.clock()-time_start))
	return true
end


return Project
