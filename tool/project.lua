local lfs = require "lfs"
local AvPath = require "avpath"
local AMF3 = require "amf3"

local Parser = require "SelenScript.parser.parser"
local Transformer = require "SelenScript.transformer.transformer"
local Emitter = require "SelenScript.emitter.emitter"
local Utils = require "SelenScript.utils"
local ASTNodes = require "SelenScript.parser.ast_nodes"
local AST = require "SelenScript.parser.ast"

local UserConfig = require "tool.userconfig"
local CACHE_VERSION = require "tool.cache_version"


---@param path string
---@param mode "file or directory"|LuaFileSystem.AttributeMode
local function path_is(path, mode)
	local attributes = lfs.attributes(path)
	return attributes ~= nil and (attributes.mode == mode or (mode == "file or directory" and (mode == "file" or mode == "directory")))
end


---@class SSSWTool.Transformer : SelenScript.Transformer
---@field multiproject SSSWTool.MultiProject
---@field project SSSWTool.Project
---@field parser SelenScript.Parser
---@field config any


---@class SSSWTool.Project.Config
---@field name string
---@field entrypoint string?
---@field src string|string[]
---@field out string|string[]|nil
---@field transformers table<string,boolean>


---@class SSSWTool.Project
---@field multiproject SSSWTool.MultiProject
---@field config SSSWTool.Project.Config
---@field buildactions SSSWTool.BuildActions[]
local Project = {}
Project.__name = "Project"
Project.__index = Project

Project.TRANSFORMERS = {
	magic_variables = {
		file = require "tool.transform_magic_variables"
	},
	combiner = {
		post = require "tool.transform_combiner"
	},
	tracing = {
		file = require "tool.transform_swaddon_tracing_file",
		post = require "tool.transform_swaddon_tracing_post"
	},
}
--- Applied to each individual file
Project.TRANSFORM_ORDER_FILE = {
	"tracing",
	"magic_variables",
}
--- Applied to the final ast
--- Avoid adding these if possible, as any changes aren't cached here.
Project.TRANSFORM_ORDER_POST = {
	"combiner",
	"tracing",
}
Project.DEFAULT_TRANSFORMERS = {
	magic_variables = true,
	combiner = true,
	tracing = false,
}

Project.TRANSFORM_ORDER_FILE_MAP = {}
for i, v in pairs(Project.TRANSFORM_ORDER_FILE_MAP) do
	Project.TRANSFORM_ORDER_FILE_MAP[v] = true
end

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
		name = infer_name and AvPath.name(multiproject.project_path) or nil,
		src = ".",
		entrypoint = "script.lua",
		transformers = Project.DEFAULT_TRANSFORMERS,
	}
end


---@param multiproject SSSWTool.MultiProject
---@param config SSSWTool.Project.Config
function Project.new(multiproject, config)
	local self = setmetatable({}, Project)
	self.buildactions = {}
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
	return AvPath.join{self.multiproject.project_path, "_buildactions", "init.lua"}
end

function Project:has_buildactions()
	return AvPath.exists(self:get_buildactions_init_path())
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

function Project:_set_buildactions_env()
	local buildactions_parent_folder = (AvPath.base(AvPath.base(self:get_buildactions_init_path())))

	local package_path = package.path
	package.path = package.path .. (";%s/?.lua;%s/?/init.lua;"):format(buildactions_parent_folder, buildactions_parent_folder)
	return function()
		package.path = package_path
	end
end

function Project:load_buildactions()
	local buildactions_file = self:get_buildactions_init_path()
	print_info(("Loading build actions from '%s'"):format(buildactions_file))
	local revert = self:_set_buildactions_env()
	local load_buildactions, err = loadfile(buildactions_file, "t", setmetatable({}, {__index=_G}))
	revert()
	if err or not load_buildactions then
		print_error("Failed to load build actions:\n" .. tostring(err))
		return false
	end
	local revert = self:_set_buildactions_env()
	local ok, buildactions = xpcall(load_buildactions, debug.traceback)
	revert()
	if not ok then
		print_error("Failed to load build actions:\n" .. tostring(buildactions))
		return false
	elseif type(buildactions) ~= "table" then
		print_error("Failed to load build actions:\nBuild actions didn't return a table.")
		return false
	end
	self:add_buildactions(buildactions)
end

--- Adds a set of buildactions
---@param buildactions SSSWTool.BuildActions
---@param run_before boolean?  # Default: false
function Project:add_buildactions(buildactions, run_before)
	if run_before then
		table.insert(self.buildactions, 1, buildactions)
	else
		table.insert(self.buildactions, buildactions)
	end
end

---@param name string
---@param ... any
function Project:call_buildaction(name, ...)
	for _, buildactions in ipairs(self.buildactions) do
		local f = buildactions[name]
		if not f then goto continue end
		local revert = self:_set_buildactions_env()
		local ok, msg = xpcall(f, debug.traceback, self.multiproject, self, ...)
		revert()
		if not ok then
			print_error(("Error in build action '%s'\n%s"):format(name, msg))
			return false
		end
	    ::continue::
	end
	return true
