--[[
	WARNING: It is heavily advised to use source control (like git), as this will modify the original source files!

	The following will replace `---@require_dir ./some_dir` with many `require("somedir.myfile")` for each lua file in the directory.
	It will end the new code with `---@require_dir_end` so it can detect the entire section that was generated to replace it.
	It also has a `---@require_dir_fields ./some_dir` to output as `["myfile"] = require("somedir.myfile")`
	`---@require_dir .` is a valid, as it ignores the file that the comment is in.

	Currently, it will require a second build to actually apply the changes from the prior build. (See TODO below)
]]


local AvPath = require "avpath"
local Emitter = require "SelenScript.emitter.emitter"
local ASTNodes = require "SelenScript.parser.ast_nodes"
local ASTNodesSpecial = require "SelenScript.parser.ast_nodes_special"
local Utils = require "SelenScript.utils"
local lfs = require "lfs"


---@class RequireDirBuildActions : SSSWTool.BuildActions
local BuildActions = {}


--- Called after a file is parsed but before it's transformed.  
--- If the file was cached, this isn't called.  
--- This is run regardless of parse success for failure.  
---@param multiproject SSSWTool.MultiProject
---@param project SSSWTool.Project
---@param path string
---@param ast SelenScript.ASTNodes.Source # Any changes to the AST will be cached!
---@param comments (SelenScript.ASTNodes.LineComment|SelenScript.ASTNodes.LongComment)[]
function BuildActions.post_file(multiproject, project, path, ast, comments)
	local parser = project:get_parser()
	if not parser then return end

	local REQUIRE_DIR_PATTERN = "^@require_dir%s+(%.?[%w%d_%- \\/:]*)%s*$"
	local REQUIRE_DIR_FIELDS_PATTERN = "^@require_dir_fields%s+(%.?[%w%d_%- \\/:]*)%s*$"
	local REQUIRE_DIR_END_PATTERN = "^@require_dir_end%s*$"

	local ast_src = ast.src

	for i=#comments,1,-1 do
		local comment = comments[i]
		if comment.prefix ~= "---" then goto continue end
		local require_dir_path = comment.value:match(REQUIRE_DIR_PATTERN)
		local output_style = "normal"
		if require_dir_path == nil then
			require_dir_path = comment.value:match(REQUIRE_DIR_FIELDS_PATTERN)
			output_style = "fields"
		end
		if require_dir_path == nil then goto continue end
		---@type SelenScript.ASTNodes.LineComment|SelenScript.ASTNodes.LongComment|nil
		local endcomment = comments[i+1]
		if endcomment and not endcomment.value:match(REQUIRE_DIR_END_PATTERN) then
			endcomment = nil
		end

		local real_path, src_path, err_msg = project:findSrcFile(AvPath.join{AvPath.relative(path, multiproject.project_path), "..", require_dir_path}, "directory")
		if not real_path or err_msg then
			print_error(("'%s%s'\n\t%s"):format(comment.prefix, comment.value, tostring(err_msg):gsub("\n", "\n\t")))
			goto continue
		end

		-- Create a 'block' ast node.
		-- These don't actually affect much, it's just a collection of nodes, which will have a newline after them.
		local block = ASTNodes["block"]{
			-- Preserve the original comment.
			comment,
			-- Add an end comment we can detect later.
			ASTNodes["LineComment"]{
				prefix = comment.prefix,
				value = "@require_dir_end"
			}
		}

		for sub_path in lfs.dir(real_path) do
			-- Ignore "." and "..", or any file/dir starting with "."
			if sub_path:sub(1, 1) == "." then goto continue end
			-- Get full path to the sub-file/folder
			local new_require_path = AvPath.join{real_path, sub_path}
			-- Get the file/folder src path.
			local sub_real_path, sub_src_path, sub_err_msg = project:findSrcFile(AvPath.relative(new_require_path, multiproject.project_path), "file", "?;?/init.lua")
			if not sub_src_path or sub_err_msg then
				print_error(("'%s%s'\n\t%s"):format(comment.prefix, comment.value, tostring(sub_err_msg):gsub("\n", "\n\t")))
				goto continue
			end
			-- Do not require this file, in this file.
			if sub_real_path == path then goto continue end
			local name = AvPath.name(sub_src_path)
			if name == "init.lua" then
				name = AvPath.name(AvPath.base(sub_src_path))
			end
			name = name:gsub("%.lua$", "")
			-- If the name contains any dots after removing the .lua extension, it can't be required.
			if name:find("%.") then
				goto continue
			end
			--                           Remove extension   Remove ./           Slashes to dots
			local modpath = sub_src_path:gsub("%.lua$", ""):gsub("%.[\\/]", ""):gsub("[\\/]", ".")
			local require_node = assert(project:parse_raw(("require(\"%s\")"):format(modpath))).block.block[1]
			---@cast require_node SelenScript.ASTNodes.index
			-- note the below inserts using `#block`, this is inserting second to last in the block. 
			if output_style == "normal" then
				-- Insert the `require("x.y.z")` into the block.
				table.insert(block, #block, require_node)
			else
				-- Insert the `["z"] = require("x.y.z")` into the block.
				-- We must do some manual formatting due to SelenScript not being able to parse specific parts of lua on demand (currently)
				table.insert(block, #block, ASTNodesSpecial["OutputRaw"]{
					("[\"%s\"] = "):format(name), require_node, ","
				})
			end
			::continue::
		end

		-- Emit the code
		local new_src_section = Emitter.new("lua", { fieldlist_compact = true }):generate(block)

		local start, finish = comment.start, endcomment and endcomment.finish or comment.finish
		local prefix_space = ast.src:sub(1, start-1):match("[ \t]+$") or ""
		local prefixed_new_src_section = new_src_section:gsub("\n", "\n" .. prefix_space)

		local new_src = ast_src:sub(1, start-1) .. prefixed_new_src_section .. ast_src:sub(finish, -1)
		if new_src ~= ast_src then
			ast_src = new_src
		end

		-- TODO: Add the `block` to the `ast` so a rebuild isn't required.
		--       This isn't that easy/performant to do currently.

    	::continue::
	end
	if ast_src ~= ast.src then
		print_warn("Found `---@require_dir` that has changed, please run another build!")
		Utils.writeFile(path, ast_src)
	end
end


return BuildActions
