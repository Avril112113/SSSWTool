local Utils = require "SelenScript.utils"
local ASTHelpers = require "SelenScript.transformer.ast_helpers"
local ASTNodes = ASTHelpers.Nodes


---@class Transformer_Lua_to_SWAddon : Transformer
---@field parser Parser
---@field addon_dir string
local TransformerDefs = {}


---@param node ASTNode
function TransformerDefs:index(node)
	local call_node = node.index
	if node.type == "index" and node.expr.name == "require" and #call_node.args == 1 and call_node.args[1].type == "string" then
		local modpath = call_node.args[1].value:match("^[\"'](.*)[\"']$")
		local filepath, err = package.searchpath(modpath, ("%s/?.lua;%s/?/init.lua;"):format(self.addon_dir, self.addon_dir))
		self.required_files = self.required_files or {}
		if err or not filepath then
			print_error(("Failed to find '%s'%s"):format(modpath, err))
			return ASTNodes.LongComment(node, nil, ("Failed to find '%s'"):format(modpath))
		elseif not self.required_files[filepath] then
			self.required_files[filepath] = true
			print_info(("Parsing '%s'"):format(filepath:gsub("^"..Utils.escape_pattern(self.addon_dir).."/?", "")))
			local ast, errors, comments = self.parser:parse(Utils.readFile(filepath), filepath)
			if #errors > 0 then
				print_error("-- Parse Errors: " .. #errors .. " --")
				for _, v in ipairs(errors) do
					print_error(v.id .. ": " .. v.msg)
				end
				os.exit(-1)
			end
			self:visit(ast)
			return ast
		end
	end
	return node
end


-- local SPECIAL_NAME = "SS_SW_DBG"

-- ---@param node ASTNode
-- ---@param id integer
-- ---@param is_recur boolean?
-- local function recur_fill_in_custom_funcs(node, id, is_recur)
-- 	if node.type == "index" and node.expr.name == SPECIAL_NAME and node.index and node.index.expr.name == "get_my_info" then
-- 		local call = node.index.index
-- 		if call.type == "index" then
-- 			call = (call.expr.type == "call" and call.expr) or (call.index.type == "call" and call.index)
-- 		end
-- 		if not call or call.type ~= "call" then
-- 			return
-- 		end
-- 		if #call.args <= 0 then
-- 			table.insert(call.args, #call.args+1, ASTNodes.numeral(node, tostring(id)))
-- 		end
-- 	elseif is_recur == nil or node.type ~= "funcbody" then
-- 		for i, v in pairs(node) do
-- 			if type(v) == "table" and v.type ~= nil then
-- 				recur_fill_in_custom_funcs(v, id, true)
-- 			end
-- 		end
-- 	end
-- end

-- ---@param node ASTNode
-- ---@param exit_node ASTNode
-- ---@param is_recur boolean?
-- local function recur_add_exit_node(node, exit_node, is_recur)
-- 	if node.type == "return" then
-- 		table.insert(node.values, #node.values+1, exit_node)
-- 		return true
-- 	elseif is_recur == nil or node.type ~= "funcbody" then
-- 		local added_exit_node = false
-- 		for i, v in pairs(node) do
-- 			if type(v) == "table" and v.type ~= nil then
-- 				added_exit_node = recur_add_exit_node(v, exit_node, true) or added_exit_node
-- 			end
-- 		end
-- 		return added_exit_node
-- 	end
-- 	return false
-- end

-- ---@param node ASTNode
-- function TransformerDefs:funcbody(node)
-- 	---@type ASTNodeSource?
-- 	local source_node = self:find_parent_of_type(node, "source")
-- 	assert(source_node ~= nil, "source_node ~= nil")
-- 	local start_line, start_column = relabel.calcline(source_node.source, node.start)

-- 	local name
-- 	local parent_node = self:get_parent(node)
-- 	if parent_node.type == "functiondef" then
-- 		name = emitter:generate(parent_node.name)
-- 		if name:sub(1, #SPECIAL_NAME) == SPECIAL_NAME then
-- 			return node
-- 		end
-- 	elseif parent_node.type == "function" then
-- 		local parent_expressionlist_node = self:get_parent(parent_node)
-- 		if parent_expressionlist_node and parent_expressionlist_node.type == "expressionlist" then
-- 			local parent_assign_node = self:get_parent(parent_expressionlist_node)
-- 			if parent_assign_node and parent_assign_node.type == "assign" then
-- 				local index = Utils.find_key(parent_expressionlist_node, parent_node)
-- 				local name_node = parent_assign_node.names[index]
-- 				if name_node then
-- 					name = emitter:generate(name_node)
-- 				end
-- 			end
-- 		end
-- 	end
-- 	self._swdbg_index = self._swdbg_index and self._swdbg_index + 1 or 1
-- 	if name == nil then
-- 		name = "anonymous:"..self._swdbg_index
-- 	end
-- 	local source_block_index = 1
-- 	for i, v in ipairs(source_node.block.block) do
-- 		if v.type == "assign" then
-- 			local name_index = v.names[1]
-- 			if
-- 				name_index.expr and name_index.expr.name == "SS_SW_DBG" and
-- 				name_index.index and name_index.index.expr and name_index.index.expr.name == "_info"
-- 			then
-- 				source_block_index = i + 1
-- 			end
-- 		end
-- 	end
-- 	table.insert(source_node.block.block, source_block_index, ASTNodes.assign(
-- 		node, nil,
-- 		ASTNodes.namelist(node, ASTNodes.index(
-- 			node, nil, ASTNodes.name(node, SPECIAL_NAME),
-- 			ASTNodes.index(
-- 				node, ".", ASTNodes.name(node, "_info"),
-- 				ASTNodes.index(node, "[", ASTNodes.numeral(node, tostring(self._swdbg_index)))
-- 			)
-- 		)),
-- 		ASTNodes.expressionlist(node, ASTNodes.table(node, ASTNodes.fieldlist(node,
-- 			ASTNodes.field(node, ASTNodes.string(node, "name", true), ASTNodes.string(node, name, true)),
-- 			ASTNodes.field(node, ASTNodes.string(node, "line", true), ASTNodes.numeral(node, tostring(start_line))),
-- 			ASTNodes.field(node, ASTNodes.string(node, "column", true), ASTNodes.numeral(node, tostring(start_column)))
-- 		)))
-- 	))
-- 	table.insert(node.block, 1,
-- 		ASTNodes.index(
-- 			node, nil, ASTNodes.name(node, SPECIAL_NAME),
-- 			ASTNodes.index(
-- 				node, ".", ASTNodes.name(node, "_trace_enter"),
-- 				ASTNodes.call(
-- 					node, ASTNodes.expressionlist(
-- 						node,
-- 						ASTNodes.numeral(node, tostring(self._swdbg_index))
-- 					)
-- 				)
-- 			)
-- 		)
-- 	)
-- 	local exit_node_call = ASTNodes.index(
-- 		node, nil, ASTNodes.name(node, SPECIAL_NAME),
-- 		ASTNodes.index(
-- 			node, ".", ASTNodes.name(node, "_trace_exit"),
-- 			ASTNodes.call(
-- 				node, ASTNodes.expressionlist(
-- 					node,
-- 					ASTNodes.numeral(node, tostring(self._swdbg_index))
-- 				)
-- 			)
-- 		)
-- 	)
-- 	if not recur_add_exit_node(node.block, exit_node_call) then
-- 		table.insert(node.block, #node.block+1, exit_node_call)
-- 	end

-- 	-- recur_fill_in_custom_funcs(node, self._swdbg_index)
	
-- 	return node
-- end


return TransformerDefs
