import os
import subprocess
import sys

sys.path.insert(0, os.path.join("..", "external", "zig-recastnavigation"))
import generate_recast_bindings_c2z


class Header:
    def __init__(self, project_root_path, filepath, includes=None):
        self.project_root_path = project_root_path
        self.filepath = filepath
        self.includes = includes or []


headers = [
    ###
    ### im3d
    ###
    Header(
        os.path.join("zig-im3d"),
        os.path.join("im3d.h"),
    ),
]


# generation
def generate(c2z_exe_path, project_root_path, header):
    print("/////////////////////////")
    print("Generating", header.filepath)
    print("Includes:", header.includes)
    print("Root path:", project_root_path)
    print("c2z path:", c2z_exe_path)

    header_filename = os.path.join(project_root_path, header.filepath)
    print("Full path:", header_filename)
    header_folderpath = os.path.dirname(header_filename)
    os.chdir(header_folderpath)

    print("In folder:", header_folderpath)
    print("-------------------------")

    run_params = []
    run_params.append(c2z_exe_path)
    for include_path in header.includes:
        run_params.append("-I" + include_path)

    run_params.append(header_filename)

    subprocess.run(
        run_params,
        cwd=".",
        capture_output=False,
        text=True,
    )

    print("\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\")

    # Back down to external...
    os.chdir(project_root_path)


#  setup & run
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
    for header in generate_recast_bindings_c2z.get_headers():
        generate_recast_bindings_c2z.generate(
            c2z_exe_path,
            project_root_path,
            header,
        )

    for header in headers:
        generate(
            c2z_exe_path, os.path.join(os.getcwd(), header.project_root_path), header
        )

    os.chdir(cwd)


if __name__ == "__main__":
    run()

    print("")
    print("Done, press enter!")
    a = input()
