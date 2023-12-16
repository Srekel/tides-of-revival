@echo off
SETLOCAL

cd external\zig-gamedev\libs\zwin32\bin\x64
echo Compiling shaders...

REM Use The-Forge shader flags when compiling HSLS shaders
dxc.exe "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\src\Shaders\HLSL\terrain.vert.hlsl" -Fo "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\PC Visual Studio 2019\x64\Debug\content\compiled_shaders\DIRECT3D12\terrain.vert" -E main -T vs_6_6 -WX -Ges -O3
dxc.exe "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\src\Shaders\HLSL\terrain.frag.hlsl" -Fo "..\..\..\..\..\The-Forge\Examples_3\TidesRenderer\PC Visual Studio 2019\x64\Debug\content\compiled_shaders\DIRECT3D12\terrain.frag" -E main -T ps_6_6 -WX -Ges -O3

exit /b 0

ENDLOCAL