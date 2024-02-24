import os
import sys
import shutil
import subprocess
import sync_external
import platform
import filecmp

from pathlib import Path


def do_task(text, task_func, skip_confirm=False):
    print("")
    print("")
    print("#" * len(text))
    print(text)
    if not skip_confirm:
        print("Press enter...")
        input()
    task_func()


# TASKS


def task_sync_build_tools():
    script_path = os.path.dirname(os.path.realpath(__file__))
    build_tools_path = os.path.join(script_path, "tools", "external", "msvc_BuildTools")
    if not os.path.isdir(build_tools_path):
        component_ids = "Microsoft.VisualStudio.Component.VC.CoreBuildTools Microsoft.VisualStudio.Component.VC.CoreIde Microsoft.VisualStudio.Component.VC.Redist.14.Latest Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
        subprocess.run(
            [
                "tools/binaries/vs_BuildTools.exe",
                "--installPath",
                build_tools_path,
                "--add",
                component_ids,
            ],
            cwd=".",
        )

def task_sync_git():
    os.system("git pull")


def task_sync_external():
    sync_external.main()


def task_copy_zig():
    pass


def task_sync_svn():
    os.system("svn update")


def task_build_game():
    Path(os.path.join("zig-out", "bin", "content", "systems")).mkdir(
        parents=True, exist_ok=True
    )
    # os.system("zig build")
    subprocess.run(
        [
            "zig",
            "build",
            "-Dtarget=native-native-msvc",
            "--summary",
            "failures",
        ],
        cwd=".",
        capture_output=False,
        text=True,
    )


def task_nuke_cache():
    if os.path.isdir("zig-cache"):
        shutil.rmtree("zig-cache")


def task_nuke_old_world():
    path = os.path.join("zig-out", "bin", "content", "patch")
    if os.path.isdir(path):
        shutil.rmtree(path)


def task_generate_new_world():
    path = os.path.join("zig-out", "bin", "TidesOfRevival.exe")
    os.system(path + " --offlinegen")


def task_sync_world():
    if platform.system() == "Windows":
        subprocess.run(
            [
                "robocopy",
                os.path.join("content", "patch"),
                os.path.join("zig-out", "bin", "content", "patch"),
                "/MIR",
                "/MT:4",
            ],
            cwd=".",
            capture_output=False,
            text=True,
        )
    else:
        # https://stackoverflow.com/questions/22493492/compare-directories-delete-leftover-files-copy-new-ones
        src = os.path.join("content", "patch")
        dst = os.path.join("zig-out", "bin", "content", "patch")
        for src_root, src_dirs, src_files in os.walk(src, topdown=True):
            dst_root = os.path.join(dst, os.path.relpath(src_root, src))
            dirs = filecmp.dircmp(src_root, dst_root)
            for item in dirs.right_only:
                print("Removing " + item)
                dst_path = os.path.join(dst_root, item)
                if os.path.isdir(dst_path):
                    shutil.rmtree(dst_path)
                else:
                    os.remove(dst_path)
            for item in dirs.left_only:
                print("Adding " + item)
                src_path = os.path.join(src_root, item)
                if os.path.isdir(src_path):
                    shutil.copytree(src_path, os.path.join(dst_root, item))
                else:
                    shutil.copy2(src_path, os.path.join(dst_root, item))


# def task_copy_new_world():
#     shutil.copytree("content\\patch", "zig-out\\bin\\content\\patch")


build = "Ask"
has_arg = len(sys.argv) > 1
if has_arg and sys.argv[1] == "--world-gen":
    build = "World Gen"

if build == "Ask":
    print("FULL PULL:      <any string> + enter")
    print("GENERATE WORLD: only enter")
    choice = input()
    build = "World Gen"
    if len(choice) > 0:
        build = "Full Pull"

print("")
print("Performing:", build)
print("")

if build == "Full Pull":
    do_task("Pulling Git...", task_sync_git)
    do_task("Syncing external libs and zig.exe...", task_sync_external)
    do_task("You need to copy zig!", task_copy_zig)
    do_task("Acquiring MSVC BuildTools!", task_sync_build_tools)
    do_task("Syncing SVN...", task_sync_svn)
    do_task("Nuking cache...", task_nuke_cache)
    do_task("Nuking game world...", task_nuke_old_world)
    do_task("Building game...", task_build_game)
    do_task("Generating game world...", task_generate_new_world)
    do_task("Copying game world...", task_sync_world)
elif build == "World Gen":
    do_task("Building game...", task_build_game, True)
    do_task("Nuking game world...", task_nuke_old_world, True)
    do_task("Generating game world...", task_generate_new_world, True)
    do_task("Copying game world...", task_sync_world, True)


print("")
print("")
print("")
print("############################")
print("        DONE")
print("############################")
print("")
if not has_arg:
    print("Press enter...")
    input()
