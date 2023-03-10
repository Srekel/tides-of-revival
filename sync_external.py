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
sync_lib("zig-args", "https://github.com/MasterQ32/zig-args.git", "c84f9709405b31ef3e72ab26b20ba3c37826f8ec")
# sync_lib("zig-flecs", "https://github.com/prime31/zig-flecs.git")
sync_lib("zig-gamedev", "https://github.com/Srekel/zig-gamedev.git", "e0ceda4d9fd5ef8ace3d176ecb6a32e05a296c8d")
sync_lib("zig-flecs", "https://github.com/Srekel/zig-flecs.git", "fe1f47d99ebd7495b16e4e56011426cd408138dc")
sync_lib("zigimg", "https://github.com/zigimg/zigimg.git", "caba7e5646516bb5ed01d84a1afb0c4605395de7")
# sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")
os.chdir("..")

print("Done")
input()