end

---@param path string  # Project local path to file.
---@param mode "file"|"directory"|"file or directory"|LuaFileSystem.AttributeMode
---@param searchpath string?  # Lua style search path, defaults to "?" to find a real file path.
---@return string, string, nil
---@overload fun(path:string): nil, nil, string
function Project:findSrcFile(path, mode, searchpath)
	searchpath = searchpath or "?"
	local paths = {}
	for path_template in searchpath:gmatch("[^;]+") do
		table.insert(paths, (path_template:gsub("%?", path)))
	end
	mode = mode or "file"
	local searched = {}
	local function check(base)
		for _, local_path in ipairs(paths) do
			local src_path = AvPath.join{base, local_path}
			local full_path = AvPath.join{self.multiproject.project_path, src_path}
			table.insert(searched, ("no %s '%s'"):format(mode, full_path))
			if path_is(full_path, mode) then
				return full_path, src_path
			end
		end
	end

	local srcs = type(self.config.src) == "string" and {self.config.src} or self.config.src
	---@diagnostic disable-next-line: param-type-mismatch
	for _, src in ipairs(srcs) do
		local full_path, src_path = check(src)
		if full_path and src_path then
			return full_path, src_path
		end
	end
	return nil, nil, table.concat(searched, "\n")
end

---@param modpath string # Project local mod path to file.
---@param lua_path string? # Lua search path, default "?.lua;?/init.lua;"
---@return string, string, nil
---@overload fun(modpath, lua_path): nil, nil, string
function Project:findModFile(modpath, lua_path)
	lua_path = lua_path or "?.lua;?/init.lua;"
	local path_parts = {}
	local srcs = type(self.config.src) == "string" and {self.config.src} or self.config.src
	---@cast srcs string[]
	for _, src in ipairs(srcs) do
		if #src > 0 then
			if AvPath.getabs(src) then
				table.insert(path_parts, (lua_path:gsub(
					"%?",
					AvPath.join{src, "?"}
				)))
			else
				table.insert(path_parts, (lua_path:gsub(
					"%?",
					AvPath.join{self.multiproject.project_path, src, "?"}
				)))
			end
		end
	end
	local full_path, err = package.searchpath(modpath, table.concat(path_parts, ";"))
	if full_path then
		full_path = AvPath.norm(full_path)
		local src_path = AvPath.relative(AvPath.abs(full_path), AvPath.abs(self.multiproject.project_path))
		return full_path, src_path, nil
	end
	return nil, nil, err
end

