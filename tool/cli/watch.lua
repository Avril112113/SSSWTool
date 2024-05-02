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
		help = "Automatically build a SW addon project upon detected changes.",
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

			local function create_watcher(multi_project)
				local watcher = LuaNotify.new()
				watcher:whitelist_glob("*.lua")
				watcher:whitelist_glob("*.json")
				watcher:blacklist_glob("*/_build/*")
				for _, path in pairs(get_watch_paths(multi_project)) do
					watcher:watch(path, true)
				end
				return watcher
			end

			local addon_dir = args[pos] or "./"
			pos = pos + 1
			local multi_project = build(addon_dir)
			if not multi_project then return -1 end
			print("\n~ Beginning watch.")
			local ok, err = xpcall(function()
				local watcher, checking_old_watcher = create_watcher(multi_project), false
				local loop_detect = 0
				while true do
					if loop_detect >= 3 then
						print("\n~ Potential watch loop detected, skipping. (can probably ignore this message)")
						watcher = create_watcher(multi_project)
					end
					while true do
						local event = watcher:poll()
						if event and (event.type == "create" or event.type == "modify" or event.type == "remove") then
							break
						elseif not event then
							if checking_old_watcher then
								watcher = create_watcher(multi_project)
								checking_old_watcher = false
							else
								sleep(100/1000)
							end
						end
					end
					sleep(100/1000)
					-- Clear out the watcher so we can detect changes during the build.
					while watcher:poll() do end
					if checking_old_watcher then
						print("\n~ Detected file change during previous build, building...")
						loop_detect = loop_detect + 1
					else
						print("\n~ Detected file change, building...")
						loop_detect = 0
					end
					checking_old_watcher = true

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