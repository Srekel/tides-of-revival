import os
import sys

# todo: specify version
def sync_lib(folder, gitpath):
    print("----",folder,"----")
    if not os.path.isdir(folder):
        os.system("git clone " + gitpath)
    os.chdir(folder)
    os.system("git pull")
    os.chdir("..")


os.chdir("external")
sync_lib("zig-args", "https://github.com/MasterQ32/zig-args.git")
sync_lib("zig-flecs", "https://github.com/prime31/zig-flecs.git")
sync_lib("zig-gamedev", "https://github.com/michal-z/zig-gamedev.git")
sync_lib("zigimg", "https://github.com/zigimg/zigimg.git")
os.chdir("..")
