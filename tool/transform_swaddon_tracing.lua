local modpath = ...

local AVPath = require "avpath"

local Utils = require "SelenScript.utils"
local ASTHelpers = require "SelenScript.transformer.ast_helpers"
local relabel = require "relabel"
local ASTNodes = ASTHelpers.Nodes
local Emitter = require "SelenScript.emitter.emitter"
local AST = require "SelenScript.parser.ast"

---@diagnostic disable-next-line: param-type-mismatch
local TRACING_PREFIX_SRC_FILE = AVPath.join{package.searchpath(modpath, package.path), "../src/tracing.lua"}


--- Used for converting AST nodes into strings
local emitter = Emitter.new("lua", {})

local SPECIAL_NAME = "SS_SW_DBG"

---@class SSSWTool.Transformer_Tracing : SSSWTool.Transformer
local TransformerDefs = {}


---@param node SelenScript.ASTNode
---@return SelenScript.ASTNodeSource?
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

---@param node SelenScript.ASTNode
---@return SelenScript.ASTNodeSource
function TransformerDefs:_ensure_tracingblock(node)
	local source = self:_get_root_source(node)
	assert(source ~= nil, "source ~= nil")
	if not self._SWAddon_TracingBlock then
		self._SWAddon_TracingBlock = ASTNodes.block(source)
		local ast, errors, comments = self.parser:parse(Utils.readFile(TRACING_PREFIX_SRC_FILE), "<SSSWTOOL>/src/tracing.lua")
		if #errors > 0 then
			print_error("-- Parse Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error(v.id .. ": " .. v.msg)
			end
			os.exit(-1)
		end
		local block = self._SWAddon_TracingBlock
		table.insert(block, #block+1, ASTNodes.LineComment(source, "--", "#region SSSWTool-Tracing-src"))
		table.insert(block, #block+1, ast)
		table.insert(block, #block+1, ASTNodes.assign(
			node, nil,
			ASTNodes.varlist(node, ASTNodes.index(
				node, nil, ASTNodes.name(node, SPECIAL_NAME),
				ASTNodes.index(
					node, ".", ASTNodes.name(node, "level")
				)
			)),
			ASTNodes.expressionlist(node, ASTNodes.string(node, self.config == "full" and "full" or "simple"))
		))
		table.insert(block, #block+1, ASTNodes.LineComment(source, "--", "#endregion"))
		table.insert(block, #block+1, ASTNodes.LineComment(source, "--", "#region SSSWTool-Tracing-info"))
		table.insert(block, #block+1, ASTNodes.LineComment(source, "--", "#endregion"))
		table.insert(source.block.block, 1, block)
	end
	return source
end

---@param node SelenScript.ASTNode
---@param name string
---@param start_line integer
---@param start_column integer
---@param local_file_path string
function TransformerDefs:_add_trace_info(node, name, start_line, start_column, local_file_path)
	self:_ensure_tracingblock(node)
	-- Omitted +1 to be above the `--#endregion` comment
	table.insert(self._SWAddon_TracingBlock, #self._SWAddon_TracingBlock, ASTNodes.assign(
		node, nil,
		ASTNodes.varlist(node, ASTNodes.index(
			node, nil, ASTNodes.name(node, SPECIAL_NAME),
			ASTNodes.index(
				node, ".", ASTNodes.name(node, "_info"),
				ASTNodes.index(node, "[", ASTNodes.numeral(node, tostring(self._swdbg_index)))
			)
		)),
		ASTNodes.expressionlist(node, ASTNodes.table(node, ASTNodes.fieldlist(node,
			ASTNodes.field(node, ASTNodes.string(node, "name"), ASTNodes.string(node, Utils.escape_escape_sequences(name))),
			ASTNodes.field(node, ASTNodes.string(node, "line"), ASTNodes.numeral(node, tostring(start_line))),
			ASTNodes.field(node, ASTNodes.string(node, "column"), ASTNodes.numeral(node, tostring(start_column))),
			ASTNodes.field(node, ASTNodes.string(node, "file"), ASTNodes.string(node, local_file_path))
		)))
	))
end


---@param node SelenScript.ASTNodeSource
function TransformerDefs:source(node)
	local root_source = assert(self:_get_root_source(node), "root_source_node ~= nil")
	self:_ensure_tracingblock(root_source)
	-- Transforming is depth-first.
	-- So, if `node == root_source` then we have finish transforming everything and can check if onTick or httpReply is missing.
	if node == root_source then
		local block = self._SWAddon_TracingBlock
		if not root_source._has_onTick then
			print_info("Missing onTick callback, one has been created for tracing.")
			table.insert(block, ASTNodes.assign(
				block, nil,
				ASTNodes.varlist(block, ASTNodes.index(block, nil, ASTNodes.name(block, "onTick"))),
				ASTNodes.expressionlist(block, ASTNodes["function"](block, ASTNodes.funcbody(block,
					ASTNodes.parlist(block, ASTNodes.var_args(block)),
					ASTNodes.block(block, self:_generate_onTick_code(block))
				)))
			))
			root_source._has_onTick = true
		end
		if not root_source._has_httpReply then
			print_info("Missing httpReply callback, one has been created for tracing.")
			table.insert(block, ASTNodes.assign(
				block, nil,
				ASTNodes.varlist(block, ASTNodes.index(block, nil, ASTNodes.name(block, "httpReply"))),
				ASTNodes.expressionlist(block, ASTNodes["function"](block, ASTNodes.funcbody(block,
					ASTNodes.parlist(block, ASTNodes.var_args(block)),
					ASTNodes.block(block, self:_generate_httpReply_code(block))
				)))
			))
			root_source._has_httpReply = true
		end
	end
	return node
end

---@param node SelenScript.ASTNode
---@return SelenScript.ASTNode
function TransformerDefs:_generate_onTick_code(node)
	return ASTNodes.block(node,
			ASTNodes.index(
				node, nil, ASTNodes.name(node, SPECIAL_NAME),
				ASTNodes.index(
					node, ".", ASTNodes.name(node, "check_stack"),
					ASTNodes.call(node, ASTNodes.expressionlist(node, ASTNodes.index(
						node, nil, ASTNodes.name(node, SPECIAL_NAME),
						ASTNodes.index(
							node, ".", ASTNodes.name(node, "expected_stack_onTick")
						)
					)))
				)
			),
			ASTNodes.index(
				node, nil, ASTNodes.name(node, SPECIAL_NAME),
				ASTNodes.index(
					node, ".", ASTNodes.name(node, "_sendCheckStackHttp"),
					ASTNodes.call(node, ASTNodes.expressionlist(node))
				)
			)
		)
end

---@param node SelenScript.ASTNode
---@return SelenScript.ASTNode
function TransformerDefs:_generate_httpReply_code(node)
	return ASTNodes["if"](
			node,
			ASTNodes.index(
				node, nil, ASTNodes.name(node, SPECIAL_NAME),
				ASTNodes.index(
					node, ".", ASTNodes.name(node, "_handleHttp"),
					ASTNodes.call(node, ASTNodes.var_args(node))
				)
			),
			ASTNodes.block(node, ASTNodes["return"](node, ASTNodes.expressionlist(node)))
		)
end

---@param node SelenScript.ASTNode
function TransformerDefs:funcbody(node)
	if node._is_traced then
		return node
	end
	node._is_traced = true

	---@type SelenScript.ASTNodeSource
	local root_source = assert(self:_get_root_source(node), "root_source ~= nil")

	---@type SelenScript.ASTNodeSource
	local source = assert(self:find_parent_of_type(node, "source"), "parent source node ~= nil")
	local start_line, start_column = source:calcline(node.start)

	---@type SelenScript.ASTNode?
	local prepend_node
	local name
	local parent_node = self:get_parent(node)
	if parent_node.type == "functiondef" then
		name = emitter:generate(parent_node.name)
		if name:sub(1, #SPECIAL_NAME) == SPECIAL_NAME then
			return node
		elseif parent_node.scope ~= "local" then
			if name == "onTick" then
				prepend_node = self:_generate_onTick_code(node)
				root_source._has_onTick = true
			elseif name == "httpReply" then
				prepend_node = self:_generate_httpReply_code(node)
				root_source._has_httpReply = true
			end
		end
	elseif parent_node.type == "function" then
		local parent_expressionlist_node = self:get_parent(parent_node)
		if parent_expressionlist_node and parent_expressionlist_node.type == "expressionlist" then
			local parent_assign_node = self:get_parent(parent_expressionlist_node)
			if parent_assign_node and parent_assign_node.type == "assign" then
				local index = Utils.find_key(parent_expressionlist_node, parent_node)
				local name_node = parent_assign_node.names[index]
				if name_node then
					name = emitter:generate(name_node)
					if parent_assign_node.scope ~= "local" then
						if name == "onTick" then
							prepend_node = self:_generate_onTick_code(node)
							root_source._has_onTick = true
						elseif name == "httpReply" then
							prepend_node = self:_generate_httpReply_code(node)
							root_source._has_httpReply = true
						end
					end
				end
			end
		end
	end
	self._swdbg_index = self._swdbg_index and self._swdbg_index + 1 or 1
	if name == nil then
		name = "anonymous:"..self._swdbg_index
	end
	local local_source_node = self:find_parent_of_type(node, "source")
	assert(local_source_node ~= nil, "local_source_node ~= nil")
	local local_file_path = "<UNKNOWN>"
	if local_source_node.file then
		if local_source_node.file:find("^<SSSWTOOL>[\\/]") then
			local_file_path = AVPath.norm(local_source_node.file)
		else
			local_file_path = AVPath.relative(local_source_node.file, self.multiproject.project_path)
		end
	end
	self:_add_trace_info(node, name, start_line, start_column, local_file_path:gsub("<", "{"):gsub(">", "}"))

	local newblock = ASTNodes.block(node,
		ASTNodes["return"](node, ASTNodes.expressionlist(
			node,
			ASTNodes.index(
				node, nil, ASTNodes.name(node, SPECIAL_NAME),
				ASTNodes.index(
					node, ".", ASTNodes.name(node, "_trace_func"),
					ASTNodes.call(
						node, ASTNodes.expressionlist(
							node,
							ASTNodes.numeral(node, tostring(self._swdbg_index)),
							ASTNodes["function"](node, node),
							ASTNodes.var_args(node)
						)
					)
				)
			)
		))
	)
	if prepend_node then
		table.insert(newblock, 1, prepend_node)
	end
	return ASTNodes.funcbody(
		node,
		ASTNodes.varlist(node, ASTNodes.var_args(node)),
		newblock
	)
end

local WHITELIST_STMT_TYPES = {
	["assign"]=true,
	["index"]=true,
}
---@param node SelenScript.ASTNode
function TransformerDefs:block(node)
	if self.config ~= "full" then
		return node
	end
	if node._is_traced then
		return node
	end
	node._is_traced = true

	if self:_get_root_source(node).block.block == node then
		return node
	end

	---@type SelenScript.ASTNodeSource
	local source = assert(self:find_parent_of_type(node, "source"), "parent source node ~= nil")

	for i=#node,1,-1 do
		local child = node[i]
		if not WHITELIST_STMT_TYPES[child.type] then
			goto continue
		end
		local start_line, start_column = source:calcline(child.start)
		local local_file_path = "<UNKNOWN>"
		if source.file then
			if source.file:find("^<SSSWTOOL>[\\/]") then
				local_file_path = AVPath.norm(source.file)
			else
				local_file_path = AVPath.relative(source.file, self.multiproject.project_path)
			end
		end
		self._swdbg_index = self._swdbg_index and self._swdbg_index + 1 or 1
		local name = "stmt_"..child.type
		if child.type == "index" then
			name = emitter:generate(child)
			if name:find("\n") then
				name = name:match("(.-)\n")
			end
		elseif child.type == "assign" then
			local cpy = Utils.shallowcopy(child)
			cpy.values = ASTNodes.expressionlist(child)
			name = emitter:generate(cpy) .. " ="
		end
		self:_add_trace_info(node, ("`%s`"):format(name), start_line, start_column, local_file_path:gsub("<", "{"):gsub(">", "}"))
		table.insert(node, i+1, ASTNodes.index(
			node, nil, ASTNodes.name(node, SPECIAL_NAME),
			ASTNodes.index(
				node, ".", ASTNodes.name(node, "_trace_exit"),
				ASTNodes.call(
					node, ASTNodes.expressionlist(
						node,
						ASTNodes.numeral(node, tostring(self._swdbg_index))
					)
				)
			)
		))
		table.insert(node, i, ASTNodes.index(
			node, nil, ASTNodes.name(node, SPECIAL_NAME),
			ASTNodes.index(
				node, ".", ASTNodes.name(node, "_trace_enter"),
				ASTNodes.call(
					node, ASTNodes.expressionlist(
						node,
						ASTNodes.numeral(node, tostring(self._swdbg_index))
					)
				)
			)
		))
		::continue::
	end

	return node
end


return TransformerDefs
