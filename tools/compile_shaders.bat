@echo off
SETLOCAL

cd external\zig-gamedev\libs\zwin32\bin\x64
echo Compiling shaders...

REM Use The-Forge shader flags when compiling HSLS shaders
dxc.exe "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\src\Shaders\HLSL\terrain.vert.hlsl" -Fo "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\PC Visual Studio 2019\x64\Debug\content\compiled_shaders\DIRECT3D12\terrain.vert" -E main -T vs_6_6 -WX -Ges -O3
copy "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\PC Visual Studio 2019\x64\Debug\content\compiled_shaders\DIRECT3D12\terrain.vert" "..\..\..\..\..\..\zig-out\bin\content\compiled_shaders\DIRECT3D12\terrain.vert"
dxc.exe "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\src\Shaders\HLSL\terrain.frag.hlsl" -Fo "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\PC Visual Studio 2019\x64\Debug\content\compiled_shaders\DIRECT3D12\terrain.frag" -E main -T ps_6_6 -WX -Ges -O3
copy "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\PC Visual Studio 2019\x64\Debug\content\compiled_shaders\DIRECT3D12\terrain.frag" "..\..\..\..\..\..\zig-out\bin\content\compiled_shaders\DIRECT3D12\terrain.frag"
dxc.exe "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\src\Shaders\HLSL\lit.vert.hlsl" -Fo "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\PC Visual Studio 2019\x64\Debug\content\compiled_shaders\DIRECT3D12\lit.vert" -E main -T vs_6_6 -WX -Ges -O3
copy "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\PC Visual Studio 2019\x64\Debug\content\compiled_shaders\DIRECT3D12\lit.vert" "..\..\..\..\..\..\zig-out\bin\content\compiled_shaders\DIRECT3D12\lit.vert"
dxc.exe "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\src\Shaders\HLSL\lit_opaque.frag.hlsl" -Fo "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\PC Visual Studio 2019\x64\Debug\content\compiled_shaders\DIRECT3D12\lit_opaque.frag" -E main -T ps_6_6 -WX -Ges -O3
copy "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\PC Visual Studio 2019\x64\Debug\content\compiled_shaders\DIRECT3D12\lit_opaque.frag" "..\..\..\..\..\..\zig-out\bin\content\compiled_shaders\DIRECT3D12\lit_opaque.frag"
dxc.exe "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\src\Shaders\HLSL\lit_masked.frag.hlsl" -Fo "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\PC Visual Studio 2019\x64\Debug\content\compiled_shaders\DIRECT3D12\lit_masked.frag" -E main -T ps_6_6 -WX -Ges -O3
copy "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\PC Visual Studio 2019\x64\Debug\content\compiled_shaders\DIRECT3D12\lit_masked.frag" "..\..\..\..\..\..\zig-out\bin\content\compiled_shaders\DIRECT3D12\lit_masked.frag"

exit /b 0

ENDLOCAL