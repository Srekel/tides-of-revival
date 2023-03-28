import os
import sys

def sync_lib(folder, git_path, commit_sha):
    print()
    print("-" * (2*4 + len(folder) + 2))
    print("----",folder,"----")
    print("-" * (2*4 + len(folder) + 2))
    print("Origin:", git_path)
    if not os.path.isdir(folder):
        os.system("git clone " + git_path)
    os.chdir(folder)
    os.system("git pull")
    os.system("git checkout " + commit_sha)
    os.system("git submodule update --init --recursive")
    # os.system("git pull " + commit_sha)
    os.chdir("..")

external_dir = "external"
if not os.path.isdir(external_dir):
    os.mkdir(external_dir)

os.chdir(external_dir)
sync_lib("websocket.zig", "https://github.com/karlseguin/websocket.zig.git", "b5ccdb1bafe6b3f59f84f275fb82603265bedc88")
sync_lib("zig-args", "https://github.com/MasterQ32/zig-args.git", "c84f9709405b31ef3e72ab26b20ba3c37826f8ec")
sync_lib("zig-gamedev", "https://github.com/Srekel/zig-gamedev.git", "df25329d65870585d7992532cc64a382e2bcb822")
sync_lib("zig-flecs", "https://github.com/Srekel/zig-flecs.git", "fe1f47d99ebd7495b16e4e56011426cd408138dc")
sync_lib("zigimg", "https://github.com/zigimg/zigimg.git", "6d0f7d71a49b19564cf70f07577670f712cfc353")
# sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")
os.chdir("..")

print("Done")
input()
