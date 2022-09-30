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
    # os.system("git pull " + commit_sha)
    os.chdir("..")


os.chdir("external")
sync_lib("zig-args", "https://github.com/MasterQ32/zig-args.git", "master")
# sync_lib("zig-flecs", "https://github.com/prime31/zig-flecs.git")
sync_lib("zig-flecs", "https://github.com/Srekel/zig-flecs.git", "0cd280d9cc254b3e3634b90ea6d749a89b4c9610")
sync_lib("zig-gamedev", "https://github.com/michal-z/zig-gamedev.git", "d95d8b08f5744daf1c4b6ce9ea0038640bed04be")
sync_lib("zigimg", "https://github.com/zigimg/zigimg.git", "fff6ea92a00c5f6092b896d754a932b8b88149ff")
# sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")
os.chdir("..")

print("Done")
input()