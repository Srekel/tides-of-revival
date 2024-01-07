@echo off
SETLOCAL

cd external\The-Forge\Common_3\Tools\AssetPipeline\Win64\x64\Release

echo "Compiling glTF 2.0 models..."

REM AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\characters\player\ --output ..\..\..\..\..\..\..\..\content\prefabs\characters\player\theforge
REM AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\creatures\giant_ant\ --output ..\..\..\..\..\..\..\..\content\prefabs\creatures\giant_ant\theforge
REM AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\creatures\spider\ --output ..\..\..\..\..\..\..\..\content\prefabs\creatures\spider\theforge
REM AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\creatures\spider\ --output ..\..\..\..\..\..\..\..\content\prefabs\creatures\spider\theforge
REM AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\environment\terrain\ --output ..\..\..\..\..\..\..\..\content\prefabs\environment\terrain\theforge
REM AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\primitives\ --output ..\..\..\..\..\..\..\..\content\prefabs\primitives\theforge
REM AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\props\bow_arrow\ --output ..\..\..\..\..\..\..\..\content\prefabs\props\bow_arrow\theforge
REM AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\props\damaged_helmet\ --output ..\..\..\..\..\..\..\..\content\prefabs\props\damaged_helmet\theforge
REM AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\content\prefabs\props\debug_sphere\ --output ..\..\..\..\..\..\..\..\content\prefabs\props\debug_sphere\theforge
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\ --output ..\..\..\..\..\..\..\..\content\meshes
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\..\tides-rpg-source-assets\environment\trees\fir\exports\ --output ..\..\..\..\..\..\..\..\content\meshes
AssetPipelineCmd.exe -pgltf --input ..\..\..\..\..\..\..\..\..\tides-rpg-source-assets\art_bible\pbr\exports\ --output ..\..\..\..\..\..\..\..\content\meshes

ENDLOCAL