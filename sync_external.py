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
        "c7954efb18bb3a98999fa96dc3621162c6630d11",
    )
    sync_lib(
        "zig-args",
        "https://github.com/MasterQ32/zig-args.git",
        "7989929d055ef7618e60de84cc54644046516fdb",
    )
    sync_lib(
        "zig-gamedev",
        "https://github.com/Srekel/zig-gamedev.git",
        "7f69965ab314ad7843ba43fdd499e2e514c2154a",
    )
    # sync_lib(
    #     "zig-flecs",
    #     "https://github.com/Srekel/zig-flecs.git",
    #     "f06689bbea7d2aea0a50e05e0d171006a948e945",
    # )
    sync_lib(
        "zigimg",
        "https://github.com/zigimg/zigimg.git",
        "40ddb16fd246174545b7327a12dce7f0889ada7a",
    )
    # sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")

    sync_zig_exe("0.12.0-dev.464+a63a1c5cb")

    os.chdir("..")
    print("Done syncing external!")


if __name__ == "__main__":
    main()
    print("Press enter...")
    input()
