import os
import subprocess
import platform
from distutils.dir_util import copy_tree

def compile_texture(input_path, input_file, format):
    output_path = os.path.join("zig-out", "bin", "content", input_path)
    os.makedirs(output_path, exist_ok=True)

    subprocess.run(
        [
            "texconv.exe",
            "-y",
            "-f",
            format,
            "-o",
            os.path.join("..", "..", "..", output_path),
            os.path.join("..", "..", "..", "content", input_path, input_file),
        ],
        cwd="./tools/binaries/texconv",
        shell=True,
    )

def install_textures(textures_path):
    copy_tree(os.path.join("content", textures_path), os.path.join("zig-out", "bin", "content", textures_path))

if platform.system() == "Windows":
    print("Compiling Textures")

    install_textures(os.path.join("textures", "env"))
    install_textures(os.path.join("textures", "ui"))

    compile_texture(os.path.join("prefabs", "buildings", "medium_house"), "medium_house_plaster_albedo.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "buildings", "medium_house"), "medium_house_plaster_arm.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "buildings", "medium_house"), "medium_house_plaster_normal.png", "BC5_UNORM")
    compile_texture(os.path.join("prefabs", "buildings", "medium_house"), "medium_house_roof_albedo.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "buildings", "medium_house"), "medium_house_roof_arm.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "buildings", "medium_house"), "medium_house_roof_normal.png", "BC5_UNORM")
    compile_texture(os.path.join("prefabs", "buildings", "medium_house"), "medium_house_stone_albedo.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "buildings", "medium_house"), "medium_house_stone_arm.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "buildings", "medium_house"), "medium_house_stone_normal.png", "BC5_UNORM")
    compile_texture(os.path.join("prefabs", "buildings", "medium_house"), "medium_house_wood_albedo.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "buildings", "medium_house"), "medium_house_wood_arm.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "buildings", "medium_house"), "medium_house_wood_normal.png", "BC5_UNORM")
    compile_texture(os.path.join("prefabs", "creatures", "giant_ant"), "giant_ant_albedo.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "creatures", "giant_ant"), "giant_ant_arm.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "creatures", "giant_ant"), "giant_ant_emissive.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "creatures", "giant_ant"), "giant_ant_normal.png", "BC5_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "fir"), "fir_bark_albedo.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "fir"), "fir_branch_albedo.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "terrain"), "dry_ground_rocks_albedo.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "terrain"), "dry_ground_rocks_arm.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "terrain"), "dry_ground_rocks_normal.png", "BC5_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "terrain"), "forest_ground_01_albedo.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "terrain"), "forest_ground_01_arm.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "terrain"), "forest_ground_01_normal.png", "BC5_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "terrain"), "rock_ground_02_albedo.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "terrain"), "rock_ground_02_arm.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "terrain"), "rock_ground_02_normal.png", "BC5_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "terrain"), "snow_02_albedo.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "terrain"), "snow_02_arm.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "environment", "terrain"), "snow_02_normal.png", "BC5_UNORM")
    compile_texture(os.path.join("prefabs", "props", "bow_arrow"), "bow_arrow_albedo.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "props", "bow_arrow"), "bow_arrow_arm.png", "BC1_UNORM")
    compile_texture(os.path.join("prefabs", "props", "bow_arrow"), "bow_arrow_normal.png", "BC5_UNORM")