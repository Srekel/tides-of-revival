import os

out_txt = os.path.join("..", "licenses.txt")
code_licenses_csv = os.path.join("..", "src", "licenses.csv")
content_licenses_csv = os.path.join("..", "content", "content.csv")
source_assets_license = os.path.join("..", "..", "tides-rpg-source-assets", "source_assets.csv")

def print_file(filename, func):
    with open(filename) as file:
        skipped_header = False
        for line in file.readlines():
            if not skipped_header:
                skipped_header = True
                continue

            line = line.strip()
            if len(line) == 0 or line[0] != "Y":
                continue
            func(line)
            print("", file=out_file)

def print_code_license(line):
    used, name, origin, license = line.split("\t")
    print(f"{name}", file=out_file)
    print(f"Origin: {origin} ", file=out_file)
    print(f"License: {license}", file=out_file)

def print_content_license(line):
    used, path, asset, origin, license, original_filename = line.split("\t")
    print(f"{path}/{asset}", file=out_file)
    print(f"Origin: {origin} ", file=out_file)
    print(f"License: {license}", file=out_file)

def print_source_assets_license(line):
    used, path, asset, origin, license = line.split("\t")
    print(f"{asset}", file=out_file)
    print(f"Origin: {origin} ", file=out_file)
    print(f"License: {license}", file=out_file)

with open(out_txt, "w") as out_file:
    print("---------------", file=out_file)
    print("CODE LICENCES", file=out_file)
    print("---------------", file=out_file)
    print_file(code_licenses_csv, print_code_license)

    print("", file=out_file)
    print("----------------", file=out_file)
    print("CONTENT LICENCES", file=out_file)
    print("----------------", file=out_file)
    print_file(content_licenses_csv, print_content_license)

    print("", file=out_file)
    print("---------------------", file=out_file)
    print("SOURCE ASSET LICENCES", file=out_file)
    print("---------------------", file=out_file)
    print_file(source_assets_license, print_source_assets_license)


