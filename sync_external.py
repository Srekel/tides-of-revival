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
sync_lib("zig-args", "https://github.com/MasterQ32/zig-args.git", "b91e056f8ab9a995ab7f10577c89af3cb493db40")
# sync_lib("zig-flecs", "https://github.com/prime31/zig-flecs.git")
sync_lib("zig-flecs", "https://github.com/Srekel/zig-flecs.git", "e9a1dfb524bc37ea8aa6bdaac46a5f91c8c4ce85")
sync_lib("zig-gamedev", "https://github.com/Srekel/zig-gamedev.git", "5f11a151b23b1e3886c7c6bc0cef0cacdb5d2dca")
sync_lib("zigimg", "https://github.com/zigimg/zigimg.git", "e57148bf6c6df395ef308e559ec833639940220c")
# sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")
os.chdir("..")

print("Done")
input()
