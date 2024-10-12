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
        "b22872e63ee5e15f010078c2d0ea9d8e948fc893",
    )
    sync_lib(
        "The-Forge",
        "https://github.com/gmodarelli/The-Forge.git",
        "9b77acaa59d16bba6c144f70d6e7cb42bedb1dce",
    )
    sync_lib(
        "websocket.zig",
        "https://github.com/karlseguin/websocket.zig.git",
        "93a0fb37b4d939abefee7aca22aa5bf3efefe8d5",
    )
    sync_lib(
        "wwise-zig",
        "https://github.com/Cold-Bytes-Games/wwise-zig.git",
        "4888fd81f3a905c7bb1cc5d91547503dbc0b3e1b",
    )
    sync_lib(
        "zig-args",
        "https://github.com/MasterQ32/zig-args.git",
        "872272205d95bdba33798c94e72c5387a31bc806",
    )
    sync_lib(
        "zig-gamedev",
        "https://github.com/Srekel/zig-gamedev.git",
        "721a28f2efd72fc379ae753b766738035845e1d3",
    )
    sync_lib(
        "zig-im3d",
        "https://github.com/Srekel/zig-im3d.git",
        "68fca723da6e21124bf59674c081be38bc063c63",
    )
    sync_lib(
        "zigimg",
        "https://github.com/zigimg/zigimg.git",
        "563531ac08d70821e9679f4fe01273356b7d2a8a",
    )
    sync_lib(
        "zig-recastnavigation",
        "https://github.com/Srekel/zig-recastnavigation.git",
        "14a7d426688a71d6460cf1b104f1fe548f8c96c2",
    )
    # sync_lib("zls", "https://github.com/zigtools/zls.git", "949e4fe525abaf25699b7f15368ecdc49fd8b786")

    sync_lib(
        "FastNoiseLite",
        "https://github.com/Auburn/FastNoiseLite",
        "72d212e005e62c886c06f55f740571116f361571",
    )
    sync_lib(
        "imgui",
        "https://github.com/ocornut/imgui",
        "10fe2b674a39a2dbee2a1f0449c6f52f2af7c0f3",
    )
    sync_lib(
        "poisson-disk-sampling",
        "https://github.com/thinks/poisson-disk-sampling",
        "11575d53f9b123b69e4963bb68251334181ad22d",
    )
    sync_lib(
        "stb",
        "https://github.com/nothings/stb",
        "f75e8d1cad7d90d72ef7a4661f1b994ef78b4e31",
    )
    sync_lib(
        "voronoi",
        "https://github.com/Srekel/voronoi",
        "e4b62e3a765c1ecf80ca3b759f456bcf0b51dc37",
    )

    sync_zig_exe("0.13.0")

    os.chdir("..")
    print("Done syncing external!")


if __name__ == "__main__":
    main()
    print("Press enter...")
    input()
