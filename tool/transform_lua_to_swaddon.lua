local modpath = ...
---@diagnostic disable-next-line: param-type-mismatch
local modfolderpath = package.searchpath(modpath, package.path):gsub("[\\/][^\\/]*$", "")
local REQUIRE_SRC_FILE = modfolderpath .. "/src/require.lua"

local Utils = require "SelenScript.utils"
local ASTHelpers = require "SelenScript.transformer.ast_helpers"
local ASTNodes = ASTHelpers.Nodes
local AST = require "SelenScript.parser.ast"  -- Used for debugging.


---@class Transformer_Lua_to_SWAddon : Transformer
---@field parser Parser
---@field addon_dir string
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
			ASTNodes.assign(source, nil,
				ASTNodes.namelist(source,
					ASTNodes.name(source, "__SSSWTOOL_REQUIRES")),
					ASTNodes.expressionlist(source, ASTNodes.table(source, ASTNodes.fieldlist(source))
				)
			),
			ASTNodes.assign(source, nil,
				ASTNodes.namelist(source,
					ASTNodes.name(source, "__SSSWTOOL_MOD_TO_FILEPATH")),
					ASTNodes.expressionlist(source, ASTNodes.table(source, ASTNodes.fieldlist(source))
				)
			),
			ASTNodes.assign(source, nil,
				ASTNodes.namelist(source,
					ASTNodes.name(source, "__SSSWTOOL_RESULTS")),
					ASTNodes.expressionlist(source, ASTNodes.table(source, ASTNodes.fieldlist(source))
				)
			),
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
		local filepath, err = package.searchpath(modpath, ("%s/?.lua;%s/?/init.lua;"):format(self.addon_dir, self.addon_dir))
		self.required_files = self.required_files or {}
		if err or not filepath then
			print_error(("Failed to find '%s'%s"):format(modpath, err))
			return ASTNodes.LongComment(node, nil, ("Failed to find '%s'"):format(modpath))
		else
			filepath = filepath:gsub("\\", "/")
			if self.required_files[filepath] == nil then
				local filepath_local = filepath:gsub("^"..Utils.escape_pattern(self.addon_dir).."/?", "")
				print_info(("Parsing '%s'"):format(filepath_local))
				local ast, errors, comments = self.parser:parse(Utils.readFile(filepath), filepath)
				if #errors > 0 then
					print_error("-- Parse Errors: " .. #errors .. " --")
					for _, v in ipairs(errors) do
						print_error(v.id .. ": " .. v.msg)
					end
					self.required_files[filepath] = false
					return node
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
