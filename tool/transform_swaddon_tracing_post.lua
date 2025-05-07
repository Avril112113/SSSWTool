local modpath = ...

local AvPath = require "avpath"

local Utils = require "SelenScript.utils"
local ASTNodes = require "SelenScript.parser.ast_nodes"
local AST = require "SelenScript.parser.ast"

---@diagnostic disable-next-line: param-type-mismatch
local TRACING_PREFIX_SRC_FILE = AvPath.join{package.searchpath(modpath, package.path), "../src/tracing.lua"}


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
		self._SWAddon_TracingBlock = ASTNodes.block{_parent = source}
		local ast, errors, comments = self.parser:parse(Utils.readFile(TRACING_PREFIX_SRC_FILE), "<SSSWTOOL>/src/tracing.lua")
		if #errors > 0 then
			print_error("-- Parse Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error(v.id .. ": " .. v.msg)
			end
			os.exit(-1)
		end
		local block = self._SWAddon_TracingBlock
		table.insert(block, #block+1, ASTNodes.LineComment{_parent = source, prefix = "--", value = "#region SSSWTool-Tracing-src"})
		table.insert(block, #block+1, ast)
		table.insert(block, #block+1, ASTNodes.assign{
			_parent = node, scope = nil,
			names = ASTNodes.varlist{_parent = node, ASTNodes.index{
				_parent = node, how = nil, expr = ASTNodes.name{_parent = node, name = SPECIAL_NAME},
				index = ASTNodes.index{
					_parent = node, how = ".", expr = ASTNodes.name{_parent = node, name = "level"}
				}
			}},
			values = ASTNodes.expressionlist{_parent = node, ASTNodes.string{_parent = node, value = self.config == "full" and "full" or "simple"}}
		})
		table.insert(block, #block+1, ASTNodes.LineComment{_parent = source, prefix = "--", value = "#endregion"})
		table.insert(block, #block+1, ASTNodes.LineComment{_parent = source, prefix = "--", value = "#region SSSWTool-Tracing-info"})
		table.insert(block, #block+1, ASTNodes.LineComment{_parent = source, prefix = "--", value = "#endregion"})
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
	table.insert(self._SWAddon_TracingBlock, #self._SWAddon_TracingBlock, ASTNodes.assign{
		_parent = node, scope = nil,
		names = ASTNodes.varlist{_parent = node, ASTNodes.index{
			_parent = node, how = nil, expr = ASTNodes.name{_parent = node, name = SPECIAL_NAME},
			index = ASTNodes.index{
				_parent = node, how = ".", expr = ASTNodes.name{_parent = node, name = "_info"},
				index = ASTNodes.index{_parent = node, how = "[", expr = trace_info.swdbg_id_node}
			}
		}},
		values = ASTNodes.expressionlist{_parent = node, ASTNodes.table{_parent = node, fields = ASTNodes.fieldlist{_parent = node,
			ASTNodes.field{_parent = node, key = ASTNodes.string{_parent = node, value = "name"}, value = ASTNodes.string{_parent = node, value = Utils.escape_escape_sequences(trace_info.name)}},
			ASTNodes.field{_parent = node, key = ASTNodes.string{_parent = node, value = "line"}, value = ASTNodes.numeral{_parent = node, value = tostring(trace_info.start_line)}},
			ASTNodes.field{_parent = node, key = ASTNodes.string{_parent = node, value = "column"}, value = ASTNodes.numeral{_parent = node, value = tostring(trace_info.start_column)}},
			ASTNodes.field{_parent = node, key = ASTNodes.string{_parent = node, value = "file"}, value = ASTNodes.string{_parent = node, value = trace_info.local_file_path}}
		}}}
	})
end

---@param node SelenScript.ASTNodes.Node
---@return SelenScript.ASTNodes.block
function TransformerDefs:_generate_onTick_code(node)
	return ASTNodes.block{_parent = node,
			ASTNodes.index{
				_parent = node, how = nil, expr = ASTNodes.name{_parent = node, name = SPECIAL_NAME},
				index = ASTNodes.index{
					_parent = node, how = ".", expr = ASTNodes.name{_parent = node, name = "check_stack"},
					index = ASTNodes.call{_parent = node, args = ASTNodes.expressionlist{_parent = node, ASTNodes.index{
						_parent = node, how = nil, expr = ASTNodes.name{_parent = node, name = SPECIAL_NAME},
						index = ASTNodes.index{
							_parent = node, how = ".", expr = ASTNodes.name{_parent = node, name = "expected_stack_onTick"}
						}
					}}}
				}
			},
			ASTNodes.index{
				_parent = node, how = nil, expr = ASTNodes.name{_parent = node, name = SPECIAL_NAME},
				index = ASTNodes.index{
					_parent = node, how = ".", expr = ASTNodes.name{_parent = node, name = "_sendCheckStackHttp"},
					index = ASTNodes.call{_parent = node, args = ASTNodes.expressionlist{_parent = node}}
				}
			}
		}
end

---@param node SelenScript.ASTNodes.Node
---@return SelenScript.ASTNodes.if
function TransformerDefs:_generate_httpReply_code(node)
	return ASTNodes["if"]{
			_parent = node,
			condition = ASTNodes.index{
				_parent = node, how = nil, expr = ASTNodes.name{_parent = node, name = SPECIAL_NAME},
				index = ASTNodes.index{
					_parent = node, how = ".", expr = ASTNodes.name{_parent = node, name = "_handleHttp"},
					index = ASTNodes.call{_parent = node, args = ASTNodes.expressionlist{_parent = node, ASTNodes.var_args{_parent = node}}}
				}
			},
			block = ASTNodes.block{_parent = node, ASTNodes["return"]{_parent = node, values = ASTNodes.expressionlist{_parent = node}}}
		}
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
			table.insert(block, ASTNodes.assign{
				_parent = block, scope = nil,
				names = ASTNodes.varlist{_parent = block, ASTNodes.index{_parent = block, how = nil, expr = ASTNodes.name{_parent = block, name = "onTick"}}},
				values = ASTNodes.expressionlist{_parent = block, ASTNodes["function"]{_parent = block, funcbody = ASTNodes.funcbody{_parent = block,
					args = ASTNodes.parlist{_parent = block, ASTNodes.var_args{_parent = block}},
					block = ASTNodes.block{_parent = block, self:_generate_onTick_code(block)}
				}}}
			})
			root_source._has_onTick = true
		end
		if not root_source._has_httpReply then
			print_info("Missing httpReply callback, one has been created for tracing.")
			table.insert(block, ASTNodes.assign{
				_parent = block, how = nil,
				names = ASTNodes.varlist{_parent = block, ASTNodes.index{_parent = block, how = nil, expr = ASTNodes.name{_parent = block, name = "httpReply"}}},
				values = ASTNodes.expressionlist{_parent = block, ASTNodes["function"]{_parent = block, funcbody = ASTNodes.funcbody{_parent = block,
					args = ASTNodes.parlist{_parent = block, ASTNodes.var_args{_parent = block}},
					block = ASTNodes.block{_parent = block, self:_generate_httpReply_code(block)}
				}}}
			})
			root_source._has_httpReply = true
		end
	end
	return node
end


return TransformerDefs
