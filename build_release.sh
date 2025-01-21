shopt -s globstar


rm -rf ./release/
rm -f ./SSSWTool-linux.zip
mkdir ./release/

cp "./main.lua" "./release/main.lua"
cp "./ssswtool.sh" "./release/ssswtool.sh"
cp -r "./tool" "./release/tool"

mkdir "./release/SelenScript"
cp -r "../SelenScript/libs" "./release/SelenScript/libs"
rm -rf ./release/SelenScript/libs/**/*.dll
cp -r "../SelenScript/SelenScript" "./release/SelenScript/SelenScript"

# Delete dev-only libs.
rm -rf ./release/SelenScript/libs/avflamegraph

# Linux builds don't provide luajit 

(cd ./release/ && zip -r ../SSSWTool-linux.zip ./*)
