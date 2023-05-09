import os
import sys
import shutil
import subprocess
import sync_external
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


def task_sync_git():
    os.system("git pull")


def task_sync_external():
    sync_external.main()


def task_copy_zig():
    pass


def task_sync_svn():
    os.system("svn update")


def task_build_game():
    Path(os.path.join("zig-out", "bin", "content", "systems")).mkdir(parents=True, exist_ok=True)
    os.system("zig build")


def task_nuke_cache():
    if os.path.isdir("zig-cache"):
        shutil.rmtree("zig-cache")

def task_nuke_old_world():
    if os.path.isdir("zig-out\\bin\\content\\patch"):
        shutil.rmtree("zig-out\\bin\\content\\patch")


def task_generate_new_world():
    os.system("zig-out\\bin\\TidesOfRevival.exe --offlinegen")


def task_sync_world():
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


def task_copy_new_world():
    shutil.copytree("content\\patch", "zig-out\\bin\\content\\patch")


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