--- Utility for buildactions
---@param source string
function Project:parse_raw(source)
	local parser = self:get_parser()
	if not parser then return nil, nil end
	local ast, errors, comments = self:get_parser():parse(source)
	if #errors > 0 then
		print_error("-- Parse Raw Errors: " .. #errors .. " --")
		for _, v in ipairs(errors) do
			print_error(v.id .. ": " .. v.msg)
		end
		return nil, nil
	end
	return ast, comments
end

---@param parser SelenScript.Parser
---@param file_path string
function Project:parse_file(parser, file_path)
	---@class SelenScript.ASTNodes.Source
	---@field _transformers {[string]:true}?
	---@field _cache_version number

	local project_file_path
	if AvPath.getabs(file_path) then
		project_file_path = file_path
	else
		project_file_path = AvPath.relative(file_path, self.multiproject.project_path)
	end
	print_info(("  '%s'"):format(project_file_path))

	if not self:call_buildaction("pre_file", file_path) then print_error("Build stopped, see above.") error("STOP_BUILD_QUIET") end

	local cache_dir = AvPath.join{self.multiproject.project_path, "_build", "cache"}
	lfs.mkdir(cache_dir)
	local cache_name = file_path:gsub("_", "__"):gsub(":", "_"):gsub("[\\/]", "_") .. ".amf3"
	local cache_path = AvPath.join{cache_dir, cache_name}
	local use_cached = AvPath.exists(cache_path) and lfs.attributes(file_path, "modification") < lfs.attributes(cache_path, "modification")

	---@type SelenScript.ASTNodes.Source?, SelenScript.Error[], (SelenScript.ASTNodes.LineComment|SelenScript.ASTNodes.LongComment)[]
	local ast, errors, comments
	if use_cached then
		local packed = Utils.readFile(cache_path, true)
		local ok, unpacked = pcall(AMF3.decode, packed, nil, Parser.amf3_handler)
		if ok then
			ast = unpacked
			---@cast ast SelenScript.ASTNodes.Source
			if not ast._transformers or not Utils.deepeq(self.config.transformers, ast._transformers) or CACHE_VERSION ~= ast._cache_version then
				print_info("Cache outdated...")
				ast = nil
				pcall(os.remove, cache_path)
			end
		else
			print_warn("Failed to load cached AST: " .. tostring(unpacked))
			pcall(os.remove, cache_path)
		end
		if ast then
			print_info("Cache read...")
		end
	end

	if ast == nil then
		print_info("Parsing...")
		if not self:call_buildaction("pre_parse", file_path) then print_error("Build stopped, see above.") error("STOP_BUILD_QUIET") end

		ast, errors, comments = parser:parse(Utils.readFile(file_path), file_path)
		if #errors > 0 then
			print_error("-- Parse Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error(v.id .. ": " .. v.msg)
			end
			if not self:call_buildaction("post_parse", file_path, ast, errors, comments) then print_error("Build stopped, see above.") error("STOP_BUILD_QUIET") end
			return ast, comments, errors
		end

		if not self:transform_file_ast(Project.TRANSFORM_ORDER_FILE, parser, ast, "file") then
			ast = nil
		else
			if not self:call_buildaction("post_parse", file_path, ast, errors, comments) then print_error("Build stopped, see above.") error("STOP_BUILD_QUIET") end
			local cpy = Utils.shallowcopy(ast)
			cpy._cache_version = CACHE_VERSION
			cpy._transformers = Utils.deepcopy(self.config.transformers)
			local packed = AMF3.encode(cpy)
			Utils.writeFile(cache_path, packed, true)
		end
	end
	if not self:call_buildaction("post_file", file_path, ast) then print_error("Build stopped, see above.") error("STOP_BUILD_QUIET") end

	return ast, comments or {}, errors or {}
end

---@param transformer_order string[]
---@param parser SelenScript.Parser
---@param ast SelenScript.ASTNodes.Source
---@param stage "file"|"post"
function Project:transform_file_ast(transformer_order, parser, ast, stage)
	for _, transformer_name in ipairs(transformer_order) do
		if self.config.transformers[transformer_name] then
			print_info(("Transforming AST with '%s' @ %s"):format(transformer_name, stage))
			local transform_time_start = os.clock()
			local TransformerDefs = assert(Project.TRANSFORMERS[transformer_name] and Project.TRANSFORMERS[transformer_name][stage], ("Missing transformer '%s' for stage '%s'"):format(transformer_name, stage))
			local transformer = Transformer.new(TransformerDefs)
			local ok, errors = xpcall(transformer.transform, debug.traceback, transformer, ast, {
				multiproject = self.multiproject,
				project = self,
				parser = parser,
				config = self.config.transformers[transformer_name],
			})
			if not ok then
				if type(errors) == "string" and errors:find("STOP_BUILD_QUIET") then
					return false
				else
					print_error(errors)
				end
			end
			if #errors > 0 then
				print_error("-- Transformer Errors: " .. #errors .. " --")
				for _, v in ipairs(errors) do
					print_error(v.id .. ": " .. v.msg)
				end
				return false
			end
			print_info(("Finished '%s' in %.3fs."):format(transformer_name, os.clock()-transform_time_start))
		-- else
		-- 	print_info(("Transforming AST skipped '%s' (disabled)"):format(transformer_name))
		end
	end
	return true
end

function Project:get_parser()
	if self._shared_parser ~= nil then return self._shared_parser end
	print_info("Creating parser")
	local parser, errors = Parser.new({
		selenscript=false,
	})
	if #errors > 0 then
		print_error("-- Parser creation Errors: " .. #errors .. " --")
		for _, v in ipairs(errors) do
			print_error((v.id or "NO_ID") .. ": " .. v.msg)
		end
		self._shared_parser = false
		return false
	end
	if parser == nil or #errors > 0 then
		print_error("Failed to create parser.")
		self._shared_parser = false
		return false
	end
	self._shared_parser = parser
	return parser
end

function Project:build()
	local time_start = os.clock()

	local entry_file_name = self.config.entrypoint or "script.lua"
	local entry_file_path = self:findSrcFile(entry_file_name)
	if not entry_file_path then
		print(("Missing entry file '%s'"):format(entry_file_name))
		return -1
	end

	local underscore_build_path = AvPath.join{self.multiproject.project_path, "_build"}
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

	local parser = self:get_parser()
	if not parser then return false end

	local ast, comments
	do
		local errors
		ast, comments, errors = self:parse_file(parser, entry_file_path)
		if #errors > 0 then
			return false
		end
		assert(ast, "Invalid `ast`?\n= " .. tostring(ast))
	end
	---@cast ast -boolean

	if not self:transform_file_ast(Project.TRANSFORM_ORDER_POST, parser, ast, "post") then
		return false
	end

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
				return ("../%s"):format(AvPath.relative(path, self.multiproject.project_path))
			end
		})
		print_info(("Finished emitting in %.3fs."):format(os.clock()-emitter_time_start))
		print_info("Writing to '_build'")
		Utils.writeFile(AvPath.join{underscore_build_path, self.config.name .. ".lua"}, script_out)
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
