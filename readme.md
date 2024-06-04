# SSSWTool
A tool to build Stormworks addons with ease.  
See below for what this tool can do thanks to utilizing [SelenScript](https://github.com/Avril112113/selenscript).  

This project is still work in progress, however it is usable and worth giving a try.  
There are many features still to be added, but already provides more than alternate options.  

Currently, only addon Lua is supported, it is planned to support vehicle Lua in the future.  

The following is what this tool provides:  
- Combining multiple files into one.  
- Optional tracing which provides full stack traces at runtime with source file, line and column info.  
- Single and Multi project config files.  
- Specify 1 or more output paths to automatically update addon's script.  
- TODO: Custom build actions.  
- TODO: vscode task template.  
- TODO: Additional configurable options (changing emitter config).  

Note that Linux is not supported properly yet, but should be in the future.  
MacOS will not be officially supported, but if you have any issues feel free to make an issue on this repo.  

## [Releases](https://github.com/Avril112113/SSSWTool/releases)
See the [releases](https://github.com/Avril112113/SSSWTool/releases) for download.  
If you want to use `ssswtool` from anywhere, consider adding it to your PATH (the directory containing `ssswtool.bat`).  
See (usage)[#Usage] for how to use this tool.  

## Usage
Requires to be run in a cmd prompt.  
If `ssswtool` was added to your PATH, you can use `ssswtool` directly, otherwise replace it with the path to `ssswtool.bat`.  

1. Create a new project with `ssswtool new addon ./some_addon_name`.  
2. Enter the new directory `cd ./some_addon_name`.  
3. Edit `script.lua`, any files `require`d from here will be included into the output.  
4. Build with `ssswtool build ./`.  
   The default output directory is `<PROJECT_DIR>/_build/script.lua`.  
   It will also output to `<SW_SAVEDATA>/data/missions/<PROJECT_NAME>/script.lua` if the directory exists.  
You may edit `ssswtool.json` to customize the build process, [see below](#json-config-format).  

You may replace `build` with `watch`, which will re-build your addon automatically when any changes are detected.  
Do be careful when modifying `ssswtool.json` while `watch` is running.  

## JSON Config format
This section describes the format of `ssswtool.json` and any referenced configs by it.  
NOTE that comments are not supported, they must be removed from the examples to utilize them.

Basic usage example (values represent default)  
```jsonc
{
	// "name" defaults to the containing directory name if not provided.
	"name": "some_addon",
	// "entrypoint" defaults to "script.lua" if not provided.
	"entrypoint": "script.lua",
	// Required, specifies where to look for entrypoint and for `require()`
	// This can be an array, eg [".", "/PATH/TO/SOME/LIB"]
	"src": ".",
	"transformers": {
		// The combiner makes `require()` work by including files and providing a custom
		// implementation of `require()`, which works similar to standalone Lua.
		"combiner": true,
		// Tracing add compile time tracing information which is used to
		// generate stack traces with correct file names and line numbers in-game.
		// This should be `false` for releases
		// as it affects runtime performance and will greatly impact the output size.
		"tracing": false
	}
}
```

Multi-Project and config reference example
```jsonc
// Multi project configs start with an array.
[
	// Refer to another project's config.
	// It doesn't strictly need to be named `ssswtool.json`, but it is highly recommended to be.
	"./other_project/ssswtool.json",
	// Or just provide a normal config.
	{
		// "name" becomes a required field.
		"name": "some_addon",
		"src": ".",
		"transformers": {
			"combiner": true,
			"tracing": false
		}
	}
]
```

**Pre-Built Binaries:**  
Releases contain [`luajit`](https://luajit.org/) pre-built for windows x64 (deleting it will use system version instead).  

The following can be found in `SelenScript/libs`:  
\- [`lfs`/`luafilesystem`](https://luarocks.org/modules/hisham/luafilesystem)  
\- [`lpeglabel`](https://luarocks.org/modules/sergio-medeiros/lpeglabel)  
\- [`luanotify`](https://github.com/Avril112113/luanotify)  
