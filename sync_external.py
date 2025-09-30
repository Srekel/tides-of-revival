import os
import sys
import subprocess
import urllib.request

script_path = os.path.dirname(os.path.realpath(__file__))


def sync_lib(folder, git_path, commit_sha_or_branch_or_tag):
    print()
    print("-" * (2 * 4 + len(folder) + 2))
    print("----", folder, "----")
    print("-" * (2 * 4 + len(folder) + 2))
    print("Origin:", git_path)
    if not os.path.isdir(folder):
        os.system("git clone " + git_path + " " + folder)
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
    zigup_dir = os.path.join(script_path, "tools", "binaries", "zigup")
    zigup_path = os.path.join(zigup_dir, "zigup")
    zig_path = os.path.join(zigup_dir, "zig")
    print("Zigup path:", zigup_path)
    print("Zig path:", zig_path)
    print("Current Zig version on in Tides's zigup:")
    os.system(f"{zig_path} version")
    print("Wanted version:")
    print(f"{build}")
    print("Ensuring correct version...")
    os.system(f"{zigup_path} {build}")
    os.system(f"{zigup_path} keep {build}")


def main():
    print("Syncing external...")
    external_dir = "external"
    if not os.path.isdir(external_dir):
        os.mkdir(external_dir)
    os.chdir(external_dir)

    sync_lib(
        "c2z",
        "https://github.com/Srekel/c2z.git",
        "f44cc6b4780a3302597442b749007fa339f74166",
    )
    sync_lib(
        "The-Forge",
        "https://github.com/gmodarelli/The-Forge.git",
        "a93a68edc3b49c9ecf1af4c7b436a8a1ae13b030",
    )
    sync_lib(
        "ze-forge",
        "https://github.com/gmodarelli/The-Forge.git",
        "ba8b526bc72045c25a001ba5f5a0865df3ebc737",
    )
    sync_lib(
        "websocket.zig",
        "https://github.com/karlseguin/websocket.zig.git",
        "10b0e7be2158ff22733f1e59c1ae0bace5bf3a0c",
    )
    sync_lib(
        "zig-args",
        "https://github.com/MasterQ32/zig-args.git",
        "9425b94c103a031777fdd272c555ce93a7dea581",
    )
    sync_lib(
        "zig-im3d",
        "https://github.com/Srekel/zig-im3d.git",
        "8cb0eeec8336039d5be2df4b0ecd80f35fe57332",
    )
    sync_lib(
        "zig-json5",
        "https://github.com/Himujjal/zig-json5.git",
        "2a7f83dca0d7cd52089605cf592ddb7ff3567a9f",
    )
    sync_lib(
        "zigimg",
        "https://github.com/zigimg/zigimg.git",
        "74caab5edd7c5f1d2f7d87e5717435ce0f0affa1",
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
        "582f7cf21065a48ee1c3cf62048831bbaa4581c5",
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
    sync_lib(
        "zigwin32",
        "https://github.com/marlersoft/zigwin32",
        "d21b419d808215e1f82605fdaddc49750bfa3bca",
    )

    ##############
    ## ZIG-GAMEDEV
    sync_lib(
        "system_sdk",
        "https://github.com/zig-gamedev/system_sdk",
        "c0dbf11cdc17da5904ea8a17eadc54dee26567ec",
    )
    sync_lib(
        "zaudio",
        "https://github.com/zig-gamedev/zaudio",
        "ea4200e7e9a877953ecb3fe8aa18a0d0d58a4bc2",
    )
    sync_lib(
        "zglfw",
        "https://github.com/zig-gamedev/zglfw",
        "c337cb3d3f984468ea7a386335937a5d555fc024",
    )
    sync_lib(
        "zflecs",
        "https://github.com/zig-gamedev/zflecs",
        "13d66e8c5f74bbe574afe1bb37c26f799971ca4a",
    )
    sync_lib(
        "zgltf",
        "https://github.com/kooparse/zgltf.git",
        "b6579c3887c7ab0eef5f1eda09abbbc1f04d76ce",
    )
    sync_lib(
        "zgui",
        "https://github.com/Srekel/zgui.git",
        "3cdbe1f449cb3581be75929362363bf59ecea669",
    )
    sync_lib(
        "zmath",
        "https://github.com/zig-gamedev/zmath",
        "58930cfe153d07f9fb2430241b5e6d4d641111b8",
    )
    sync_lib(
        "zmesh",
        "https://github.com/zig-gamedev/zmesh",
        "f8f528128704ae879a16ddb0a3470c5e0a144a20",
    )
    sync_lib(
        "znoise",
        "https://github.com/zig-gamedev/znoise",
        "96f9458c2da975a8bf1cdf95e819c7b070965198",
    )
    sync_lib(
        "zphysics",
        "https://github.com/zig-gamedev/zphysics",
        "e390932a4fc9bbc61cafcd96ead1d7cc8c290065",
    )
    sync_lib(
        "zpix",
        "https://github.com/zig-gamedev/zpix",
        "e1f5f72d2a64ac1c459a14be40df63bef07bb97e",
    )
    sync_lib(
        "zpool",
        "https://github.com/zig-gamedev/zpool",
        "4c850e222e1ba507b45d7bab8cac83bdd74cacd6",
    )
    sync_lib(
        "zstbi",
        "https://github.com/zig-gamedev/zstbi",
        "094c4bba5cdbec167d3f6aaa98cccccd5c99145f",
    )
    sync_lib(
        "ztracy",
        "https://github.com/zig-gamedev/ztracy",
        "be3d003f29d59d72e68e493ab531374ab474a795",
    )
    sync_lib(
        "zwindows",
        "https://github.com/zig-gamedev/zwindows",
        "c29e0fec072c282a8c6234c5837db071af42a11f",
    )

    sync_zig_exe("0.14.1")

    os.chdir("..")
    print("Done syncing external!")


if __name__ == "__main__":
    main()
    print("Press enter...")
    input()
