const std = @import("std");
const prefab_manager = @import("../prefab_manager.zig");
const core = @import("../core/core.zig");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("flecs_data.zig");
const renderer = @import("../renderer/tides_renderer.zig");

pub var player: ecsu.Entity = undefined;
pub var giant_ant: ecsu.Entity = undefined;
pub var bow: ecsu.Entity = undefined;

pub fn initPrefabs(prefab_mgr: *prefab_manager.PrefabManager, ecsu_world: ecsu.World) void {
    {
        player = prefab_mgr.loadPrefabFromBinary("player.bin", ecsu_world);
        player.setOverride(fd.Dynamic{});
        var static_mesh_component = player.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.initNoTexture(fd.ColorRGB.init(1, 1, 1), 0.8, 0.0);
        }
    }

    {
        giant_ant = prefab_mgr.loadPrefabFromBinary("giant_ant.bin", ecsu_world);
        giant_ant.setOverride(fd.Dynamic{});
        var static_mesh_component = giant_ant.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.init();
            static_mesh.materials[0].albedo = renderer.loadTexture("giant_ant_albedo.dds");
            static_mesh.materials[0].arm = renderer.loadTexture("giant_ant_arm.dds");
            static_mesh.materials[0].normal = renderer.loadTexture("giant_ant_normal.dds");
        }
    }

    {
        var albedo = renderer.loadTexture("bow_arrow_albedo.dds");
        var arm = renderer.loadTexture("bow_arrow_arm.dds");
        var normal = renderer.loadTexture("bow_arrow_normal.dds");

        bow = prefab_mgr.loadPrefabFromBinary("bow.bin", ecsu_world);
        bow.setOverride(fd.Dynamic{});
        var static_mesh_component = bow.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.init();
            static_mesh.materials[0].albedo = albedo;
            static_mesh.materials[0].arm = arm;
            static_mesh.materials[0].normal = normal;
        }

        var arrow = prefab_mgr.loadPrefabFromBinary("arrow.bin", ecsu_world);
        arrow.setOverride(fd.Dynamic{});
        static_mesh_component = arrow.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.init();
            static_mesh.materials[0].albedo = albedo;
            static_mesh.materials[0].arm = arm;
            static_mesh.materials[0].normal = normal;
        }
    }

    {
        var cube = prefab_mgr.loadPrefabFromBinary("primitive_cube.bin", ecsu_world);
        cube.setOverride(fd.Dynamic{});
        var static_mesh_component = cube.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.initNoTexture(fd.ColorRGB.init(1, 1, 1), 0.8, 0.0);
        }
    }

    {
        var cylinder = prefab_mgr.loadPrefabFromBinary("primitive_cylinder.bin", ecsu_world);
        cylinder.setOverride(fd.Dynamic{});
        var static_mesh_component = cylinder.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.initNoTexture(fd.ColorRGB.init(1, 1, 1), 0.8, 0.0);
        }
    }

    {
        var sphere = prefab_mgr.loadPrefabFromBinary("primitive_sphere.bin", ecsu_world);
        sphere.setOverride(fd.Dynamic{});
        var static_mesh_component = sphere.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.initNoTexture(fd.ColorRGB.init(1, 1, 1), 0.8, 0.0);
        }
    }

    {
        var medium_house = prefab_mgr.loadPrefabFromBinary("medium_house.bin", ecsu_world);
        var static_mesh_component = medium_house.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 4;

            static_mesh.materials[0] = fd.PBRMaterial.init();
            static_mesh.materials[0].albedo = renderer.loadTexture("medium_house_roof_albedo.dds");
            static_mesh.materials[0].arm = renderer.loadTexture("medium_house_roof_arm.dds");
            static_mesh.materials[0].normal = renderer.loadTexture("medium_house_roof_normal.dds");

            static_mesh.materials[1] = fd.PBRMaterial.init();
            static_mesh.materials[1].albedo = renderer.loadTexture("medium_house_wood_albedo.dds");
            static_mesh.materials[1].arm = renderer.loadTexture("medium_house_wood_arm.dds");
            static_mesh.materials[1].normal = renderer.loadTexture("medium_house_wood_normal.dds");

            static_mesh.materials[2] = fd.PBRMaterial.init();
            static_mesh.materials[2].albedo = renderer.loadTexture("medium_house_plaster_albedo.dds");
            static_mesh.materials[2].arm = renderer.loadTexture("medium_house_plaster_arm.dds");
            static_mesh.materials[2].normal = renderer.loadTexture("medium_house_plaster_normal.dds");

            static_mesh.materials[3] = fd.PBRMaterial.init();
            static_mesh.materials[3].albedo = renderer.loadTexture("medium_house_stone_albedo.dds");
            static_mesh.materials[3].arm = renderer.loadTexture("medium_house_stone_arm.dds");
            static_mesh.materials[3].normal = renderer.loadTexture("medium_house_stone_normal.dds");
        }
    }

    {
        var fir = prefab_mgr.loadPrefabFromBinary("fir.bin", ecsu_world);
        var static_mesh_component = fir.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 2;

            static_mesh.materials[0] = fd.PBRMaterial.init();
            static_mesh.materials[0].albedo = renderer.loadTexture("fir_bark.dds");

            static_mesh.materials[1] = fd.PBRMaterial.init();
            static_mesh.materials[1].albedo = renderer.loadTexture("fir_branch.dds");
            static_mesh.materials[1].surface_type = .masked;
        }
    }

    {
        var sphere_test = prefab_mgr.loadPrefabFromBinary("sphere_test.bin", ecsu_world);
        var static_mesh_component = sphere_test.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 22;

            for (0..11) |i| {
                const roughness: f32 = @as(f32, @floatFromInt(i)) / 10.0;
                static_mesh.materials[i] = fd.PBRMaterial.init();
                static_mesh.materials[i].base_color = fd.ColorRGB.init(1.0, 0.0, 0.0);
                static_mesh.materials[i].metallic = 0.0;
                static_mesh.materials[i].roughness = roughness;

                static_mesh.materials[i + 11] = fd.PBRMaterial.init();
                static_mesh.materials[i + 11].base_color = fd.ColorRGB.init(1.0, 0.0, 0.0);
                static_mesh.materials[i + 11].metallic = 1.0;
                static_mesh.materials[i + 11].roughness = roughness;
            }
        }
    }
}
