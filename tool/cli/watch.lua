local ffi = require "ffi"
local LuaNotify = require "luanotify"
local AVPath = require "avpath"

local MultiProject = require "tool.multi_project"


ffi.cdef[[
void Sleep(int ms);
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
]]
local sleep
if ffi.os == "Windows" then
	function sleep(s)
		ffi.C.Sleep(s*1000)
	end
else
	function sleep(s)
		ffi.C.poll(nil, 0, s*1000)
	end
end


---@param CLI SSWTool.CLI
return function(CLI)
	---@type SSWTool.CLI.Action
	return {
		help = "Build a SW addon project.",
		usage = "[path=./]",
		---@param args string[]
		---@param pos integer
		handler = function(args, pos)
			---@param project SSSWTool.MultiProject|SSSWTool.Project
			local function get_watch_paths(project, paths)
				paths = paths or {}
				if project.__name == "Project" then
					---@cast project SSSWTool.Project
					local src = project.config.src
					if type(src) == "table" then
						for _, v in pairs(src) do
							if not AVPath.getabs(v) then
								v = AVPath.join{project.multiproject.project_path, v}
							end
							table.insert(paths, v)
						end
					elseif type(src) == "string" then
						if not AVPath.getabs(src) then
							src = AVPath.join{project.multiproject.project_path, src}
						end
						table.insert(paths, src)
					end
				elseif project.__name == "MultiPorject" then
					---@cast project SSSWTool.MultiProject
					table.insert(paths, project.config_path)
					for _, subproject in pairs(project.projects) do
						get_watch_paths(subproject, paths)
					end
				else
					error(("Not a Project or MultiProject? '%s'"):format(tostring(project)))
				end
				return paths
			end

			---@param addon_dir string
			local function build(addon_dir)
				local multi_project, err = MultiProject.new(addon_dir .. "/ssswtool.json")
				if not multi_project or err then
					print_error(err or "FAIL project ~= nil")
				elseif multi_project then
					multi_project:build()
				end
				return multi_project, err
			end

			local addon_dir = args[pos] or "./"
			pos = pos + 1
			local multi_project = build(addon_dir)
			if not multi_project then return -1 end
			print("\n~ Beginning watch.")
			local ok, err = xpcall(function()
				while true do
					local watcher = LuaNotify.new()
					watcher:whitelist_glob("*.lua")
					watcher:whitelist_glob("*.json")
					watcher:blacklist_glob("*/_build/*")
					for _, path in pairs(get_watch_paths(multi_project)) do
						watcher:watch(path, true)
					end
					while true do
						local event = watcher:poll()
						if event then break end
					end
					sleep(100/1000)
					print("\n~ Detected file change, building...")
					local new_multi_project = build(addon_dir)
					if new_multi_project then
						multi_project = new_multi_project
					end
				end
			end, debug.traceback)
			if not ok then
				if err ~= nil and err:sub(1, 12) ~= "interrupted!" then
					print("Watch stopped.")
				elseif err == nil or err:sub(1, 12) ~= "interrupted!" then
					print(err or "watch not ok and missing error msg.")
					return -1
				end
			end
			return 0
		end,
	}
end