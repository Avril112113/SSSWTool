local args = assert(arg)

local MAIN_PATH = assert(args[0])  -- Path to this file
local TOOL_PATH = MAIN_PATH:find("[\\/]") and MAIN_PATH:gsub("[\\/][^\\/]*$", "") or "."
local SELENSCRIPT_PATH_LOCAL = "SelenScript"
do
	-- Directory existence check, works on Windows and Linux
	local f, _, code = io.open(TOOL_PATH .. "/../SelenScript", "r")
	if code == 13 or (f and select(3, f:read()) == 21) then
		if f then f:close() end
		SELENSCRIPT_PATH_LOCAL = "../SelenScript"
	end
end
local SELENSCRIPT_PATH = TOOL_PATH .. "/" .. SELENSCRIPT_PATH_LOCAL

jit = jit or select(2, pcall(require, "jit"))
if not jit then
	print("Must be run with LuaJIT, not " .. _VERSION)
	os.exit(-1)
end
local binary_ext = jit.os == "Windows" and "dll" or "so"
package.path = ("{TP}/?.lua;{TP}/?/init.lua;{SSP}/libs/?.lua;{SSP}/libs/?/init.lua;{SSP}/?.lua;{SSP}/?/init.lua;"):gsub("{TP}", TOOL_PATH):gsub("{SSP}", SELENSCRIPT_PATH)
package.cpath = ("{TP}/?.{EXT};{SSP}/?.{EXT};{SSP}/libs/?.{EXT};"):gsub("{TP}", TOOL_PATH):gsub("{SSP}", SELENSCRIPT_PATH):gsub("{EXT}", binary_ext)



local lanes = require "lanes".configure()
local socket = require "socket"
require "logging".windows_enable_ansi()
local lfs = require "lfs"
local Utils = require "SelenScript.utils"
local Parser = require "SelenScript.parser.parser"


local function allfiles(path, exclusion)
	function recur(basepath)
		for sub in lfs.dir(basepath) do
			if sub ~= "." and sub ~= ".." then
				local sub_path = basepath .. "/" .. sub
				if not exclusion or exclusion[sub_path] ~= false then
					if lfs.attributes(sub_path, "mode") == "directory" then
						recur(sub_path)
					else
						coroutine.yield(sub_path)
					end
				end
			end
		end
	end
	return coroutine.wrap(function()
		recur(path)
	end)
end

local parse_worker_linda = lanes.linda()
local parse_worker = lanes.gen("*", function()
	require "logging".windows_enable_ansi()
	local Parser = require "SelenScript.parser.parser"
	local Transformer = require "SelenScript.transformer.transformer"
	local TransformMagicVariables = require "tool.transform_magic_variables"
	local TransformTracingFile = require "tool.transform_swaddon_tracing_file"
	local parser = assert(Parser.new({}))
	while true do
		local _, file_path = assert(parse_worker_linda:receive("parse"))
		local ast, errors, comments = parser:parse(Utils.readFile(file_path), file_path)
		Transformer.new(TransformMagicVariables):transform(ast)
		Transformer.new(TransformTracingFile):transform(ast, {
			multiproject = { project_path = "./test/toast_imai" }
		})
		assert(parse_worker_linda:send("results", {file_path, {ast, errors, comments}}))
	end
end)

local start = socket.gettime()

print("Starting workers...")
local workers = {}
for i=1,6 do
	table.insert(workers, parse_worker())
end

print("Parsing all lua files...")
local files = {}
local count = 0
for file in allfiles("./test/toast_imai", {["./test/toast_imai/_build"]=false}) do
	if file:sub(-4) == ".lua" then
		assert(parse_worker_linda:send("parse", file))
		files[file] = false
		count = count + 1
	end
end

print("Waiting for workers...")
while count > 0 do
	for i, worker in pairs(workers) do
		if worker.status == "error" then
			_ = worker[1]
		end
	end

	local _, result = assert(parse_worker_linda:receive("results"))
	local file_path, parse_data = result[1], result[2]
	files[file_path] = parse_data
	count = count - 1
	-- print(file_path, parse_data)
end

print("Cancelling worker threads...")
for i,worker in pairs(workers) do
	worker:cancel()
end

local finish = socket.gettime()
print("Threaded finished", finish-start)


local start = socket.gettime()

local Parser = require "SelenScript.parser.parser"
local Transformer = require "SelenScript.transformer.transformer"
local TransformMagicVariables = require "tool.transform_magic_variables"
local TransformTracingFile = require "tool.transform_swaddon_tracing_file"
local parser = assert(Parser.new({}))
local files = {}
for file_path in allfiles("./test/toast_imai", {["./test/toast_imai/_build"]=false}) do
	if file_path:sub(-4) == ".lua" then
		local ast, errors, comments = parser:parse(Utils.readFile(file_path), file_path)
		Transformer.new(TransformMagicVariables):transform(ast)
		Transformer.new(TransformTracingFile):transform(ast, {
			multiproject = { project_path = "./test/toast_imai" }
		})
		files[file_path] = ast
	end
end

local finish = socket.gettime()
print("Non-threaded finished", finish-start)


-- local test = lanes.gen("*", function()
-- 	local Parser = require "SelenScript.parser.parser"
-- 	local parser = assert(Parser.new({}))
-- 	return parser:parse(Utils.readFile("testing.lua"))
-- end)

-- local thread = test()
-- print(thread[1])

-- print("...")
