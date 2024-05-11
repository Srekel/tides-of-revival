import os
import sys
import subprocess
import urllib.request


def sync_lib(folder, git_path, commit_sha_or_branch_or_tag):
    print()
    print("-" * (2 * 4 + len(folder) + 2))
    print("----", folder, "----")
    print("-" * (2 * 4 + len(folder) + 2))
    print("Origin:", git_path)
    if not os.path.isdir(folder):
        os.system("git clone " + git_path)
    os.chdir(folder)
    os.system("git fetch")

    wanted_commit_sha = subprocess.run(
        ["git", "rev-parse", commit_sha_or_branch_or_tag],
        cwd=".",
        capture_output=True,
        text=True,
    ).stdout.strip()

    current_commit_sha = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=".", capture_output=True, text=True
    ).stdout.strip()
    if current_commit_sha == wanted_commit_sha:
        print("Already at commit", commit_sha_or_branch_or_tag, wanted_commit_sha)
        os.chdir("..")
        return

    print("Current commit:", current_commit_sha)
    print("Wanted commit: ", commit_sha_or_branch_or_tag, wanted_commit_sha)
    if os.path.exists(os.path.join(".git", "refs", "heads", "main")):
        os.system("git checkout main")
    else:
        os.system("git checkout master")
    os.system("git pull")
    os.system("git submodule update --init --recursive")
    os.system("git checkout " + commit_sha_or_branch_or_tag)

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
        "c2z",
        "https://github.com/Srekel/c2z.git",
        "5cb4b156cca9c8283150efc539c1e817eb00a05e",
    )
    sync_lib(
        "The-Forge",
        "https://github.com/gmodarelli/The-Forge.git",
        "1d23be9591b677a2c86edf218bbc8550af0a83c0",
    )
    sync_lib(
        "websocket.zig",
        "https://github.com/karlseguin/websocket.zig.git",
        "c77f87d0e6548865636eb9781106a8be72e5755a",
    )
    sync_lib(
        "wwise-zig",
        "https://github.com/Cold-Bytes-Games/wwise-zig.git",
        "4888fd81f3a905c7bb1cc5d91547503dbc0b3e1b",
    )
    sync_lib(
        "zig-args",
        "https://github.com/MasterQ32/zig-args.git",
        "adb65692a3e3e1d7ea00e4f865ef1b1718326573",
    )
    sync_lib(
        "zig-gamedev",
        "https://github.com/Srekel/zig-gamedev.git",
        "4c42a5af94a7d9e2614ae428078c5d615dca83c0",
    )
    sync_lib(
        "zig-im3d",
        "https://github.com/Srekel/zig-im3d.git",
        "296a35e5f1a51e577d879dd5d1225bbcbdb27234",
    )
    sync_lib(
        "zigimg",
        "https://github.com/zigimg/zigimg.git",
        "637974e2d31dcdbc33f1e9cc8ffb2e46abd2e215",
    )
    sync_lib(
        "zig-recastnavigation",
        "https://github.com/Srekel/zig-recastnavigation.git",
        "6a69021cd643276aafb0f12a32b50bbdc21ed59a",
    )
    # sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")

    sync_zig_exe("0.13.0-dev.46+3648d7df1")

    os.chdir("..")
    print("Done syncing external!")


if __name__ == "__main__":
    main()
    print("Press enter...")
    input()
