@echo off
@REM I really hate batch...


if exist "./release/" rmdir "./release/" /q /s
mkdir "./release/"

mkdir "./release/SSSWTool"
copy "./main.lua" "./release/SSSWTool/main.lua"
copy "./ssswtool.bat" "./release/SSSWTool/ssswtool.bat"
copy "./transform_lua_to_swaddon.lua" "./release/SSSWTool/transform_lua_to_swaddon.lua"
copy "./transform_swaddon_tracing.lua" "./release/SSSWTool/transform_swaddon_tracing.lua"

mkdir "./release/SelenScript"
xcopy "../SelenScript/libs" "./release/SelenScript/libs" /s /e /i
xcopy "../SelenScript/SelenScript" "./release/SelenScript/SelenScript" /s /e /i
