local args = assert(arg)

local tool_path = assert(args[0]):gsub("[\\/][^\\/]*$", "")

package.path = ("%s/?.lua;%s/?/init.lua;%s/../SelenScript/libs/?.lua;%s/../SelenScript/libs/?/init.lua;%s/../SelenScript/?.lua;%s/../SelenScript/?/init.lua;"):gsub("%%s", tool_path)
package.cpath = ("%s/?.dll;%s/../SelenScript/libs/?.dll;"):gsub("%%s", tool_path)

local lfs = require "lfs"
local logging = require "logging".windows_enable_ansi().set_log_file("build.log", true)
---@diagnostic disable-next-line: duplicate-set-field
logging.get_source = function() return "" end

local Parser = require "SelenScript.parser.parser"
local Transformer = require "SelenScript.transformer.transformer"
local Emitter = require "SelenScript.emitter.emitter"
local Utils = require "SelenScript.utils"
local ASTHelpers = require "SelenScript.transformer.ast_helpers"

local SWAddonTransformerDefs = require "transform_lua_to_swaddon"
local SWAddonTracerTransformerDefs = require "transform_swaddon_tracing"


if table.remove(args, 1) ~= "build" then
	print_error("Argument #1 expected 'build'")
	os.exit(-1)
end

local addon_dir = (table.remove(args, 1) or ""):gsub("\\", "/"):gsub("^./", ""):gsub("/$", "")
if #addon_dir <= 0 then
	addon_dir = "."
end
local addon_dir_attributes = assert(lfs.attributes(addon_dir), "Invalid arg #1 addon path.")
assert(addon_dir_attributes.mode == "directory", "Invalid arg #1 addon path must be a directory.")

local script_file = addon_dir .. "/script.lua"
assert(lfs.attributes(script_file), "Addon directory does not contain 'script.lua'.")

local script_file_src = Utils.readFile(script_file)

local enable_tracing = false
for i, arg in ipairs(args) do
	if arg == "--trace" then
		enable_tracing = true
	elseif arg == "--no-trace" then
		enable_tracing = false
	else
		print_warn(("Unexpected argument #%i '%s'"):format(i, arg))
	end
end

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
	ast, errors, comments = parser:parse(script_file_src, script_file)
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

	local time_finish = os.clock()
	print_info(("Finished in %ss."):format(time_finish-time_start))
end
