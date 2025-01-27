local AVPath = require "avpath"

local Utils = require "SelenScript.utils"
local ASTNodes = require "SelenScript.parser.ast_nodes"
local Emitter = require "SelenScript.emitter.emitter"
local AST = require "SelenScript.parser.ast"

local TracingPostDefs = require "tool.transform_swaddon_tracing_post"


--- Used for converting AST nodes into strings
local emitter = Emitter.new("lua", {})

local SPECIAL_NAME = "SSSW_DBG"

-- AST Node class field injections

---@class SelenScript.ASTNodes.Source
---@field _has_onTick true?
---@field _has_httpReply true?
---@field _traces_info SSSWTool.Transformer_Tracing_File.TraceInfo[]?

---@class SelenScript.ASTNodes.funcbody
---@field _is_traced true?

---@class SelenScript.ASTNodes.block
---@field _is_traced true?


---@class SSSWTool.Transformer_Tracing_File.TraceInfo
---@field node SelenScript.ASTNodes.Node
---@field name string
---@field start_line integer
---@field start_column integer
---@field local_file_path string
---@field swdbg_id_node SelenScript.ASTNodes.numeral


---@class SSSWTool.Transformer_Tracing_File : SSSWTool.Transformer
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
---@param name string
---@param start_line integer
---@param start_column integer
---@param local_file_path string
function TransformerDefs:_add_trace_info(node, name, start_line, start_column, local_file_path)
	local source_node = assert(self:find_parent_of_type(node, "source"), "root_source ~= nil")
	---@cast source_node SelenScript.ASTNodes.Source
	source_node._traces_info = source_node._traces_info or {}
	local swdbg_id_node = ASTNodes.numeral{ _parent = node, value = "-1" }
	table.insert(source_node._traces_info, {
		node = node, name = name, start_line = start_line, start_column = start_column, local_file_path = local_file_path,
		swdbg_id_node = swdbg_id_node,
	})
	return swdbg_id_node
end

