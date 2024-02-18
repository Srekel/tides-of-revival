import os
import subprocess
import platform

def compile_shader(input_filename, output_filename, shader_type):
    subprocess.run(
        [
            "dxc.exe",
            os.path.join("..", "..", "src", "shaders", "HLSL", input_filename),
            "-Fo",
            os.path.join("..", "..", "zig-out", "bin", "content", "compiled_shaders", "DIRECT3D12", output_filename),
            "-E",
            "main",
            "-T",
            shader_type + "_6_6",
            "-WX",
            "-Ges",
            "-O3",
        ],
        cwd="./binaries/dxc",
        shell=True,
    )

if platform.system() == "Windows":
    os.makedirs(os.path.join("zig-out", "bin", "content", "compiled_shaders", "DIRECT3D12"), exist_ok=True)

    print("Compiling HLSL Shaders")
    compile_shader("skybox.vert.hlsl", "skybox.vert", "vs")
    compile_shader("skybox.frag.hlsl", "skybox.frag", "ps")
    compile_shader("terrain.vert.hlsl", "terrain.vert", "vs")
    compile_shader("terrain.frag.hlsl", "terrain.frag", "ps")
    compile_shader("lit.vert.hlsl", "lit.vert", "vs")
    compile_shader("lit_opaque.frag.hlsl", "lit_opaque.frag", "ps")
    compile_shader("lit_masked.frag.hlsl", "lit_masked.frag", "ps")
    compile_shader("fullscreen.vert.hlsl", "fullscreen.vert", "vs")
    compile_shader("deferred_shading.frag.hlsl", "deferred_shading.frag", "ps")
    compile_shader("tonemapper.frag.hlsl", "tonemapper.frag", "ps")