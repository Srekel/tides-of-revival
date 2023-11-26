import os
import subprocess
import platform
# import sys
import shutil
# import filecmp
import build_licenses

build_licenses.build_licenses()

release = "March_of_the_Ants"
build = "Final"

os.chdir("..")

# Can't use ReleaseSafe due to bug in Zig:
# https://github.com/ziglang/zig/issues/17529
os.system("zig build -Dtarget=native-native-msvc  -Doptimize=Debug --summary failures")
# os.system("zig build  -Doptimize=ReleaseSafe  -Dtarget=native-native-msvc -Dcpu=baseline")

release_name = f"Tides_of_Revival_{release}_{build}"
dest_path = os.path.join("release_build", release_name)
os.makedirs(dest_path, exist_ok=True)
# os.removedirs(dest_path)


if platform.system() == "Windows":
    print("Copying zig-out/bin")
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
    
    print("Copying content/audio")
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

print("Copying license")
shutil.copyfile(
    os.path.join("licenses.txt"),
    os.path.join(dest_path, "licenses.txt"),
)

print("Zipping to", release_name + ".zip")
shutil.make_archive(os.path.join("release_build", release_name), 'zip', dest_path)

os.chdir("tools")
