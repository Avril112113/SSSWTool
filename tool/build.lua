local lfs = require "lfs"

local Parser = require "SelenScript.parser.parser"
local Transformer = require "SelenScript.transformer.transformer"
local Emitter = require "SelenScript.emitter.emitter"
local Utils = require "SelenScript.utils"
local ASTHelpers = require "SelenScript.transformer.ast_helpers"
local AST = require "SelenScript.parser.ast"

local SWAddonTransformerDefs = require "tool.transform_lua_to_swaddon"
local SWAddonTracerTransformerDefs = require "tool.transform_swaddon_tracing"


---@param path string
---@param mode LuaFileSystem.AttributeMode
local function path_is(path, mode)
	local attributes = lfs.attributes(path)
	return attributes ~= nil and attributes.mode == mode
end


local Build = {}


---@param addon_dir string
function Build.build(addon_dir)
	addon_dir = addon_dir:gsub("\\", "/"):gsub("^./", ""):gsub("/$", "")
	if #addon_dir <= 0 then
		addon_dir = "."
	end
	if not path_is(addon_dir, "directory") then
		print(("Invalid addon directory '%s'"):format(addon_dir))
		return -1
	end

	local enable_tracing = false

	local entry_file = "script.lua"
	local entry_file_path = addon_dir .. "/" .. entry_file
	if not path_is(entry_file_path, "file") then
		print(("Missing entry file '%s'"):format(entry_file))
		return -1
	end
	local entry_file_src = Utils.readFile(entry_file_path)

	local time_start = os.clock()

	local parser
	do
		local errors
		print_info("Creating parser")
		parser, errors = Parser.new()
		if #errors > 0 then
			print_error("-- Parser creation Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error((v.id or "NO_ID") .. ": " .. v.msg)
			end
			os.exit(-1)
		end
		if parser == nil or #errors > 0 then
			print_error("Failed to create parser.")
			os.exit(-1)
		end
	end

	local ast, comments
	do
		local errors
		print_info("Parsing 'script.lua'")
		ast, errors, comments = parser:parse(entry_file_src, entry_file_path)
		if #errors > 0 then
			print_error("-- Parse Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error(v.id .. ": " .. v.msg)
			end
			os.exit(-1)
		end
	end

	do
		print_info("Transforming AST")
		local transformer = Transformer.new(SWAddonTransformerDefs)
		local errors = transformer:transform(ast, {
			addon_dir=addon_dir,
			parser=parser,
		})
		if #errors > 0 then
			print_error("-- Transformer Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error(v.id .. ": " .. v.msg)
			end
			os.exit(-1)
		end
	end

	if enable_tracing then
		print_info("Transforming AST (DBG Tracer)")
		local transformer = Transformer.new(SWAddonTracerTransformerDefs)
		local errors = transformer:transform(ast, {
			addon_dir=addon_dir,
			parser=parser,
		})
		if #errors > 0 then
			print_error("-- Transformer Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error(v.id .. ": " .. v.msg)
			end
			os.exit(-1)
		end
	end

	do
		-- Add comment at beginning of file to disable all diagnostics of the file.
		-- This isn't required but is nice to have.
		table.insert(ast.block.block, 1, ASTHelpers.Nodes.LineComment(ast.block.block[1], "---", "@diagnostic disable"))
	end

	do
		print_info("Emitting Lua")
		local emitter_lua = Emitter.new("lua", {})
		local script_out, script_out_source_map = emitter_lua:generate(ast, {
			base_path = addon_dir,
			luacats_source_prefix = "..",
		})

		lfs.mkdir(addon_dir .. "/_build")
		Utils.writeFile(addon_dir .. "/_build/script.lua", script_out)
	end

	local time_finish = os.clock()
	print_info(("Finished in %ss."):format(time_finish-time_start))
end


return Build
