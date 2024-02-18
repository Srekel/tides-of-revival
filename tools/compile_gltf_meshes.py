import os
import subprocess
import platform

def compile_model(path):
    output_path = os.path.join("zig-out", "bin", "content", "prefabs", path)
    os.makedirs(output_path, exist_ok=True)

    subprocess.run(
        [
            "AssetPipelineCmd.exe",
            "-pgltf",
            "--input",
            os.path.join("..", "..", "..", "content", "prefabs", path),
            "--output",
            os.path.join("..", "..", "..", output_path),
        ],
        cwd="./tools/binaries/asset_pipeline",
        shell=True,
    )

if platform.system() == "Windows":
    print("Compiling glTF 2.0 Models")
    compile_model(os.path.join("buildings", "medium_house"))
    compile_model(os.path.join("characters", "player"))
    compile_model(os.path.join("creatures", "giant_ant"))
    compile_model(os.path.join("environment", "fir"))
    compile_model(os.path.join("environment", "terrain"))
    compile_model(os.path.join("primitives"))
    compile_model(os.path.join("props", "bow_arrow"))
    compile_model(os.path.join("props", "debug_sphere"))
