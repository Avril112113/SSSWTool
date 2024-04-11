-- This is a very dummed down version of my logging library, which isn't as well suited for CLI situations.

local jit = require "jit"
local Colors = require "terminal_colors"

local MODE_COLORS = {
	DEBUG = Colors.debug,
	INFO = Colors.info,
	WARN = Colors.warn,
	ERROR = Colors.error,
}


--- https://stackoverflow.com/questions/64919350/enable-ansi-sequences-in-windows-terminal
local function windows_enable_ansi()
	local ffi = require"ffi"
	ffi.cdef[[
	typedef int BOOL;
	static const int INVALID_HANDLE_VALUE               = -1;
	static const int STD_OUTPUT_HANDLE                  = -11;
	static const int ENABLE_VIRTUAL_TERMINAL_PROCESSING = 4;
	intptr_t GetStdHandle(int nStdHandle);
	BOOL GetConsoleMode(intptr_t hConsoleHandle, int* lpMode);
	BOOL SetConsoleMode(intptr_t hConsoleHandle, int dwMode);
	]]
	---@diagnostic disable: undefined-field
	local console_handle = ffi.C.GetStdHandle(ffi.C.STD_OUTPUT_HANDLE)
	assert(console_handle ~= ffi.C.INVALID_HANDLE_VALUE)
	local prev_console_mode = ffi.new"int[1]"
	assert(ffi.C.GetConsoleMode(console_handle, prev_console_mode) ~= 0, "This script must be run from a console application")
	---@diagnostic disable-next-line: param-type-mismatch
	assert(ffi.C.SetConsoleMode(console_handle, bit.bor(prev_console_mode[0], ffi.C.ENABLE_VIRTUAL_TERMINAL_PROCESSING or 0)) ~= 0)
	---@diagnostic enable: undefined-field
end

---@param mode string
---@param ... any
local function _print(mode, ...)
	local values = {...}
	for i=1,select("#", ...) do
		values[i] = tostring(values[i])
	end
	print(("%s[%s%s%s]:%s%s %s"):format(Colors.fix, MODE_COLORS[mode], mode, Colors.fix, Colors.reset, string.rep(" ", 5-#mode), table.concat(values, "\t")))
end

---@param ... any
function print_debug(...)
	_print("DEBUG", ...)
end

---@param ... any
function print_info(...)
	_print("INFO", ...)
end

---@param ... any
function print_warn(...)
	_print("WARN", ...)
end

---@param ... any
function print_error(...)
	_print("ERROR", ...)
end


if jit.os == "Windows" then
	windows_enable_ansi()
end
