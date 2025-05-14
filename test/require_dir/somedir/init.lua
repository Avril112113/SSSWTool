---@require_dir .
require("somedir.bar")
require("somedir.foo")
---@require_dir_end

return {
    ---@require_dir_fields .
    ["bar"] = require("somedir.bar"),
    ["foo"] = require("somedir.foo"),
    ---@require_dir_end
}