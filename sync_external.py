import os
import sys
import subprocess
import urllib.request

def sync_lib(folder, git_path, commit_sha):
    print()
    print("-" * (2 * 4 + len(folder) + 2))
    print("----", folder, "----")
    print("-" * (2 * 4 + len(folder) + 2))
    print("Origin:", git_path)
    if not os.path.isdir(folder):
        os.system("git clone " + git_path)
    os.chdir(folder)
    os.system("git fetch")
    result = subprocess.run(["git", "rev-parse", "HEAD"], cwd=".", capture_output=True, text=True)
    current_hash = result.stdout.strip()
    if current_hash == commit_sha:
        print("Already at commit", commit_sha)
        os.chdir("..")
        return

    print("Current commit:", current_hash)
    print("Wanted commit: ", commit_sha)
    if os.path.exists(os.path.join(".git", "refs", "heads", "main")):
        os.system("git checkout main")
    else:
        os.system("git checkout master")
    os.system("git pull")
    os.system("git submodule update --init --recursive")
    os.system("git checkout " + commit_sha)

    os.chdir("..")


def sync_zig_exe(build):
    print()
    print("-------------")
    print("---- ZIG ----")
    print("-------------")
    print("Downloading build", build)
    filename = "zig-windows-x86_64-" + build + ".zip"
    if os.path.isfile(filename):
        print("...already found: external/" + filename)
        return
    url = "https://ziglang.org/builds/" + filename
    urllib.request.urlretrieve(url, filename)
    print("...saved at: external/" + filename)
    print("Important: You need to copy this over your existing zig.exe")


def main():
    print("Syncing external...")
    external_dir = "external"
    if not os.path.isdir(external_dir):
        os.mkdir(external_dir)
    os.chdir(external_dir)

    sync_lib(
        "websocket.zig",
        "https://github.com/karlseguin/websocket.zig.git",
        "a7a1d1990605bebdec38c1bacf00b1e7a3cbc371",
    )
    sync_lib(
        "zig-args",
        "https://github.com/MasterQ32/zig-args.git",
        "53f9b53d7bebe9baad52ed4d505b480540344946",
    )
    sync_lib(
        "zig-gamedev",
        "https://github.com/Srekel/zig-gamedev.git",
        "6ff65ed35758837d6f8bb38a36ae896a779e0a19",
    )
    sync_lib(
        "zig-flecs",
        "https://github.com/Srekel/zig-flecs.git",
        "d634e86f0bb03e0c858c270cd2d5ba4f9cb8ffc1",
    )
    sync_lib(
        "zigimg",
        "https://github.com/zigimg/zigimg.git",
        "f9553b0656d2c80e18c19966c75690e3f59c633e",
    )
    # sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")

    sync_zig_exe("0.11.0-dev.3859+88284c124")

    os.chdir("..")
    print("Done syncing external!")


if __name__ == "__main__":
    main()
    print("Press enter...")
    input()
