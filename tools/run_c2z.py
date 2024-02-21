import os
import subprocess
import sys

sys.path.insert(0, os.path.join("..", "external", "zig-recastnavigation"))
import generate_bindings_c2z


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

    c2z_exe_path = os.path.abspath(
        os.path.join(os.getcwd(), "c2z", "zig-out", "bin", "c2z")
    )
    project_root_path = os.path.join(os.getcwd(), "zig-recastnavigation")
    for header in generate_bindings_c2z.get_headers():
        generate_bindings_c2z.generate(
            c2z_exe_path,
            project_root_path,
            header,
        )

    os.chdir(cwd)


if __name__ == "__main__":
    run()

    print("")
    print("Done, press enter!")
    a = input()