---@param node SelenScript.ASTNodes.funcbody
function TransformerDefs:funcbody(node)
	if node._is_traced then
		return node
	end
	node._is_traced = true

	local root_source = assert(self:_get_root_source(node), "root_source ~= nil")

	local source = assert(self:find_parent_of_type(node, "source"), "parent source node ~= nil")
	---@cast source SelenScript.ASTNodes.Source
	local start_line, start_column = source:calcline(node.start)

	---@type SelenScript.ASTNodes.Node?
	local prepend_node
	local name
	local parent_node = self:get_parent(node)
	if parent_node.type == "functiondef" then
		---@cast parent_node SelenScript.ASTNodes.functiondef
		name = emitter:generate(parent_node.name)
		if name:sub(1, #SPECIAL_NAME) == SPECIAL_NAME then
			return node
		elseif parent_node.scope ~= "local" then
			if name == "onTick" then
				prepend_node = TracingPostDefs._generate_onTick_code(self, node)
				root_source._has_onTick = true
			elseif name == "httpReply" then
				prepend_node = TracingPostDefs._generate_httpReply_code(self, node)
				root_source._has_httpReply = true
			end
		end
	elseif parent_node.type == "function" then
		---@cast parent_node SelenScript.ASTNodes.function
		local parent_expressionlist_node = self:get_parent(parent_node)
		if parent_expressionlist_node and parent_expressionlist_node.type == "expressionlist" then
			local parent_assign_node = self:get_parent(parent_expressionlist_node)
			if parent_assign_node and parent_assign_node.type == "assign" then
				---@cast parent_assign_node SelenScript.ASTNodes.assign
				local index = Utils.find_key(parent_expressionlist_node, parent_node)
				local name_node = parent_assign_node.names[index]
				if name_node then
					name = emitter:generate(name_node)
					if parent_assign_node.scope ~= "local" then
						if name == "onTick" then
							prepend_node = TracingPostDefs._generate_onTick_code(self, node)
							root_source._has_onTick = true
						elseif name == "httpReply" then
							prepend_node = TracingPostDefs._generate_httpReply_code(self, node)
							root_source._has_httpReply = true
						end
					end
				end
			end
		end
	end
	if name == nil then
		name = "anonymous:<FILL_TRACE_ID>"
	end
	local local_source_node = self:find_parent_of_type(node, "source")
	assert(local_source_node ~= nil, "local_source_node ~= nil")
	---@cast local_source_node SelenScript.ASTNodes.Source
	local local_file_path = "<UNKNOWN>"
	if local_source_node.file then
		if local_source_node.file:find("^<SSSWTOOL>[\\/]") then
			local_file_path = AVPath.norm(local_source_node.file)
		else
			local_file_path = AVPath.relative(local_source_node.file, self.multiproject.project_path)
		end
	end
	local swdbg_id_node = self:_add_trace_info(node, name, start_line, start_column, local_file_path:gsub("<", "{"):gsub(">", "}"))

	local newblock = ASTNodes.block{_parent = node,
		ASTNodes["return"]{_parent = node, values = ASTNodes.expressionlist{
			_parent = node,
			ASTNodes.index{
				_parent = node, how = nil, expr = ASTNodes.name{_parent = node, name = SPECIAL_NAME},
				index = ASTNodes.index{
					_parent = node, how = ".", expr = ASTNodes.name{_parent = node, name = "_trace_func"},
					index = ASTNodes.call{
						_parent = node, args = ASTNodes.expressionlist{
							_parent = node,
							swdbg_id_node,
							ASTNodes["function"]{_parent = node, funcbody = node},
							ASTNodes.var_args{_parent = node}
						}
					}
				}
			}
		}}
	}
	if prepend_node then
		table.insert(newblock, 1, prepend_node)
	end
	return ASTNodes.funcbody{
		_parent = node,
		args = ASTNodes.parlist{_parent = node, ASTNodes.var_args{_parent = node}},
		block = newblock
	}
end

local WHITELIST_STMT_TYPES = {
	["assign"]=true,
	["index"]=true,
}
---@param node SelenScript.ASTNodes.block
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

	local source = assert(self:find_parent_of_type(node, "source"), "parent source node ~= nil")
	---@cast source SelenScript.ASTNodes.Source

	for i=#node,1,-1 do
		local child = node[i]
		---@cast child -?
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
		local name = "stmt_"..child.type
		if child.type == "index" then
			---@cast child SelenScript.ASTNodes.index
			name = emitter:generate(child)
			if name:find("\n") then
				name = name:match("(.-)\n")
			end
		elseif child.type == "assign" then
			---@cast child SelenScript.ASTNodes.assign
			local cpy = Utils.shallowcopy(child)
			cpy.values = ASTNodes.expressionlist{_parent = child}
			name = emitter:generate(cpy) .. " ="
		end
		local swdbg_id_node = self:_add_trace_info(node, ("`%s`"):format(name), start_line, start_column, local_file_path:gsub("<", "{"):gsub(">", "}"))
		table.insert(node, i+1, ASTNodes.index{
			_parent = node, how = nil, expr = ASTNodes.name{_parent = node, name = SPECIAL_NAME},
			index = ASTNodes.index{
				_parent = node, how = ".", expr = ASTNodes.name{_parent = node, name = "_trace_exit"},
				index = ASTNodes.call{
					_parent = node, args = ASTNodes.expressionlist{
						_parent = node,
						swdbg_id_node
					}
				}
			}
		})
		table.insert(node, i, ASTNodes.index{
			_parent = node, how = nil, expr = ASTNodes.name{_parent = node, name = SPECIAL_NAME},
			index = ASTNodes.index{
				_parent = node, how = ".", expr = ASTNodes.name{_parent = node, name = "_trace_enter"},
				index = ASTNodes.call{
					_parent = node, args = ASTNodes.expressionlist{
						_parent = node,
						swdbg_id_node
					}
				}
			}
		})
		::continue::
	end

	return node
end


return TransformerDefs
