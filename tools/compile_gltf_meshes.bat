@echo off
SETLOCAL

cd external\The-Forge\Common_3\Tools\AssetPipeline\Win64\x64\Release

echo "Compiling glTF 2.0 models..."

AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\environment\terrain\ --output ..\..\..\..\..\..\..\..\content\prefabs\environment\terrain\theforge

ENDLOCAL