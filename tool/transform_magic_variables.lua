local ASTNodes = require "SelenScript.parser.ast_nodes"
local ASTNodesSpecial = require "SelenScript.parser.ast_nodes_special"


---@class SSSWTool.Transformer_MagicVariables : SSSWTool.Transformer
local TransformerDefs = {}


local MAGIC_VARIABLE_HANDLERS = {
	---@param self SSSWTool.Transformer_MagicVariables
	---@param node SelenScript.ASTNodes.index
	["SSSWTOOL_PROJECT_NAME"]=function(self, node)
		return ASTNodes["string"]{
			_parent = node,
			value = self.project.config.name
		}
	end,
	---@param self SSSWTool.Transformer_MagicVariables
	---@param node SelenScript.ASTNodes.index
	["SSSWTOOL_SRC_FILE"]=function(self, node)
		return ASTNodes["string"]{
			_parent = node,
			value = node.source.file
		}
	end,
	---@param self SSSWTool.Transformer_MagicVariables
	---@param node SelenScript.ASTNodes.index
	["SSSWTOOL_SRC_POS"]=function(self, node)
		return ASTNodes["numeral"]{
			_parent = node,
			value = ("%s"):format(node.start)
		}
	end,
	---@param self SSSWTool.Transformer_MagicVariables
	---@param node SelenScript.ASTNodes.index
	["SSSWTOOL_SRC_LINE"]=function(self, node)
		local line, column = node.source:calcline(node.start)
		return ASTNodes["numeral"]{
			_parent = node,
			value = ("%s"):format(line)
		}
	end,
	---@param self SSSWTool.Transformer_MagicVariables
	---@param node SelenScript.ASTNodes.index
	["SSSWTOOL_SRC_COLUMN"]=function(self, node)
		local line, column = node.source:calcline(node.start)
		return ASTNodes["numeral"]{
			_parent = node,
			value = ("%s"):format(column)
		}
	end,
	---@param self SSSWTool.Transformer_MagicVariables
	---@param node SelenScript.ASTNodes.index
	["SSSWTOOL_OUT_POS"]=function(self, node)
		return ASTNodesSpecial["OutputPos"]{
			_parent = node
		}
	end,
	---@param self SSSWTool.Transformer_MagicVariables
	---@param node SelenScript.ASTNodes.index
	["SSSWTOOL_OUT_LINE"]=function(self, node)
		return ASTNodesSpecial["OutputLine"]{
			_parent = node
		}
	end,
	---@param self SSSWTool.Transformer_MagicVariables
	---@param node SelenScript.ASTNodes.index
	["SSSWTOOL_OUT_COLUMN"]=function(self, node)
		return ASTNodesSpecial["OutputColumn"]{
			_parent = node
		}
	end,
}


---@param node SelenScript.ASTNodes.index
function TransformerDefs:index(node)
	local parent = self:get_parent(node)
	if parent.type ~= "index" and parent.type ~= "functiondef" and node.expr.type == "name" then
		local name = node.expr
		---@cast name SelenScript.ASTNodes.name
		local handler = MAGIC_VARIABLE_HANDLERS[name.name]
		if handler then
			local new_node = handler(self, node)
			if node.index then
				return ASTNodes["index"]{
					_parent = node,
					---@diagnostic disable-next-line: assign-type-mismatch
					expr = new_node,
					index = node.index
				}
			else
				return new_node
			end
		end
	end
	return node
end


return TransformerDefs
