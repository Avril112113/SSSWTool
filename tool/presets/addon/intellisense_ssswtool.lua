---@meta
--- Intellisense information for SSSWTool
--- DO NOT require() this file


--#region Combiner

--- **UNSTABLE API**, This may change without warning.  
--- Get the project relative file path of a modpath.  
--- `__SSSWTOOL_MOD_TO_FILEPATH[modpath]`  
---@type table<string,string>
__SSSWTOOL_MOD_TO_FILEPATH = {}

--- **UNSTABLE API**, This may change without warning.  
--- You can check if something has already been required;  
--- `__SSSWTOOL_RESULTS[modpath]`  
---@type table<string,nil|any>
__SSSWTOOL_RESULTS = {}

--#endregion


--#region Tracing
--[[
	Before using any of these, make sure to check if tracing is enabled.
	For example;
	```lua
	if SSSW_DBG then
		local lines = SSSW_DBG.stacktrace()
		...
	end
	```
]]

---@alias SSSW_DBG.INFO {name:string, line:integer, column:integer, file:string}

---@type table?
SSSW_DBG = {}

---@type "simple"|"full"
SSSW_DBG.level = nil

--- In certain cases, tracing may find an onTick function that has later been overridden.  
--- This will mess-up tracing, below can be used to as a hacky fix.  
--- Ensure to check the tracing mode and set accordingly.  
--- ```lua
--- if SSSW_DBG then
--- 	if SSSW_DBG.level == "full" then
--- 		SSSW_DBG.expected_stack_onTick = {"_ENV[name]", "`existing(...)`"}
--- 	else
--- 		SSSW_DBG.expected_stack_onTick = {"_ENV[name]"}
--- 	end
--- 	SSSW_DBG.expected_stack_httpReply = SSSW_DBG.expected_stack_onTick
--- end
--- ```
SSSW_DBG.expected_stack_onTick = {}
SSSW_DBG.expected_stack_httpReply = {}

--- The error handler is called when any error is detected, just before the stack is cleaned up.  
--- The first argument is the top-most stack entry, which should be where the error occurred.  
--- See https://github.com/Avril112113/SSSWTool/blob/main/tool/src/tracing.lua for accessing the stack.  
---@type fun(t:SSSW_DBG.INFO)?
SSSW_DBG.error_handler = nil

---@type fun(depth:integer?):string[]
SSSW_DBG.stacktrace = nil

---@type fun():SSSW_DBG.INFO
SSSW_DBG.get_current_info = nil


--#endregion


--#region MagicVariables

--- Context sensitive magic variable.  
--- A string of the project's name.  
---@type string
SSSWTOOL_PROJECT_NAME = nil

--- Context sensitive magic variable.  
--- This file's path relative to the project.  
---@type string
SSSWTOOL_SRC_FILE = nil

--- Context sensitive magic variable.  
--- The position of this variable in this file. 
---@type integer
SSSWTOOL_SRC_POS = nil

--- Context sensitive magic variable.  
--- The line position of this variable in this file. 
---@type integer
SSSWTOOL_SRC_LINE = nil

--- Context sensitive magic variable.  
--- The column position of this variable in this file. 
---@type integer
SSSWTOOL_SRC_COLUMN = nil

--- Context sensitive magic variable.  
--- The position of this variable in the output. 
---@type integer
SSSWTOOL_OUT_POS = nil

--- Context sensitive magic variable.  
--- The line position of this variable in the output. 
---@type integer
SSSWTOOL_OUT_LINE = nil

--- Context sensitive magic variable.  
--- The column position of this variable in the output. 
---@type integer
SSSWTOOL_OUT_COLUMN = nil

--#endregion
