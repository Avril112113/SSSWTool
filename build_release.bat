@echo off
SETLOCAL

@REM I really hate batch...


if exist "./release/" rmdir "./release/" /q /s
mkdir "./release/"

copy "./main.lua" "./release/main.lua"
copy "./ssswtool.bat" "./release/ssswtool.bat"
xcopy "./tool" "./release/tool" /s /e /i

mkdir "./release/SelenScript"
xcopy "../SelenScript/libs" "./release/SelenScript/libs" /s /e /i
xcopy "../SelenScript/SelenScript" "./release/SelenScript/SelenScript" /s /e /i

@REM We include LuaJIT x64 for windows in the release.
@REM Not everyone will have it built on their system and it takes effort to build.
FOR /F "tokens=* USEBACKQ" %%F IN (`where luajit`) DO SET LUAJIT_PATH=%%F
echo %LUAJIT_PATH%
copy "%LUAJIT_PATH%" "./release/luajit.exe"
copy "%LUAJIT_PATH%/../lua51.dll" "./release/lua51.dll"

7za a SSSWTool.zip ./release/*
