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
        "49ead61b742cf4339f1418b254c443591f39f946",
    )
    sync_lib(
        "The-Forge",
        "https://github.com/gmodarelli/The-Forge.git",
        "42bc23af2f15a09ee850c70954d37c0485fd81b7",
    )
    sync_lib(
        "websocket.zig",
        "https://github.com/karlseguin/websocket.zig.git",
        "7d009556a0a82e95db2cf1f66a5fdb057642faba",
    )
    sync_lib(
        "wwise-zig",
        "https://github.com/Cold-Bytes-Games/wwise-zig.git",
        "4888fd81f3a905c7bb1cc5d91547503dbc0b3e1b",
    )
    sync_lib(
        "zig-args",
        "https://github.com/MasterQ32/zig-args.git",
        "01d72b9a0128c474aeeb9019edd48605fa6d95f7",
    )
    sync_lib(
        "zig-gamedev",
        "https://github.com/Srekel/zig-gamedev.git",
        "c1732f48bf287d406b9b69427b428f1157ab8ea7",
    )
    sync_lib(
        "zigimg",
        "https://github.com/zigimg/zigimg.git",
        "8873f29fc449e1b63400e9f4ad86d3c76204f962",
    )
    sync_lib(
        "zig-recastnavigation",
        "https://github.com/Srekel/zig-recastnavigation.git",
        "90c440c7117ec405371c6fb2de4a27bbcc93c1ae",
    )
    # sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")

    sync_zig_exe("0.12.0-dev.3180+83e578a18")

    os.chdir("..")
    print("Done syncing external!")


if __name__ == "__main__":
    main()
    print("Press enter...")
    input()
