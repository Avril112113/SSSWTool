@echo off

if exist "%~dp0luajit.exe" (
	@REM echo - Using provided luajit.
	"%~dp0\luajit.exe" "%~dp0main.lua" %*
) else (
	@REM echo - Using system luajit.
	luajit "%~dp0main.lua" %*
)
