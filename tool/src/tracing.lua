---@diagnostic disable: duplicate-set-field


---@alias SS_SW_DBG.INFO {name:string, line:integer, column:integer, file:string}

-- Local is fine, since all combined files will be after this file.
-- It also prevents accidential recursion with `_ENV`
---@class SS_SW_DBG
local SS_SW_DBG = {}
---@type integer[]
SS_SW_DBG._stack = {}
SS_SW_DBG._server = {
	announce = server.announce,
	getAddonData = server.getAddonData,
	getAddonIndex = server.getAddonIndex,
	httpGet = server.httpGet,
}

function SS_SW_DBG._trace_enter(id)
	table.insert(SS_SW_DBG._stack, #SS_SW_DBG._stack+1, id)
end

function SS_SW_DBG._trace_exit(id)
	local removed_id = table.remove(SS_SW_DBG._stack, #SS_SW_DBG._stack)
	if removed_id ~= id then
		local msg = ("Attempt to exit trace '%s' but found '%s' instead."):format(id, removed_id)
		debug.log("[SW] [ERROR] " .. msg)
		SS_SW_DBG._server.announce(SS_SW_DBG._server.getAddonData((SS_SW_DBG._server.getAddonIndex())).name, msg, -1)
	end
end

function SS_SW_DBG._trace_func(id, f, ...)
	SS_SW_DBG._trace_enter(id)
	local results = {f(...)}
	SS_SW_DBG._trace_exit(id)
	return table.unpack(results)
end

---@param tbl table
---@param path string
function SS_SW_DBG._hook_tbl(tbl, path)
	for i, v in pairs(tbl) do
		if type(i) == "string" and type(v) == "function" then
			local nindex = SS_SW_DBG._nindex
			SS_SW_DBG._info[nindex] = {
				["name"] = path .. "." .. i,
				["line"] = 1,
				["column"] = 1,
				["file"] = "{_ENV}",
			}
			tbl[i] = function(...)
				return SS_SW_DBG._trace_func(nindex, v, ...)
			end
			SS_SW_DBG._nindex = SS_SW_DBG._nindex - 1
		end
	end
end

function SS_SW_DBG._sendCheckStackHttp()
	SS_SW_DBG._server.httpGet(0, "SSSWTool-tracing-check_stack")
end

function SS_SW_DBG._handleHttp(port, request)
	if port == 0 and request == "SSSWTool-tracing-check_stack" then
		SS_SW_DBG.check_stack(0)
		return true
	end
	return false
end

---@param depth integer?
function SS_SW_DBG.stacktrace(depth)
	depth = depth or #SS_SW_DBG._stack
	local lines = {}
	local prev_file
	for i=depth,1,-1 do
		local id = SS_SW_DBG._stack[i]
		local trace = SS_SW_DBG._info[id]
		if trace.file ~= prev_file then
			prev_file = trace.file
			table.insert(lines, ("   '%s'"):format(trace.file))
		end
		table.insert(lines, ("%s %s @ %s:%s"):format(i, trace.name, trace.line, trace.column))
	end
	return lines
end

---@param expected_depth integer
---@return boolean # true when stack was to be deeper than expected and was shortend with error been logged. 
function SS_SW_DBG.check_stack(expected_depth)
	if #SS_SW_DBG._stack > expected_depth then
		local lines = SS_SW_DBG.stacktrace(#SS_SW_DBG._stack-expected_depth)
		table.insert(lines, 1, "Detected unwound stacktrace:")
		for i=#SS_SW_DBG._stack-expected_depth,1,-1 do
			table.remove(SS_SW_DBG._stack, i)
		end
		for _, s in ipairs(lines) do debug.log("[SW] [ERROR] " .. s) end
		SS_SW_DBG._server.announce(SS_SW_DBG._server.getAddonData((SS_SW_DBG._server.getAddonIndex())).name, table.concat(lines, "\n"), -1)
		return true
	end
	return false
end

---@return SS_SW_DBG.INFO
function SS_SW_DBG.get_current_info()
	return SS_SW_DBG._info[SS_SW_DBG._stack[#SS_SW_DBG._stack]]
end

-- Negative index, used for std methods in _ENV
SS_SW_DBG._nindex = -1
---@type SS_SW_DBG.INFO[]
SS_SW_DBG._info = {}

SS_SW_DBG._hook_tbl(server, "server")
