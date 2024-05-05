# SSSWTool
A tool to build Stormworks addons with ease.  
See below for what this tool can do thanks to utilizing [SelenScript](https://github.com/Avril112113/selenscript).  

This project is currently **VERY work in progress**, it's lacking various features.  
As it is right now, it's not considered a replacement for other tools until further testing and features has been finished.  

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
Run `ssswtool.bat` either directly or just `ssswtool` if it's on your PATH.  
The file `script.lua` is the default entrypoint, any files `require()` from there will be included into the output.  
Build with `ssswtool build ./`.  
The default output directory is `<CWD_OR_CONFIG_DIR>/_build/script.lua`.  
You may create a `ssswtool.json` to customize the build process, it is high recommended to create this, see [below on how to set it up](#json-config-format).  

You may replace `build` with `watch`, which will build, then upon any detected changes re-build your addon automatically.  
It will detect changes even during a build (build loops will be detected and stopped).  

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
