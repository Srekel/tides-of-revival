import os
import shutil
import sync_external

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
    os.system("zig build")

def task_nuke_old_world():
    if os.path.isdir("zig-out\\bin\\content\\patch"):
        shutil.rmtree("zig-out\\bin\\content\\patch")

def task_generate_new_world():
    os.system("zig-out\\bin\\TidesOfRevival.exe --offlinegen")

def task_copy_new_world():
    shutil.copytree("content\\patch", "zig-out\\bin\\content\\patch")

print("FULL PULL: <any string> + enter")
print("GENERATE WORLD: only enter")

choice = input()
if len(choice) > 0:
    do_task("About to pull Git", task_sync_git)
    do_task("About to sync external libs and zig.exe", task_sync_external)
    do_task("You need to copy zig!", task_copy_zig)
    do_task("About to sync SVN", task_sync_svn)
    do_task("About to build game", task_build_game)
    do_task("About to nuke old game world", task_nuke_old_world)
    do_task("About to generate game world", task_generate_new_world)
    do_task("About to copy game world", task_copy_new_world)
else:
    do_task("About to nuke old game world", task_nuke_old_world, True)
    do_task("About to generate game world", task_generate_new_world, True)
    do_task("About to copy game world", task_copy_new_world, True)


print("")
print("")
print("")
print("############################")
print("        DONE")
print("############################")
print("")
print("Press enter...")
input()
