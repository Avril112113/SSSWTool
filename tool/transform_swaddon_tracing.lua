local modpath = ...
---@diagnostic disable-next-line: param-type-mismatch
local modfolderpath = package.searchpath(modpath, package.path):gsub("[\\/][^\\/]*$", "")
local TRACING_PREFIX_FILE = modfolderpath .. "/tracing_prefix.lua"


local Utils = require "SelenScript.utils"
local ASTHelpers = require "SelenScript.transformer.ast_helpers"
local relabel = require "relabel"
local ASTNodes = ASTHelpers.Nodes
local Emitter = require "SelenScript.emitter.emitter"
local AST = require "SelenScript.parser.ast"


--- Used for converting AST nodes into strings
local emitter = Emitter.new("lua", {})

local SPECIAL_NAME = "SS_SW_DBG"

local EVENT_HOOKS = {
	["onTick"]=1,
	-- ["onTick"]=1, ["onCreate"]=1, ["onDestroy"]=1, ["onCustomCommand"]=1, ["onChatMessage"]=1, ["httpReply"]=1,
	-- ["onPlayerJoin"]=1, ["onPlayerLeave"]=1, ["onPlayerRespawn"]=1, ["onPlayerDie"]=1, ["onPlayerSit"]=1, ["onPlayerUnsit"]=1,
	-- ["onToggleMap"]=1,
	-- ["onCharacterSit"]=1, ["onCharacterUnsit"]=1, ["onCharacterPickup"]=1,
	-- ["onCreatureSit"]=1, ["onCreatureUnsit"]=1, ["onCreaturePickup"]=1,
	-- ["onEquipmentPickup"]=1, ["onEquipmentDrop"]=1,
	-- ["onGroupSpawn"]=1, ["onVehicleSpawn"]=1, ["onVehicleDespawn"]=1, ["onVehicleLoad"]=1, ["onVehicleUnload"]=1, ["onVehicleTeleport"]=1,
	-- ["onVehicleDamaged"]=1,
	-- ["onButtonPress"]=1,
	-- ["onObjectLoad"]=1, ["onObjectUnload"]=1,
	-- ["onFireExtinguished"]=1, ["onForestFireSpawned"]=1, ["onForestFireExtinguised"]=1,
	-- ["onTornado"]=1, ["onMeteor"]=1, ["onTsunami"]=1, ["onWhirlpool"]=1, ["onVolcano"]=1, ["onOilSpill"]=1,
	-- ["onSpawnAddonComponent"]=1,
}

---@class Transformer_SWAddon_Tracing : Transformer
---@field parser Parser
---@field addon_dir string
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


---@param node ASTNodeSource
function TransformerDefs:source(node)
	local source = self:_get_root_source(node)
	---@cast source -?
	if not source._SWAddon_Tracing_HasPrefix then
		source._SWAddon_Tracing_HasPrefix = true
		local ast, errors, comments = self.parser:parse(Utils.readFile(TRACING_PREFIX_FILE), TRACING_PREFIX_FILE)
		if #errors > 0 then
			print_error("-- Parse Errors: " .. #errors .. " --")
			for _, v in ipairs(errors) do
				print_error(v.id .. ": " .. v.msg)
			end
			os.exit(-1)
		end
		table.insert(source.block.block, 1, ast)
	end
	return node
end

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


---@param node ASTNode
function TransformerDefs:_generate_check_call(node, name)
	table.insert(node.block, 1, ASTNodes.index(
		node, nil, ASTNodes.name(node, SPECIAL_NAME),
		ASTNodes.index(
			node, ".", ASTNodes.name(node, "check_stack"),
			ASTNodes.call(
				node, ASTNodes.expressionlist(
					node,
					ASTNodes.numeral(node, tostring(EVENT_HOOKS[name]))
				)
			)
		)
	))
end

---@param node ASTNode
function TransformerDefs:funcbody(node)
	---@type ASTNodeSource?
	local root_source_node = self:_get_root_source(node)
	assert(root_source_node ~= nil, "root_source_node ~= nil")
	local start_line, start_column = relabel.calcline(root_source_node.source, node.start)

	local name
	local parent_node = self:get_parent(node)
	if parent_node.type == "functiondef" then
		name = emitter:generate(parent_node.name)
		if name:sub(1, #SPECIAL_NAME) == SPECIAL_NAME then
			return node
		elseif EVENT_HOOKS[name] then
			self:_generate_check_call(node, name)
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
					if EVENT_HOOKS[name] then
						self:_generate_check_call(node, name)
					end
				end
			end
		end
	end
	self._swdbg_index = self._swdbg_index and self._swdbg_index + 1 or 1
	if name == nil then
		name = "anonymous:"..self._swdbg_index
	end
	local source_block_index = 1
	for i, v in ipairs(root_source_node.block.block) do
		if v.type == "assign" then
			local name_index = v.names[1]
			if
				name_index.expr and name_index.expr.name == "SS_SW_DBG" and
				name_index.index and name_index.index.expr and name_index.index.expr.name == "_info"
			then
				source_block_index = i + 1
			end
		end
	end
	local local_source_node = self:find_parent_of_type(node, "source")
	assert(local_source_node ~= nil, "local_source_node ~= nil")
	local local_file_path = local_source_node.file:sub(#self.addon_dir+2)
	table.insert(root_source_node.block.block, source_block_index, ASTNodes.assign(
		node, nil,
		ASTNodes.namelist(node, ASTNodes.index(
			node, nil, ASTNodes.name(node, SPECIAL_NAME),
			ASTNodes.index(
				node, ".", ASTNodes.name(node, "_info"),
				ASTNodes.index(node, "[", ASTNodes.numeral(node, tostring(self._swdbg_index)))
			)
		)),
		ASTNodes.expressionlist(node, ASTNodes.table(node, ASTNodes.fieldlist(node,
			ASTNodes.field(node, ASTNodes.string(node, "name", true), ASTNodes.string(node, name, true)),
			ASTNodes.field(node, ASTNodes.string(node, "line", true), ASTNodes.numeral(node, tostring(start_line))),
			ASTNodes.field(node, ASTNodes.string(node, "column", true), ASTNodes.numeral(node, tostring(start_column))),
			ASTNodes.field(node, ASTNodes.string(node, "file", true), ASTNodes.string(node, local_file_path:gsub("\\", "/"), true))
		)))
	))

	return ASTNodes.funcbody(
		node,
		ASTNodes.varlist(node, ASTNodes.var_args(node)),
		ASTNodes.block(node,
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
	)
end


return TransformerDefs
