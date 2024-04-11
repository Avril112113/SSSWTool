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
	if node.type == "index" and node.expr.name == "require" then
		local modpath
		if call_node.args.type == "string" then
			modpath = call_node.args.value
		elseif #call_node.args == 1 and call_node.args[1].type == "string" then
			modpath = call_node.args[1].value
		else
			return node
		end
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
			-- TODO: Replace with function call containing all the code, meaning returns from require will work.
			self:visit(ast)
			return ast
		end
	end
	return node
end


return TransformerDefs
