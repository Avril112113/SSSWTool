@echo off

if exist "%~dp0luajit.exe" (
	@REM echo - Using provided luajit.
	"%~dp0\luajit.exe" "%~dp0main.lua" %*
) else (
	@REM echo - Using system luajit.
	@REM For profiling: '-jp=-3izsFm5'
	luajit "%~dp0main.lua" %*
)
