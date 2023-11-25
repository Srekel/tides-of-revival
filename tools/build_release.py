import os
import subprocess
import platform
# import sys
# import shutil
# import filecmp

release = "March_of_the_Ants"
build = "RC2"

os.chdir("..")
os.system("zig build -Dtarget=native-native-msvc  -Doptimize=Debug --summary failures")
# os.system("zig build  -Doptimize=ReleaseSafe  -Dtarget=native-native-msvc -Dcpu=baseline")

dest_path = os.path.join("release_build", f"Tides_of_Revival_{release}_{build}")
os.makedirs(dest_path, exist_ok=True)
# os.removedirs(dest_path)


if platform.system() == "Windows":
    subprocess.run(
        [
            "robocopy",
            os.path.join("zig-out", "bin"),
            dest_path,
            "/MIR",
            "/MT:4",
        ],
        cwd=".",
        capture_output=False,
        text=True,
    )
    
    subprocess.run(
        [
            "robocopy",
            os.path.join("content", "audio"),
            os.path.join(dest_path, "content", "audio"),
            "/MIR",
            "/MT:4",
        ],
        cwd=".",
        capture_output=False,
        text=True,
    )

os.chdir("tools")
