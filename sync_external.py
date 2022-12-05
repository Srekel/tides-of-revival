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
sync_lib("zig-flecs", "https://github.com/Srekel/zig-flecs.git", "08b50bda74c84a485151cb451917d3b3c38cc997")
sync_lib("zig-gamedev", "https://github.com/michal-z/zig-gamedev.git", "1ab179c0523ae1de154095c98bea9f1f94d28433")
sync_lib("zigimg", "https://github.com/zigimg/zigimg.git", "64d04a63814b54301182194dadccd1f28c91906d")
# sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")
os.chdir("..")

print("Done")
input()
