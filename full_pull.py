import os
import sys
import shutil
import subprocess
import sync_external

from pathlib import Path


class bcolors:
    HEADER = "\033[95m"
    OKBLUE = "\033[94m"
    OKCYAN = "\033[96m"
    OKGREEN = "\033[92m"
    WARNING = "\033[93m"
    FAIL = "\033[91m"
    ENDC = "\033[0m"
    BOLD = "\033[1m"
    UNDERLINE = "\033[4m"


def do_task(text, task_func, skip_confirm=False):
    print("")
    print("")
    print(bcolors.OKCYAN + "#" * len(text) + bcolors.ENDC)
    print(bcolors.OKCYAN + text + bcolors.ENDC)
    if not skip_confirm:
        print(bcolors.OKGREEN + "Press enter..." + bcolors.ENDC)
        input()
    task_func()


script_path = os.path.dirname(os.path.realpath(__file__))
tools_path = os.path.join(script_path, "tools")
tools_binaries_path = os.path.join(tools_path, "binaries")
zig_path = os.path.join(tools_binaries_path, "zigup", "zig.exe")
simulator_root = os.path.join(tools_path, "simulator")
simulator_path = os.path.join(simulator_root, "zig-out", "bin", "Simulator.exe")
asset_cooker_path = os.path.join(tools_binaries_path, "AssetCooker", "AssetCooker.exe")

# TASKS


def task_sync_build_tools():
    build_tools_path = os.path.join(os.path.abspath(os.curdir), "tools", "external", "msvc_BuildTools")
    if not os.path.isdir(build_tools_path):
        subprocess.run(
            [
                "tools/binaries/vs_BuildTools.exe",
                "--installPath",
                build_tools_path,
                "--add",
                "Microsoft.VisualStudio.Component.VC.Tools.x86.x64;includeOptional",
                "--add",
                "Microsoft.VisualStudio.Component.VC.CoreBuildTools",
                "--add",
                "Microsoft.VisualStudio.Component.VC.CoreIde",
                "--add",
                "Microsoft.VisualStudio.Component.VC.Redist.14.Latest",
                "--add",
                "Microsoft.VisualStudio.Component.Windows11SDK.26100;includeOptional",
                "--nickname",
                "TidesRPG"
            ],
            cwd=".",
        )


def task_sync_git():
    os.system("git pull")


def task_sync_external():
    sync_external.main()


def task_sync_svn():
    if not os.path.exists(os.path.join(script_path, ".svn")):
        print("You need to download, install, and clone SVN.")
        print("Then restart thiss script.")
        print("Note: If you don't have a user/pw, poke Anders. (Srekel)")
        input()
        sys.exit(0)

    os.system("svn update")


def task_start_asset_cooker():
    os.startfile(asset_cooker_path, cwd=os.path.dirname(asset_cooker_path))


def task_build_game():
    # Path(os.path.join("zig-out", "bin", "content", "systems")).mkdir(
    #     parents=True, exist_ok=True
    # )
    # os.system("zig build")
    print(zig_path)
    subprocess.run(
        [
            zig_path,
            "build",
            "-Dtarget=native-native-msvc",
            "--summary",
            "failures",
        ],
        cwd=script_path,
        capture_output=False,
        text=True,
    )


def task_build_simulator():
    # Path(os.path.join("zig-out", "bin", "content", "systems")).mkdir(
    #     parents=True, exist_ok=True
    # )
    # os.system("zig build")
    subprocess.run(
        [
            zig_path,
            "build",
            # "-Dtarget=native-native-msvc",
            "-Doptimize=ReleaseFast",
            "--summary",
            "failures",
        ],
        cwd=simulator_root,
        capture_output=False,
        text=True,
    )


def task_nuke_cache():
    if os.path.isdir("zig-cache"):
        shutil.rmtree(".zig-cache")


def task_nuke_old_world():
    path = os.path.join("zig-out", "bin", "content", "patch")
    if os.path.isdir(path):
        shutil.rmtree(path)


def task_generate_new_world():
    os.startfile(simulator_path, cwd=os.path.dirname(simulator_path))


print("")
print("Performing: Full Pull")
print("")

do_task("Pulling Git...", task_sync_git)
do_task("Syncing external libs and zig.exe...", task_sync_external)
do_task("Acquiring MSVC BuildTools!", task_sync_build_tools)
do_task("Syncing SVN...", task_sync_svn)
do_task("Building game...", task_build_game)
do_task("Building simulator...", task_build_simulator)
do_task("Starting asset cooker...", task_start_asset_cooker)
do_task("Generating game world...", task_generate_new_world)

print("")
print("")
print("")
print("############################")
print("        DONE")
print("############################")
print("")
