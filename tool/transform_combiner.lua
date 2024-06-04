local modpath = ...

local AVPath = require "avpath"
local lfs = require "lfs"
local MessagePack = require "MessagePack"

local Utils = require "SelenScript.utils"
local Parser = require "SelenScript.parser.parser"
local ASTHelpers = require "SelenScript.transformer.ast_helpers"
local ASTNodes = ASTHelpers.Nodes
local AST = require "SelenScript.parser.ast"  -- Used for debugging.

---@diagnostic disable-next-line: param-type-mismatch
local REQUIRE_SRC_FILE = AVPath.join{package.searchpath(modpath, package.path), "../src/require.lua"}


---@class SSSWTool.Transformer_Combiner : SSSWTool.Transformer
---@field required_files table<string,ASTNodeSource|false>
local TransformerDefs = {}


---@param node ASTNode
---@return ASTNodeSource?
function TransformerDefs:_get_root_source(node)
	local source = node
	while true do
		local t = self:find_parent_of_type(source, "source")
		if t then
			source = t
		else
			break
		end
	end
	return source.type == "source" and source or nil
end

---@param node ASTNode
---@param func_node ASTNode
---@param modpath string
---@param filepath string
function TransformerDefs:_add_require(node, func_node, modpath, filepath)
	local source = self:_get_root_source(node)
	if source == nil then error("Missing source node.") end
	local block
	if not self._SWAddon_RequiresBlock then
		local require_src_ast, errors, comments = self.parser:parse(Utils.readFile(REQUIRE_SRC_FILE), "<SSSWTOOL>/src/require.lua")
		if #errors > 0 then
			print_error("-- Parse Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error(v.id .. ": " .. v.msg)
			end
			os.exit(-1)
		end

		block = ASTNodes.block(source,
			ASTNodes.LineComment(source, "--", "#region SSSWTool-Require-src"),
			require_src_ast,
			ASTNodes.LineComment(source, "--", "#endregion")
		)
		self._SWAddon_RequiresBlock = block
		table.insert(source.block.block, 1, block)
	end
	block = block or self._SWAddon_RequiresBlock
	-- Using +1 to be below the `--#endregion` comment
	-- Assign to __SSSWTOOL_MOD_TO_FILEPATH
	table.insert(block, #block+1, ASTNodes.assign(source, nil,
		ASTNodes.varlist(source, ASTNodes.index(source, nil, ASTNodes.name(source, "__SSSWTOOL_MOD_TO_FILEPATH"), ASTNodes.index(source, "[", ASTNodes.string(source, modpath)))),
		ASTNodes.expressionlist(source, ASTNodes.string(source, filepath))
	))
	-- Assign to __SSSWTOOL_REQUIRES
	table.insert(block, #block+1, ASTNodes.assign(source, nil,
		ASTNodes.varlist(source, ASTNodes.index(source, nil, ASTNodes.name(source, "__SSSWTOOL_REQUIRES"), ASTNodes.index(source, "[", ASTNodes.string(source, modpath)))),
		ASTNodes.expressionlist(source, func_node)
	))
end


---@param node ASTNode
function TransformerDefs:index(node)
	if node.type == "index" and node.expr.name == "require" then
		-- print(AST.tostring_ast(node))
		local call_node
		local modpath
		if node.index.type == "call" then
			call_node = node.index
		elseif node.index.type == "index" and node.index.expr.type == "call" then
			call_node = node.index.expr
		else
			return node
		end
		if call_node.args.type == "string" then
			modpath = call_node.args.value
		elseif call_node.args[1].type == "string" then
			modpath = call_node.args[1].value
		else
			return node
		end
		local filepath, filepath_local, err = self.project:findModFile(modpath)
		self.required_files = self.required_files or {}
		if err or not filepath then
			print_error(("Failed to find '%s'%s"):format(modpath, err))
			return ASTNodes.LongComment(node, nil, ("Failed to find '%s'"):format(modpath))
		else
			filepath = AVPath.norm(filepath)
			if self.required_files[filepath] == nil then
				local cache_dir = AVPath.join{self.multiproject.project_path, "_build", "cache"}
				lfs.mkdir(cache_dir)
				local cache_name = filepath:gsub("_", "__"):gsub(":", "_"):gsub("[\\/]", "_") .. ".msgpack"
				local cache_path = AVPath.join{cache_dir, cache_name}
				---@type ASTNodeSource
				local ast
				if AVPath.exists(cache_path) and lfs.attributes(filepath, "modification") < lfs.attributes(cache_path, "modification") then
					print_info(("Cache read '%s'"):format(filepath_local))
					local packed = Utils.readFile(cache_path, true)
					local ok, unpacked = pcall(MessagePack.unpack, packed)
					if ok then
						ast = unpacked
						ast.calcline = Parser._source_calcline
					else
						print_warn("Failed to load cached AST: " .. tostring(unpacked))
						pcall(os.remove, cache_path)
					end
				end
				if ast == nil then
					print_info(("Parsing '%s'"):format(filepath_local))
					local errors, comments
					ast, errors, comments = self.parser:parse(Utils.readFile(filepath), filepath)
					if #errors > 0 then
						print_error("-- Parse Errors: " .. #errors .. " --")
						for _, v in ipairs(errors) do
							print_error(v.id .. ": " .. v.msg)
						end
						self.required_files[filepath] = false
						return node
					end
					local cpy = Utils.shallowcopy(ast)
					cpy._avcalcline = nil
					cpy.calcline = nil
					local packed = MessagePack.pack(cpy)
					Utils.writeFile(cache_path, packed, true)
				end
				self:_add_require(
					call_node,
					ASTNodes["function"](ast, ASTNodes.funcbody(ast, ASTNodes.expressionlist(ast, ASTNodes.var_args(ast)), ast)),
					modpath,
					filepath_local
				)
				self.required_files[filepath] = ast
				-- Done last to ensure no recursive issues.
				self:visit(ast)
			end
			return node
		end
	end
	return node
end


return TransformerDefs
