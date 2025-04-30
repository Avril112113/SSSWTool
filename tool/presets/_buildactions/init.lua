-- WARNING: Ensure only trusted code is put here!
-- Build actions are powerful, they run within SSSWTool and as such has the same capabilities.
-- With that said, they can also be extremely helpful for customizing the build process and adding features for your own needs.
--
-- Stormworks uses Lua 5.3, SSSWTool is run with LuaJIT along with these build actions, there are some notable differences!
-- No guarantees are made about compatibility between versions of SSSWTool for build actions, however breaking changes will be avoided.
--
-- Do not trust the 'current working directory', projects can be built from any directory.
-- Use `AVPath.join{multiproject.project_path, "some_file.txt"}` to access a file within the project reliably.


local AVPath = require "avpath"


---@class SSSWTool.BuildActions
local BuildActions = {}


--- Called before any of the build process starts.
---@param multiproject SSSWTool.MultiProject
---@param project SSSWTool.Project
function BuildActions.pre_build(multiproject, project)
end

--- Called before a file is parsed.  
--- Includes cached and non-cached files.  
---@param multiproject SSSWTool.MultiProject
---@param project SSSWTool.Project
---@param path string
function BuildActions.pre_file(multiproject, project, path)
end

--- Called before a file is parsed.  
--- If the file was cached, this isn't called.  
---@param multiproject SSSWTool.MultiProject
---@param project SSSWTool.Project
---@param path string
function BuildActions.pre_parse(multiproject, project, path)
end

--- Called after a file is parsed but before it's transformed.  
--- If the file was cached, this isn't called.  
--- This is run regardless of parse succsess for failure.  
---@param multiproject SSSWTool.MultiProject
---@param project SSSWTool.Project
---@param path string
---@param ast SelenScript.ASTNodes.Source # Any changes to the AST will be cached!
---@param errors any
---@param comments any
function BuildActions.post_parse(multiproject, project, path, ast, errors, comments)
end

--- Called after a file is parsed successfully but before it's transformed.  
--- Includes cached and non-cached files.  
---@param multiproject SSSWTool.MultiProject
---@param project SSSWTool.Project
---@param path string
function BuildActions.post_file(multiproject, project, path, ast)
end

--- Called after everything is parsed (or loaded from cache) and has been transformed.  
---@param multiproject SSSWTool.MultiProject
---@param project SSSWTool.Project
---@param ast SelenScript.ASTNodes.Source # This is the fully combined output after all transformers has run (including the combiner and tracing).
function BuildActions.post_transform(multiproject, project, ast)
end

--- Called after the entire build process finishes.
--- This is the very last build action to be called.
--- It is called before `script.lua` is copied to it's output directory.
---@param multiproject SSSWTool.MultiProject
---@param project SSSWTool.Project
function BuildActions.post_build(multiproject, project)
end


return BuildActions
