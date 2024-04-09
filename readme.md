# SSSWTool
A tool utilizing [SelenScript](https://github.com/Avril112113/selenscript)'s parser to combine your StormWorks addon code into a single file.  
The catch, it's intelligent and adds more features!  

This project is currently **VERY work in progress**, it's lacking a decent CLI and various features.  
As it is right now, it's not considered a replacement for other tools until further testing and features has been finished.  

To clarify, the following is what this tool provides:
- Combining multiple files into one.
- Optional tracing with `--trace` which provides full stack traces at runtime with source file, line and column info
- TODO: Config file (for predefined options and output path, eg)
- TODO: Build output path.
- TODO: Custom build actions.
- TODO: vscode task template.

## Usage
Run `ssswtool.bat` either directly or `ssswtool` if it's on your PATH.  
The file `script.lua` is the entrypoint, any files `require()` from there will be directly included into the output.  
Build with `ssswtool build ./`, or with tracing `ssswtool build ./ --trace`  
The default output directory is `<ADDON_SRC>/_build/script.lua` (not configurable yet)  

## [Releases](https://github.com/Avril112113/SSSWTool/releases)
See the [releases](https://github.com/Avril112113/SSSWTool/releases) for download.  
If you want to use `ssswtool` anywhere, consider adding the `./SSSWTool/` to your PATH (the directory containing `ssswtool.bat`).  
See (usage)[#Usage] for how to use this tool.  

**Pre-Built Binaries:**  
The releases come with `luajit` pre-built, you can delete the files and it'll use your system version instead.  
SelenScript also comes with pre-built libraries for `lfs` and `lpeglabel` in `./SelenScript/libs`.  
