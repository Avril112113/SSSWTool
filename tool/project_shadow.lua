local lfs = require "lfs"
local AVPath = require "avpath"
local Lanes = require "lanes"
local AMF3 = require "amf3"

local Parser = require "SelenScript.parser.parser"
local Transformer = require "SelenScript.transformer.transformer"
local Emitter = require "SelenScript.emitter.emitter"
local Utils = require "SelenScript.utils"
local ASTNodes = require "SelenScript.parser.ast_nodes"
local AST = require "SelenScript.parser.ast"

local MultiProjectShadow = require "tool.multiproject_shadow"


---@param path string
---@param mode "file or directory"|LuaFileSystem.AttributeMode
local function path_is(path, mode)
	local attributes = lfs.attributes(path)
	return attributes ~= nil and (attributes.mode == mode or (mode == "file or directory" and (mode == "file" or mode == "directory")))
end


---@class SSSWTool.Transformer : SelenScript.Transformer
---@field multiproject SSSWTool.MultiProject
---@field project SSSWTool.ProjectShadow
---@field parser_factory fun():SelenScript.Parser
---@field config any


---@class SSSWTool.Project.Config
---@field name string
---@field entrypoint string?
---@field src string|string[]
---@field out string|string[]|nil
---@field transformers table<string,boolean>


--- LuaLanes compatible
---@class SSSWTool.ProjectShadow
---@field multiproject SSSWTool.MultiProjectShadow
---@field config SSSWTool.Project.Config
local ProjectShadow = {}
ProjectShadow.__index = ProjectShadow

ProjectShadow.TRANSFORMERS = {
	magic_variables = {
		file = require "tool.transform_magic_variables"
	},
	combiner = {
		file = require "tool.transform_combiner_file",
		post = require "tool.transform_combiner_post"
	},
	tracing = {
		file = require "tool.transform_swaddon_tracing_file",
		post = require "tool.transform_swaddon_tracing_post"
	},
}
--- Applied to each individual file
ProjectShadow.TRANSFORM_ORDER_FILE = {
	"tracing",
	"magic_variables",
	"combiner",
}
--- Applied to the final ast
--- Avoid adding these if possible, as any changes aren't cached here.
ProjectShadow.TRANSFORM_ORDER_POST = {
	"combiner",
	"tracing",
}
ProjectShadow.DEFAULT_TRANSFORMERS = {
	magic_variables = true,
	combiner = true,
	tracing = false,
}


---@param project SSSWTool.Project
---@return SSSWTool.ProjectShadow
function ProjectShadow._from_multiproject(project)
	return setmetatable({
		multiproject = MultiProjectShadow._from_multiproject(project.multiproject),
		config = project.config,
	}, ProjectShadow)
end

---@param path string # Project local path to file.
---@param mode "file"|"directory"|"file or directory"|LuaFileSystem.AttributeMode
---@return string, string, nil
---@overload fun(path:string): nil, nil, string
function ProjectShadow:findSrcFile(path, mode)
	mode = mode or "file"
	local searched = {}
	local function check(base)
		local src_path = AVPath.join{base, path}
		local full_path = AVPath.join{self.multiproject.project_path, src_path}
		table.insert(searched, ("no %s '%s'"):format(mode, full_path))
		if path_is(full_path, mode) then
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
---@param lua_path string? # Lua search path, default "?.lua;?/init.lua;"
---@return string, string, nil
---@overload fun(modpath, lua_path): nil, nil, string
function ProjectShadow:findModFile(modpath, lua_path)
	lua_path = lua_path or "?.lua;?/init.lua;"
	local path_parts = {}
	local srcs = type(self.config.src) == "string" and {self.config.src} or self.config.src
	---@cast srcs string[]
	for _, src in ipairs(srcs) do
		if #src > 0 then
			if AVPath.getabs(src) then
				table.insert(path_parts, (lua_path:gsub(
					"%?",
					AVPath.join{src, "?"}
				)))
			else
				table.insert(path_parts, (lua_path:gsub(
					"%?",
					AVPath.join{self.multiproject.project_path, src, "?"}
				)))
			end
		end
	end
	local full_path, err = package.searchpath(modpath, table.concat(path_parts, ";"))
	if full_path then
		full_path = AVPath.norm(full_path)
		local src_path = AVPath.relative(AVPath.abs(full_path), AVPath.abs(self.multiproject.project_path))
		return full_path, src_path, nil
	end
	return nil, nil, err
end

--- Used to check if a given path is a valid location to require.
--- Unlike `findModFile`, this searched by path rather than modpath.
---@param path string # File path to get mod path from
---@param lua_path string? # Lua search path, default "?.lua;?/init.lua;"
---@return string, string, nil
---@overload fun(path, lua_path): nil, nil, string
function ProjectShadow:getModPath(path, lua_path)
	lua_path = lua_path or "?.lua;?/init.lua;"
	lua_path = lua_path:gsub(
		"%?",
		AVPath.join{AVPath.abs(AVPath.join{path, ".."}), "?"}
	)
	local modpath = AVPath.name(path):gsub("%.lua$", "")
	local full_path, src_path, err = self:findModFile(modpath, lua_path)
	return full_path, src_path, err
