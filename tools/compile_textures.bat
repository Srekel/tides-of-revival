@echo off
SETLOCAL

cd tools\

echo "Compiling Textures..."

REM Medium House
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM_SRGB ..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\medium_house_plaster_albedo.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM_SRGB ..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\medium_house_roof_albedo.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM_SRGB ..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\medium_house_stone_albedo.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM_SRGB ..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\medium_house_wood_albedo.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM ..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\medium_house_plaster_arm.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM ..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\medium_house_roof_arm.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM ..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\medium_house_stone_arm.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM ..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\medium_house_wood_arm.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC5_UNORM ..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\medium_house_plaster_normal.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC5_UNORM ..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\medium_house_roof_normal.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC5_UNORM ..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\medium_house_stone_normal.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC5_UNORM ..\..\tides-rpg-source-assets\environment\buildings\exports\medium_house\medium_house_wood_normal.png

REM Bow & Arrow
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM_SRGB ..\..\tides-rpg-source-assets\weapons\exports\bow_arrow_albedo.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM ..\..\tides-rpg-source-assets\weapons\exports\bow_arrow_arm.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC5_UNORM ..\..\tides-rpg-source-assets\weapons\exports\bow_arrow_normal.png

REM Giant Ant
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM_SRGB ..\..\tides-rpg-source-assets\enemies\exports\light_ant\giant_ant_albedo.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM_SRGB ..\..\tides-rpg-source-assets\enemies\exports\light_ant\giant_ant_emissive.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM ..\..\tides-rpg-source-assets\enemies\exports\light_ant\giant_ant_arm.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC5_UNORM ..\..\tides-rpg-source-assets\enemies\exports\light_ant\giant_ant_normal.png

REM Terrain: Forest Ground
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM_SRGB ..\..\tides-rpg-source-assets\environment\terrain\exports\forest_ground_01_diff_2k.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM ..\..\tides-rpg-source-assets\environment\terrain\exports\forest_ground_01_arm_2k.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC5_UNORM ..\..\tides-rpg-source-assets\environment\terrain\exports\forest_ground_01_nor_dx_2k.png

REM Terrain: Dry Ground Rock
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM_SRGB ..\..\tides-rpg-source-assets\environment\terrain\exports\dry_ground_rocks_diff_2k.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM ..\..\tides-rpg-source-assets\environment\terrain\exports\dry_ground_rocks_arm_2k.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC5_UNORM ..\..\tides-rpg-source-assets\environment\terrain\exports\dry_ground_rocks_nor_dx_2k.png

REM Terrain: Rock Ground
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM_SRGB ..\..\tides-rpg-source-assets\environment\terrain\exports\rock_ground_02_diff_2k.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM ..\..\tides-rpg-source-assets\environment\terrain\exports\rock_ground_02_arm_2k.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC5_UNORM ..\..\tides-rpg-source-assets\environment\terrain\exports\rock_ground_02_nor_dx_2k.png

REM Terrain: Snow
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM_SRGB ..\..\tides-rpg-source-assets\environment\terrain\exports\snow_02_diff_2k.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC1_UNORM ..\..\tides-rpg-source-assets\environment\terrain\exports\snow_02_arm_2k.png
texconv.exe -nologo -y -o ..\content\textures\ -f BC5_UNORM ..\..\tides-rpg-source-assets\environment\terrain\exports\snow_02_nor_dx_2k.png

echo "All textures compiled"

ENDLOCAL