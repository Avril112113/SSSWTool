local BuildActions = {}


--- Called before any of the build process starts.
---@param config SSSWTool.Config
function BuildActions.pre_build(config)
end

--- Called before a file is parsed.
---@param config SSSWTool.Config
---@param path string
function BuildActions.pre_parse(config, path)
end

--- Called after a file is parsed but before it's transformed.
---@param config SSSWTool.Config
---@param path string
---@param ast SelenScript.ASTNodeSource
function BuildActions.post_parse(config, path, ast)
end

--- Called after a file is transformed.
---@param config SSSWTool.Config
---@param path string
---@param ast SelenScript.ASTNodeSource
function BuildActions.post_transform(config, path, ast)
end

--- Called after the entire build process finishes.
--- This is the very last build action to be called.
--- This is still called before `script.lua` is copied to it's output directory.
---@param config SSSWTool.Config
function BuildActions.post_build(config)
end


return BuildActions