end


---@param parser_factory fun():SelenScript.Parser
---@param file_path string
---@return SelenScript.ASTNodes.Source?, (SelenScript.ASTNodes.LineComment|SelenScript.ASTNodes.LongComment)[], SelenScript.Error[]
function ProjectShadow:parse_file(parser_factory, file_path)
	---@class SelenScript.ASTNodes.Source
	---@field _transformers {[string]:true}?

	local project_file_path
	if AVPath.getabs(file_path) then
		project_file_path = file_path
	else
		project_file_path = AVPath.relative(file_path, self.multiproject.project_path)
	end
	print_info(("  '%s'"):format(project_file_path))

	-- if not self:call_buildaction("pre_file", file_path) then print_error("Build stopped, see above.") error("STOP_BUILD_QUIET") end

	local cache_dir = AVPath.join{self.multiproject.project_path, "_build", "cache"}
	lfs.mkdir(cache_dir)
	local cache_name = file_path:gsub("_", "__"):gsub(":", "_"):gsub("[\\/]", "_") .. ".amf3"
	local cache_path = AVPath.join{cache_dir, cache_name}
	local use_cached = AVPath.exists(cache_path) and lfs.attributes(file_path, "modification") < lfs.attributes(cache_path, "modification")

	---@type SelenScript.ASTNodes.Source?, SelenScript.Error[], (SelenScript.ASTNodes.LineComment|SelenScript.ASTNodes.LongComment)[]
	local ast, errors, comments
	if use_cached then
		local packed = Utils.readFile(cache_path, true)
		local ok, unpacked = pcall(AMF3.decode, packed, nil, Parser.amf3_handler)
		if ok then
			ast = unpacked
			---@cast ast SelenScript.ASTNodes.Source
			if not ast._transformers or not Utils.deepeq(self.config.transformers, ast._transformers) then
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
		-- if not self:call_buildaction("pre_parse", file_path) then print_error("Build stopped, see above.") error("STOP_BUILD_QUIET") end

		local parser = parser_factory()
		ast, errors, comments = parser:parse(Utils.readFile(file_path), file_path)
		if #errors > 0 then
			print_error("-- Parse Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error(v.id .. ": " .. v.msg)
			end
			-- if not self:call_buildaction("post_parse", file_path, ast, errors, comments) then print_error("Build stopped, see above.") error("STOP_BUILD_QUIET") end
			return ast, comments, errors
		end

		if not self:transform_file_ast(ProjectShadow.TRANSFORM_ORDER_FILE, parser_factory, ast, "file") then
			ast = nil
		else
			-- if not self:call_buildaction("post_parse", file_path, ast, errors, comments) then print_error("Build stopped, see above.") error("STOP_BUILD_QUIET") end
			local cpy = Utils.shallowcopy(ast)
			cpy._transformers = Utils.deepcopy(self.config.transformers)
			-- local packed = .encode(cpy)
			local packed = AMF3.encode(cpy)
			Utils.writeFile(cache_path, packed, true)
		end
	end
	-- if not self:call_buildaction("post_file", file_path, ast) then print_error("Build stopped, see above.") error("STOP_BUILD_QUIET") end

	return ast, comments or {}, errors or {}
end

---@param parser_factory fun():SelenScript.Parser
---@param file_path string
---@return AvLanesUtils.Pool.WorkId
function ProjectShadow:parse_file_future(parser_factory, file_path)
	local project_shadow = Utils.shallowcopy(self)
	return require "avlanesutils.pool_worker_context".work_async(function()
		local project_shadow = setmetatable(project_shadow, require "tool.project_shadow")
		return project_shadow:parse_file(parser_factory, file_path)
	end)
end

---@param transformer_order string[]
---@param parser_factory fun():SelenScript.Parser
---@param ast SelenScript.ASTNodes.Source
---@param stage "file"|"post"
function ProjectShadow:transform_file_ast(transformer_order, parser_factory, ast, stage)
	for _, transformer_name in ipairs(transformer_order) do
		if self.config.transformers[transformer_name] then
			print_info(("Transforming AST with '%s' @ %s"):format(transformer_name, stage))
			local transform_time_start = os.clock()
			local TransformerDefs = assert(ProjectShadow.TRANSFORMERS[transformer_name] and ProjectShadow.TRANSFORMERS[transformer_name][stage], ("Missing transformer '%s' for stage '%s'"):format(transformer_name, stage))
			local transformer = Transformer.new(TransformerDefs)
			local ok, errors = xpcall(transformer.transform, debug.traceback, transformer, ast, {
				multiproject = self.multiproject,
				project = self,
				parser_factory = parser_factory,
				config = self.config.transformers[transformer_name],
			})
			if not ok then
				if type(errors) == "string" and errors:find("STOP_BUILD_QUIET") then
					return false
				else
					print_error(("Error from transformer '%s' @ %s:\n%s"):format(transformer_name, stage, errors))
					return false
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


return ProjectShadow
