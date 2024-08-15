local modpath = ...

local AVPath = require "avpath"

local Utils = require "SelenScript.utils"
local ASTHelpers = require "SelenScript.transformer.ast_helpers"
local ASTNodes = ASTHelpers.Nodes
local AST = require "SelenScript.parser.ast"

---@diagnostic disable-next-line: param-type-mismatch
local TRACING_PREFIX_SRC_FILE = AVPath.join{package.searchpath(modpath, package.path), "../src/tracing.lua"}


local SPECIAL_NAME = "SSSW_DBG"


---@class SSSWTool.Transformer_Tracing_Post : SSSWTool.Transformer
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
---@return SelenScript.ASTNodes.Source
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

---@param trace_info SSSWTool.Transformer_Tracing_File.TraceInfo
function TransformerDefs:_add_trace_info(trace_info)
	-- self:_ensure_tracingblock(trace_info.node)
	-- Omitted +1 to be above the `--#endregion` comment
	if trace_info.swdbg_id_node.value == "-1" then
		self._sw_dbg_index = (self._sw_dbg_index and self._sw_dbg_index + 1) or 1
		trace_info.swdbg_id_node.value = tostring(self._sw_dbg_index)
	end
	local node = trace_info.node
	table.insert(self._SWAddon_TracingBlock, #self._SWAddon_TracingBlock, ASTNodes.assign(
		node, nil,
		ASTNodes.varlist(node, ASTNodes.index(
			node, nil, ASTNodes.name(node, SPECIAL_NAME),
			ASTNodes.index(
				node, ".", ASTNodes.name(node, "_info"),
				ASTNodes.index(node, "[", trace_info.swdbg_id_node)
			)
		)),
		ASTNodes.expressionlist(node, ASTNodes.table(node, ASTNodes.fieldlist(node,
			ASTNodes.field(node, ASTNodes.string(node, "name"), ASTNodes.string(node, Utils.escape_escape_sequences(trace_info.name))),
			ASTNodes.field(node, ASTNodes.string(node, "line"), ASTNodes.numeral(node, tostring(trace_info.start_line))),
			ASTNodes.field(node, ASTNodes.string(node, "column"), ASTNodes.numeral(node, tostring(trace_info.start_column))),
			ASTNodes.field(node, ASTNodes.string(node, "file"), ASTNodes.string(node, trace_info.local_file_path))
		)))
	))
end

---@param node SelenScript.ASTNodes.Node
---@return SelenScript.ASTNodes.Node
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

---@param node SelenScript.ASTNodes.Node
---@return SelenScript.ASTNodes.Node
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

---@param node SelenScript.ASTNodes.Source
function TransformerDefs:source(node)
	local root_source = assert(self:_get_root_source(node), "root_source_node ~= nil")

	root_source._has_onTick = root_source._has_onTick or node._has_onTick
	root_source._has_httpReply = root_source._has_httpReply or node._has_httpReply

	self:_ensure_tracingblock(root_source)

	if node._traces_info then
		for _, trace_info in ipairs(node._traces_info) do
			self:_add_trace_info(trace_info)
		end
	end

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


return TransformerDefs
