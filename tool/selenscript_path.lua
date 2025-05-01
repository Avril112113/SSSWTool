local AvPath = require "avpath"

---@diagnostic disable-next-line: param-type-mismatch
return AvPath.base(AvPath.base(package.searchpath("SelenScript.utils", package.path)))
