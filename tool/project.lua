local lfs = require "lfs"
local AVPath = require "avpath"

local Parser = require "SelenScript.parser.parser"
local Transformer = require "SelenScript.transformer.transformer"
local Emitter = require "SelenScript.emitter.emitter"
local Utils = require "SelenScript.utils"
local ASTHelpers = require "SelenScript.transformer.ast_helpers"
local AST = require "SelenScript.parser.ast"


---@param path string
---@param mode LuaFileSystem.AttributeMode
local function path_is(path, mode)
	local attributes = lfs.attributes(path)
	return attributes ~= nil and attributes.mode == mode
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
local Project = {}
Project.__name = "Project"
Project.__index = Project

Project.TRANSFORMERS = {
	combiner = require "tool.transform_combiner",
	tracing = require "tool.transform_swaddon_tracing",
}
Project.TRANSFORM_ORDER = {
	"combiner",
	"tracing",
}
Project.DEFAULT_TRANSFORMERS = {
	combiner = true,
	tracing = false,
}

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

---@param path string # Project local path to file.
---@return string, string, nil
---@overload fun(path:string): nil, nil, string
function Project:findSrcFile(path)
	local searched = {}
	local function check(base)
		local src_path = AVPath.join{base, path}
		local full_path = AVPath.join{self.multiproject.project_path, src_path}
		table.insert(searched, ("no file '%s'"):format(full_path))
		if path_is(full_path, "file") then
			return full_path, src_path
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
---@return string, string, nil
---@overload fun(modpath:string): nil, nil, string
function Project:findModFile(modpath, path)
	path = path or "?.lua;?/init.lua;"
	local path_parts = {}
	local srcs = type(self.config.src) == "string" and {self.config.src} or self.config.src
	---@cast srcs string[]
	---@diagnostic disable-next-line: param-type-mismatch
	for _, src in ipairs(srcs) do
		if #src > 0 then
			if AVPath.getabs(src) then
				table.insert(path_parts, (path:gsub(
					"%?",
					AVPath.join{src, "?"}
				)))
			else
				table.insert(path_parts, (path:gsub(
					"%?",
					AVPath.join{self.multiproject.project_path, src, "?"}
				)))
			end
		end
	end
	local full_path, err = package.searchpath(modpath, table.concat(path_parts, ";"))
	if full_path then
		full_path = AVPath.norm(full_path)
		local src_path = AVPath.relative(full_path, self.multiproject.project_path)
		return full_path, src_path, nil
	end
	return nil, nil, err
end

function Project:build()
	local time_start = os.clock()

	local entry_file_name = self.config.entrypoint or "script.lua"
	local entry_file_path = self:findSrcFile(entry_file_name)
	if not entry_file_path then
		print(("Missing entry file '%s'"):format(entry_file_name))
		return -1
	end
	local entry_file_src = Utils.readFile(entry_file_path)

	local underscore_build_path = AVPath.join{self.multiproject.project_path, "_build"}
	lfs.mkdir(underscore_build_path)

	local parser
	do
		local errors
		print_info("Creating parser")
		parser, errors = Parser.new({
			selenscript=false,
		})
		if #errors > 0 then
			print_error("-- Parser creation Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error((v.id or "NO_ID") .. ": " .. v.msg)
			end
			return false
		end
		if parser == nil or #errors > 0 then
			print_error("Failed to create parser.")
			return false
		end
	end

	local ast, comments
	do
		local errors
		print_info(("Parsing '%s'"):format(entry_file_name))
		ast, errors, comments = parser:parse(entry_file_src, entry_file_path)
		if #errors > 0 then
			print_error("-- Parse Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error(v.id .. ": " .. v.msg)
			end
			return false
		end
	end

	for _, transformer_name in ipairs(Project.TRANSFORM_ORDER) do
		if self.config.transformers[transformer_name] then
			print_info(("Transforming AST with '%s'"):format(transformer_name))
			local transform_time_start = os.clock()
			local TransformerDefs = assert(Project.TRANSFORMERS[transformer_name], ("Missing transformer"):format(transformer_name))
			local transformer = Transformer.new(TransformerDefs)
			local errors = transformer:transform(ast, {
				multiproject = self.multiproject,
				project = self,
				parser = parser,
				config = self.config.transformers[transformer_name],
			})
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

	do
		-- Add comment at beginning of file to disable all diagnostics of the file.
		-- This isn't required but is nice to have.
		table.insert(ast.block.block, 1, ASTHelpers.Nodes.LineComment(ast.block.block, "---", "@diagnostic disable"))
	end

	local script_out
	do
		print_info("Emitting Lua")
		local emitter_time_start = os.clock()
		---@type SelenScript.LuaEmitterConfig
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
