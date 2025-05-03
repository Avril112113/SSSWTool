local AVPath = require "avpath"

local ASTNodes = require "SelenScript.parser.ast_nodes"


---@class SSSWTool.Transformer_Combiner_File.FileInfo
---@field [1] string  # local file path
---@field [2] string  # modpath

---@class SelenScript.ASTNodes.Source
---@field _required_paths table<string, SSSWTool.Transformer_Combiner_File.FileInfo>

---@class SSSWTool.Transformer_Combiner_File : SSSWTool.Transformer
---@field _required_paths table<string, SSSWTool.Transformer_Combiner_File.FileInfo>
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
		if err or not filepath or not filepath_local then
			print_error(("Failed to find '%s'%s"):format(modpath, err))
			return ASTNodes.LongComment{_parent = node, value = ("Failed to find '%s'"):format(modpath)}
		else
			filepath = AVPath.norm(filepath)
			if not self._required_paths then
				self._required_paths = {}
				self:_get_root_source(node)._required_paths = self._required_paths
			end
			self._required_paths[filepath] = {filepath_local, modpath}
			return node
		end
	end
	return node
end


return TransformerDefs
