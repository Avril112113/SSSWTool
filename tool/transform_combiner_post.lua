local modpath = ...

local AVPath = require "avpath"

local Utils = require "SelenScript.utils"
local ASTNodes = require "SelenScript.parser.ast_nodes"
local AST = require "SelenScript.parser.ast"  -- Used for debugging.
local PoolWorkerContext = require "avlanesutils.pool_worker_context"

---@diagnostic disable-next-line: param-type-mismatch
local REQUIRE_SRC_FILE = AVPath.join{package.searchpath(modpath, package.path), "../src/require.lua"}


---@class SSSWTool.Transformer_Combiner : SSSWTool.Transformer
---@field _required_files table<string, AvLanesUtils.Pool.WorkId|SelenScript.ASTNodes.Source>
---@field _file_info table<string, SSSWTool.Transformer_Combiner_File.FileInfo>
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

---@param ast SelenScript.ASTNodes.Source
---@param func_node SelenScript.ASTNodes.function
---@param modpath string
---@param filepath string
function TransformerDefs:_add_require(ast, func_node, modpath, filepath)
	local source = self:_get_root_source(ast)
	if source == nil then error("Missing source node.") end
	local block
	if not self._SWAddon_RequiresBlock then
		local require_src_ast, errors, comments = self.parser_factory():parse(Utils.readFile(REQUIRE_SRC_FILE), "<SSSWTOOL>/src/require.lua")
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
			ASTNodes.LineComment{_parent = source, prefix = "--", value = "#endregion"},
			ASTNodes.block{_parent = source}
		}
		self._SWAddon_RequiresBlock = block
		table.insert(source.block.block, 1, block)
	end
	block = block or self._SWAddon_RequiresBlock
	local requires_block = block[#block]
	---@cast requires_block SelenScript.ASTNodes.block
	
	local insert_pos = 1
	-- for i,v in ipairs(requires_block) do
	-- 	insert_pos = i+2
	-- 	if v.type == "assign" and v.values[1].type == "string" then
	-- 		if v.values[1].value < filepath then
	-- 			break
	-- 		end
	-- 	end
	-- end
	-- print(insert_pos, filepath)
	
	-- Assign to __SSSWTOOL_MOD_TO_FILEPATH
	table.insert(requires_block, insert_pos, ASTNodes.assign{_parent = source, scope = nil,
		names = ASTNodes.varlist{_parent = source, ASTNodes.index{_parent = source, how = nil, expr = ASTNodes.name{_parent = source, name = "__SSSWTOOL_MOD_TO_FILEPATH"}, index = ASTNodes.index{_parent = source, how = "[", expr = ASTNodes.string{_parent = source, value = modpath}}}},
		values = ASTNodes.expressionlist{_parent = source, ASTNodes.string{_parent = source, value = filepath}}
	})
	-- Assign to __SSSWTOOL_REQUIRES
	table.insert(requires_block, insert_pos+1, ASTNodes.assign{_parent = source, scope = nil,
		names = ASTNodes.varlist{_parent = source, ASTNodes.index{_parent = source, how = nil, expr = ASTNodes.name{_parent = source, name = "__SSSWTOOL_REQUIRES"}, index = ASTNodes.index{_parent = source, how = "[", expr = ASTNodes.string{_parent = source, value = modpath}}}},
		values = ASTNodes.expressionlist{_parent = source, func_node}
	})

	table.sort(requires_block, function(a, b)
		local aname = a.names[1].index.expr.value
		local bname = b.names[1].index.expr.value
		if aname == bname then
			return a.names[1].expr.name < b.names[1].expr.name
		end
		return aname < bname
	end)
end

---@param node SelenScript.ASTNodes.Source
function TransformerDefs:source(node)
	self._required_files = self._required_files or {}
	self._file_info = self._file_info or {}
	if node._required_paths then
		for file_path, file_info in pairs(node._required_paths) do
			if not self._required_files[file_path] then
				self._required_files[file_path] = self.project:parse_file_future(self.parser_factory, file_path)
				self._file_info[file_path] = file_info
			end
		end
	end
	for file_path, work_id in pairs(self._required_files) do
		if type(work_id) == "number" then
			local file_ast, file_comments, file_errors = PoolWorkerContext.work_await(work_id)
			if not file_ast then error(("Failed to parse '%s'"):format(file_path)) end
			self._required_files[file_path] = file_ast
			local file_path_local, modpath = unpack(self._file_info[file_path])
			self:_add_require(
				node,
				ASTNodes["function"]{_parent = file_ast, funcbody = ASTNodes.funcbody{_parent = file_ast,
					args = ASTNodes.parlist{_parent = file_ast, ASTNodes.var_args{_parent = file_ast}},
					block = ASTNodes.block{_parent = file_ast, file_ast}
				}},
				modpath,
				file_path_local
			)
			self:visit(file_ast)
		end
	end
	return node
end

-- ---@param ast SelenScript.ASTNodes.Source
-- function TransformerDefs:__post_transform(ast)
-- 	print(AST.tostring_ast(ast))
-- end


return TransformerDefs
