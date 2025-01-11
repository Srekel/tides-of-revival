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
    try:
        url = "https://ziglang.org/builds/" + filename
        urllib.request.urlretrieve(url, filename)
    except:
        print("Didn't find on zig.com, trying machengine.org")
        url = "https://pkg.machengine.org/zig/" + filename
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
        "da79d270587b1c523d3363b3031aff999c8860a4",
    )
    sync_lib(
        "The-Forge",
        "https://github.com/gmodarelli/The-Forge.git",
        "1b27d3392f82c4969b10818dcd2f560cf93d71fd",
    )
    sync_lib(
        "websocket.zig",
        "https://github.com/karlseguin/websocket.zig.git",
        "ba14f387b22210667a2941c1e5e4170eb1854957",
    )
    sync_lib(
        "zig-args",
        "https://github.com/MasterQ32/zig-args.git",
        "236bccf4cc7871aef5c48fc102218ecf8baa48dd",
    )
    sync_lib(
        "zig-im3d",
        "https://github.com/Srekel/zig-im3d.git",
        "68fca723da6e21124bf59674c081be38bc063c63",
    )
    sync_lib(
        "zigimg",
        "https://github.com/zigimg/zigimg.git",
        "1496bdd39bc35a795e8514c493114e2ab82f8cf3",
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
        "5944f97c2681c6f63ead24bfe6501f33c5cc72a3",
    )
    sync_lib(
        "imgui",
        "https://github.com/ocornut/imgui",
        "10fe2b674a39a2dbee2a1f0449c6f52f2af7c0f3",
    )
    sync_lib(
        "poisson-disk-sampling",
        "https://github.com/thinks/poisson-disk-sampling",
        "c126f1712b53103ac2039a8430b7d77b38f75ab9",
    )
    sync_lib(
        "stb",
        "https://github.com/nothings/stb",
        "5c205738c191bcb0abc65c4febfa9bd25ff35234",
    )
    sync_lib(
        "voronoi",
        "https://github.com/Srekel/voronoi",
        "73f609573a6556e6eb2a1a6600d4aa99afdf6113",
    )

    ##############
    ## ZIG-GAMEDEV
    sync_lib(
        "system_sdk",
        "https://github.com/zig-gamedev/system_sdk",
        "bf49d627a191e339f70e72668c8333717fb969b0",
    )
    sync_lib(
        "zglfw",
        "https://github.com/zig-gamedev/zglfw",
        "f3f35b36e3ae9cb6b85f39e15ab0336c1ee65b4b",
    )
    sync_lib(
        "zflecs",
        "https://github.com/zig-gamedev/zflecs",
        "fcde2da35ea43c289bc731c9a244417c176192d0",
    )
    sync_lib(
        "zgui",
        "https://github.com/Srekel/zgui.git",
        "b5b29363a1a1db91519f0d94099c597e49eadfe9",
    )
    sync_lib(
        "zmath",
        "https://github.com/zig-gamedev/zmath",
        "24cdd20f9da09bd1ce7b552907eeaba9bafea59d",
    )
    sync_lib(
        "zmesh",
        "https://github.com/zig-gamedev/zmesh",
        "1fc267af7c8bd00cb2d79de12b3e0512a3b787cf",
    )
    sync_lib(
        "znoise",
        "https://github.com/zig-gamedev/znoise",
        "b6e7a24c9bfa4bae63521664e191a728b5b18805",
    )
    sync_lib(
        "zphysics",
        "https://github.com/zig-gamedev/zphysics",
        "c545c87dcd09d42cf04d8551d8480a5ffad4abee",
    )
    sync_lib(
        "zpix",
        "https://github.com/zig-gamedev/zpix",
        "9f13130127bed52d532538e6ab45ca6db4f5fb2e",
    )
    sync_lib(
        "zpool",
        "https://github.com/zig-gamedev/zpool",
        "163b4ab18936a3d57b5d8375eba1284114402c80",
    )
    sync_lib(
        "zstbi",
        "https://github.com/zig-gamedev/zstbi",
        "bcbd249f3f57fb84d6d76f1bc621c7bd3bfaa4a2",
    )
    sync_lib(
        "ztracy",
        "https://github.com/zig-gamedev/ztracy",
        "5af60074f355ecda6114d08dcc8c931c3d163c94",
    )
    sync_lib(
        "zwindows",
        "https://github.com/zig-gamedev/zwindows",
        "e4217edae23ce580f00e7354b5823f50b50bf6d7",
    )

    sync_zig_exe("0.14.0-dev.2577+271452d22")

    os.chdir("..")
    print("Done syncing external!")


if __name__ == "__main__":
    main()
    print("Press enter...")
    input()
