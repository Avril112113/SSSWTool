__SSSWTOOL_REQUIRES = {}
__SSSWTOOL_MOD_TO_FILEPATH = {}
__SSSWTOOL_RESULTS = {}
function require(modpath)
	if __SSSWTOOL_RESULTS[modpath] == nil then
		__SSSWTOOL_RESULTS[modpath] = __SSSWTOOL_REQUIRES[modpath](modpath, __SSSWTOOL_MOD_TO_FILEPATH[modpath])
		if __SSSWTOOL_RESULTS[modpath] == nil then
			__SSSWTOOL_RESULTS[modpath] = true
		end
	end
	return __SSSWTOOL_RESULTS[modpath]
end
