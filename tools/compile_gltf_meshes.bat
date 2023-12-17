@echo off
SETLOCAL

cd external\The-Forge\Common_3\Tools\AssetPipeline\Win64\x64\Release

echo "Compiling glTF 2.0 models..."

AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\buildings\medium_house\ --output ..\..\..\..\..\..\..\..\content\prefabs\buildings\medium_house\theforge
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\characters\player\ --output ..\..\..\..\..\..\..\..\content\prefabs\characters\player\theforge
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\creatures\giant_ant\ --output ..\..\..\..\..\..\..\..\content\prefabs\creatures\giant_ant\theforge
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\creatures\spider\ --output ..\..\..\..\..\..\..\..\content\prefabs\creatures\spider\theforge
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\creatures\spider\ --output ..\..\..\..\..\..\..\..\content\prefabs\creatures\spider\theforge
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\environment\fir\ --output ..\..\..\..\..\..\..\..\content\prefabs\environment\fir\theforge
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\environment\terrain\ --output ..\..\..\..\..\..\..\..\content\prefabs\environment\terrain\theforge
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\primitives\ --output ..\..\..\..\..\..\..\..\content\prefabs\primitives\theforge
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\props\bow_arrow\ --output ..\..\..\..\..\..\..\..\content\prefabs\props\bow_arrow\theforge
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\props\damaged_helmet\ --output ..\..\..\..\..\..\..\..\content\prefabs\props\damaged_helmet\theforge
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\props\debug_sphere\ --output ..\..\..\..\..\..\..\..\content\prefabs\props\debug_sphere\theforge

ENDLOCAL