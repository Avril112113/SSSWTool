local modpath = ...

local AVPath = require "avpath"

local Utils = require "SelenScript.utils"
local ASTNodes = require "SelenScript.parser.ast_nodes"
local AST = require "SelenScript.parser.ast"  -- Used for debugging.

---@diagnostic disable-next-line: param-type-mismatch
local REQUIRE_SRC_FILE = AVPath.join{package.searchpath(modpath, package.path), "../src/require.lua"}


---@class SSSWTool.Transformer_Combiner : SSSWTool.Transformer
---@field required_files table<string,SelenScript.ASTNodes.Source|false>
local TransformerDefs = {}


---@param node SelenScript.ASTNodes.Node
---@return SelenScript.ASTNodes.Source?
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
	---@cast source SelenScript.ASTNodes.Source
	return source.type == "source" and source or nil
end

---@param node SelenScript.ASTNodes.Node
---@param func_node SelenScript.ASTNodes.function
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

		block = ASTNodes.block{_parent = source,
			ASTNodes.LineComment{_parent = source, prefix = "--", value = "#region SSSWTool-Require-src"},
			require_src_ast,
			ASTNodes.LineComment{_parent = source, prefix = "--", value = "#endregion"}
		}
		self._SWAddon_RequiresBlock = block
		table.insert(source.block.block, 1, block)
	end
	block = block or self._SWAddon_RequiresBlock
	-- Using +1 to be below the `--#endregion` comment
	-- Assign to __SSSWTOOL_MOD_TO_FILEPATH
	table.insert(block, #block+1, ASTNodes.assign{_parent = source, scope = nil,
		names = ASTNodes.varlist{_parent = source, ASTNodes.index{_parent = source, how = nil, expr = ASTNodes.name{_parent = source, name = "__SSSWTOOL_MOD_TO_FILEPATH"}, index = ASTNodes.index{_parent = source, how = "[", expr = ASTNodes.string{_parent = source, value = modpath}}}},
		values = ASTNodes.expressionlist{_parent = source, ASTNodes.string{_parent = source, value = filepath}}
	})
	-- Assign to __SSSWTOOL_REQUIRES
	table.insert(block, #block+1, ASTNodes.assign{_parent = source, scope = nil,
		names = ASTNodes.varlist{_parent = source, ASTNodes.index{_parent = source, how = nil, expr = ASTNodes.name{_parent = source, name = "__SSSWTOOL_REQUIRES"}, index = ASTNodes.index{_parent = source, how = "[", expr = ASTNodes.string{_parent = source, value = modpath}}}},
		values = ASTNodes.expressionlist{_parent = source, func_node}
	})
end


---@param node SelenScript.ASTNodes.index
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
		---@cast call_node SelenScript.ASTNodes.call
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
			return ASTNodes.LongComment{_parent = node, value = ("Failed to find '%s'"):format(modpath)}
		else
			filepath = AVPath.norm(filepath)
			if self.required_files[filepath] == nil then
				local ast, comments, errors = self.project:parse_file(self.parser, self.buildactions, filepath)
				if not ast then error(("Failed to parse '%s'"):format(filepath)) end
				---@cast ast SelenScript.ASTNodes.block # Temporary conversion
				self:_add_require(
					call_node,
					ASTNodes["function"]{_parent = ast, funcbody = ASTNodes.funcbody{_parent = ast,
						args = ASTNodes.parlist{_parent = ast, ASTNodes.var_args{_parent = ast}},
						block = ASTNodes.block{_parent = ast, ast}
					}},
					modpath,
					filepath_local
				)
				---@cast ast SelenScript.ASTNodes.Source
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
