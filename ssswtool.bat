@echo off

if exist "%~dp0luajit.exe" (
	echo - Using provided luajit.
	"%~dp0\luajit.exe" "%~dp0main.lua" %*
) else (
	echo - Using system luajit.
	luajit "%~dp0main.lua" %*
)
