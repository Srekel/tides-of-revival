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
sync_lib("zig-args", "https://github.com/MasterQ32/zig-args.git", "1ff417ac1f31f8dbee3a31e5973b46286d42e71d")
# sync_lib("zig-flecs", "https://github.com/prime31/zig-flecs.git")
sync_lib("zig-flecs", "https://github.com/Srekel/zig-flecs.git", "8a013623e3cf2c0e7884a3185bcb8d1670ec9b70")
sync_lib("zig-gamedev", "https://github.com/michal-z/zig-gamedev.git", "9dd09272ee86509acd2c66f349cfb795fdb0e904")
sync_lib("zigimg", "https://github.com/zigimg/zigimg.git", "a224b3c942d48dbf580a75f2f87de16046cb335f")
# sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")
os.chdir("..")

print("Done")
input()
