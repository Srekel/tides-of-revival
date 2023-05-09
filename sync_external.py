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
        "b5ccdb1bafe6b3f59f84f275fb82603265bedc88",
    )
    sync_lib(
        "zig-args",
        "https://github.com/MasterQ32/zig-args.git",
        "cce1b8987723c155d1fa61c4e6cac717074a2e74",
    )
    sync_lib(
        "zig-gamedev",
        "https://github.com/Srekel/zig-gamedev.git",
        "86bc3b5092c33b823c6ea1d1f22d5cb6782f3a69",
    )
    sync_lib(
        "zig-flecs",
        "https://github.com/Srekel/zig-flecs.git",
        "fe1f47d99ebd7495b16e4e56011426cd408138dc",
    )
    sync_lib(
        "zigimg",
        "https://github.com/zigimg/zigimg.git",
        "d60a391d062eb0a0e4aa9072ae752bb9ac31e917",
    )
    # sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")

    sync_zig_exe("0.11.0-dev.2892+fd6200eda")

    os.chdir("..")
    print("Done syncing external!")


if __name__ == "__main__":
    main()
    print("Press enter...")
    input()
