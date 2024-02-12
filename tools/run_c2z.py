import os
import subprocess


def generate(header_filepath):
    # assume we're at /external
    external_path = os.getcwd()

    header_filename = os.path.basename(header_filepath)
    header_folderpath = os.path.dirname(header_filepath)
    os.chdir(header_folderpath)

    path_to_external = os.path.relpath(external_path, header_folderpath)
    path_to_c2z = os.path.join(path_to_external, "c2z", "zig-out", "bin", "c2z")
    # print(path_to_c2z)

    print("-------------------------")
    print("Generating", header_filename)
    print(header_folderpath)
    print("-------------------------")
    subprocess.run(
        [
            path_to_c2z,
            header_filename,
        ],
        cwd=".",
        capture_output=False,
        text=True,
    )

    # Back down to external...
    os.chdir(external_path)


def build_c2z():
    # assume we're at /external
    os.chdir("c2z")

    print("Building c2z...")
    subprocess.run(
        [
            "zig",
            "build",
            # "-Dtarget=native-native-msvc",
            # "--summary",
            # "failures",
        ],
        cwd=".",
        capture_output=False,
        text=True,
    )

    # Back down to external...
    os.chdir("..")


def run():
    cwd = os.getcwd()
    if os.path.exists("run_c2z.py"):
        os.chdir("..")

    if os.path.exists("external"):
        os.chdir("external")

    build_c2z()

    headers = [
        # os.path.join("zig-recastnavigation", "Recast", "Include", "Recast.h"),
        # os.path.join("zig-recastnavigation", "Recast", "Include", "RecastAlloc.h"),
        # os.path.join("zig-recastnavigation", "Recast", "Include", "RecastAssert.h"),
        os.path.join("zig-recastnavigation", "Detour", "Include", "DetourCommon.h"),
    ]

    for header in headers:
        generate(os.path.join(os.getcwd(), header))

    os.chdir(cwd)


if __name__ == "__main__":
    run()

    print("Done")
    a = input()
