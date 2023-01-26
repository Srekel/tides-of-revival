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


os.chdir("external")
sync_lib("zig-args", "https://github.com/MasterQ32/zig-args.git", "77a2c6557bb9768dc332f98cc6cbc9eac94c93aa")
# sync_lib("zig-flecs", "https://github.com/prime31/zig-flecs.git")
sync_lib("zig-gamedev", "https://github.com/Srekel/zig-gamedev.git", "38ec3e469afd9b882a59da3edb67a1f0f27b47b5")
sync_lib("zig-flecs", "https://github.com/Srekel/zig-flecs.git", "8cbf441c7d508f11da40ff80ec72df94c36920e1")
sync_lib("zigimg", "https://github.com/zigimg/zigimg.git", "5e8e5687ce1edd7dd1040c0580ec0731bcfbd793")
# sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")
os.chdir("..")

print("Done")
input()
