local modpath = ...
---@diagnostic disable-next-line: param-type-mismatch
local modfolderpath = package.searchpath(modpath, package.path):gsub("[\\/][^\\/]*$", "")
local TRACING_PREFIX_SRC_FILE = modfolderpath .. "/src/tracing.lua"


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

---@param node ASTNode
---@return ASTNodeSource
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
		table.insert(block, #block+1, ASTNodes.LineComment(source, "--", "#endregion"))
		table.insert(block, #block+1, ASTNodes.LineComment(source, "--", "#region SSSWTool-Tracing-info"))
		table.insert(block, #block+1, ASTNodes.LineComment(source, "--", "#endregion"))
		table.insert(source.block.block, 1, block)
	end
	return source
end

---@param node ASTNode
---@param name string
---@param start_line integer
---@param start_column integer
---@param local_file_path string
function TransformerDefs:_add_trace_info(node, name, start_line, start_column, local_file_path)
	self:_ensure_tracingblock(node)
	-- Omitted +1 to be above the `--#endregion` comment
	table.insert(self._SWAddon_TracingBlock, #self._SWAddon_TracingBlock, ASTNodes.assign(
		node, nil,
		ASTNodes.namelist(node, ASTNodes.index(
			node, nil, ASTNodes.name(node, SPECIAL_NAME),
			ASTNodes.index(
				node, ".", ASTNodes.name(node, "_info"),
				ASTNodes.index(node, "[", ASTNodes.numeral(node, tostring(self._swdbg_index)))
			)
		)),
		ASTNodes.expressionlist(node, ASTNodes.table(node, ASTNodes.fieldlist(node,
			ASTNodes.field(node, ASTNodes.string(node, "name"), ASTNodes.string(node, name)),
			ASTNodes.field(node, ASTNodes.string(node, "line"), ASTNodes.numeral(node, tostring(start_line))),
			ASTNodes.field(node, ASTNodes.string(node, "column"), ASTNodes.numeral(node, tostring(start_column))),
			ASTNodes.field(node, ASTNodes.string(node, "file"), ASTNodes.string(node, local_file_path))
		)))
	))
end


---@param node ASTNodeSource
function TransformerDefs:source(node)
	local source = self:_get_root_source(node)
	---@cast source -?
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
		table.insert(block, #block+1, ASTNodes.LineComment(source, "--", "#region SSSWTOOL-Tracing"))
		table.insert(block, #block+1, ast)
		table.insert(block, #block+1, ASTNodes.LineComment(source, "--", "#endregion"))
		table.insert(source.block.block, 1, block)
	end
	return node
end

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
	local local_source_node = self:find_parent_of_type(node, "source")
	assert(local_source_node ~= nil, "local_source_node ~= nil")
	local local_file_path = "<UNKNOWN>"
	if local_source_node.file then
		if local_source_node.file:find("^<SSSWTOOL>/") then
			local_file_path = local_source_node.file:gsub("\\", "/")
		else
			local_file_path = local_source_node.file:sub(#self.addon_dir+2):gsub("\\", "/")
		end
	end
	self:_add_trace_info(node, name, start_line, start_column, local_file_path)

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
