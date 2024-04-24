local args = assert(arg)

local MAIN_PATH = assert(args[0])  -- Path to this file
local TOOL_PATH = MAIN_PATH:find("[\\/]") and MAIN_PATH:gsub("[\\/][^\\/]*$", "") or "."
local SELENSCRIPT_PATH = "SelenScript"
do
	-- Directory existence check, works on Windows and Linux
	local f, _, code = io.open("../SelenScript", "r")
	if code == 13 or (f and select(3, f:read()) == 21) then
		if f then f:close() end
		SELENSCRIPT_PATH = "../SelenScript"
	end
end

jit = jit or select(2, pcall(require, "jit"))
if not jit then
	print("Must be run with LuaJIT, not " .. _VERSION)
	os.exit(-1)
end
local binary_ext = jit.os == "Windows" and "dll" or "so"
package.path = ("{TP}/?.lua;{TP}/?/init.lua;{SSP}/libs/?.lua;{SSP}/libs/?/init.lua;{SSP}/?.lua;{SSP}/?/init.lua;"):gsub("{TP}", TOOL_PATH):gsub("{SSP}", SELENSCRIPT_PATH)
package.cpath = ("{TP}/?.{EXT};{SSP}/libs/?.{EXT};"):gsub("{TP}", TOOL_PATH):gsub("{SSP}", SELENSCRIPT_PATH):gsub("{EXT}", binary_ext)

local CLI = require "tool.cli"

os.exit(CLI.process(args) or 0)
