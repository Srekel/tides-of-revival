const std = @import("std");
const prefab_manager = @import("../prefab_manager.zig");
const core = @import("../core/core.zig");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("flecs_data.zig");
const renderer = @import("../renderer/tides_renderer.zig");
const ID = @import("../core/core.zig").ID;

pub var player: ecsu.Entity = undefined;
pub var giant_ant: ecsu.Entity = undefined;
pub var bow: ecsu.Entity = undefined;
pub var default_cube: ecsu.Entity = undefined;

pub const arrow_id = ID("prefab_arrow");
pub const bow_id = ID("prefab_bow");
pub const cube_id = ID("prefab_cube");
pub const cylinder_id = ID("prefab_cylinder");
pub const debug_sphere_id = ID("prefab_debug_sphere");
pub const fir_id = ID("prefab_fir");
pub const giant_ant_id = ID("prefab_giant_ant");
pub const medium_house_id = ID("prefab_medium_house");
pub const player_id = ID("prefab_player");
pub const sphere_id = ID("prefab_sphere");

pub fn initPrefabs(prefab_mgr: *prefab_manager.PrefabManager, ecsu_world: ecsu.World) void {
    {
        player = prefab_mgr.loadPrefabFromBinary("prefabs/characters/player/player.bin", player_id, ecsu_world);
        player.setOverride(fd.Dynamic{});
        const static_mesh_component = player.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.initNoTexture(fd.ColorRGB.init(1, 1, 1), 0.8, 0.0);
        }
    }

    {
        giant_ant = prefab_mgr.loadPrefabFromBinary("prefabs/creatures/giant_ant/giant_ant.bin", giant_ant_id, ecsu_world);
        giant_ant.setOverride(fd.Dynamic{});
        const static_mesh_component = giant_ant.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.init();
            static_mesh.materials[0].albedo = renderer.loadTexture("prefabs/creatures/giant_ant/giant_ant_albedo.dds");
            static_mesh.materials[0].arm = renderer.loadTexture("prefabs/creatures/giant_ant/giant_ant_arm.dds");
            static_mesh.materials[0].normal = renderer.loadTexture("prefabs/creatures/giant_ant/giant_ant_normal.dds");
        }
    }

    {
        const albedo = renderer.loadTexture("prefabs/props/bow_arrow/bow_arrow_albedo.dds");
        const arm = renderer.loadTexture("prefabs/props/bow_arrow/bow_arrow_arm.dds");
        const normal = renderer.loadTexture("prefabs/props/bow_arrow/bow_arrow_normal.dds");

        bow = prefab_mgr.loadPrefabFromBinary("prefabs/props/bow_arrow/bow.bin", bow_id, ecsu_world);
        bow.setOverride(fd.Dynamic{});
        var static_mesh_component = bow.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.init();
            static_mesh.materials[0].albedo = albedo;
            static_mesh.materials[0].arm = arm;
            static_mesh.materials[0].normal = normal;
        }

        var arrow = prefab_mgr.loadPrefabFromBinary("prefabs/props/bow_arrow/arrow.bin", arrow_id, ecsu_world);
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
        default_cube = prefab_mgr.loadPrefabFromBinary("prefabs/primitives/primitive_cube.bin", cube_id, ecsu_world);
        default_cube.setOverride(fd.Dynamic{});
        const static_mesh_component = default_cube.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.initNoTexture(fd.ColorRGB.init(1, 1, 1), 0.8, 0.0);
        }
    }

    {
        var cylinder = prefab_mgr.loadPrefabFromBinary("prefabs/primitives/primitive_cylinder.bin", cylinder_id, ecsu_world);
        cylinder.setOverride(fd.Dynamic{});
        const static_mesh_component = cylinder.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.initNoTexture(fd.ColorRGB.init(1, 1, 1), 0.8, 0.0);
        }
    }

    {
        var sphere = prefab_mgr.loadPrefabFromBinary("prefabs/primitives/primitive_sphere.bin", sphere_id, ecsu_world);
        sphere.setOverride(fd.Dynamic{});
        const static_mesh_component = sphere.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = fd.PBRMaterial.initNoTexture(fd.ColorRGB.init(1, 1, 1), 0.8, 0.0);
        }
    }

    {
        var medium_house = prefab_mgr.loadPrefabFromBinary("prefabs/buildings/medium_house/medium_house.bin", medium_house_id, ecsu_world);
        const static_mesh_component = medium_house.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 4;

            static_mesh.materials[0] = fd.PBRMaterial.init();
            static_mesh.materials[0].albedo = renderer.loadTexture("prefabs/buildings/medium_house/medium_house_roof_albedo.dds");
            static_mesh.materials[0].arm = renderer.loadTexture("prefabs/buildings/medium_house/medium_house_roof_arm.dds");
            static_mesh.materials[0].normal = renderer.loadTexture("prefabs/buildings/medium_house/medium_house_roof_normal.dds");

            static_mesh.materials[1] = fd.PBRMaterial.init();
            static_mesh.materials[1].albedo = renderer.loadTexture("prefabs/buildings/medium_house/medium_house_wood_albedo.dds");
            static_mesh.materials[1].arm = renderer.loadTexture("prefabs/buildings/medium_house/medium_house_wood_arm.dds");
            static_mesh.materials[1].normal = renderer.loadTexture("prefabs/buildings/medium_house/medium_house_wood_normal.dds");

            static_mesh.materials[2] = fd.PBRMaterial.init();
            static_mesh.materials[2].albedo = renderer.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_albedo.dds");
            static_mesh.materials[2].arm = renderer.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_arm.dds");
            static_mesh.materials[2].normal = renderer.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_normal.dds");

            static_mesh.materials[3] = fd.PBRMaterial.init();
            static_mesh.materials[3].albedo = renderer.loadTexture("prefabs/buildings/medium_house/medium_house_stone_albedo.dds");
            static_mesh.materials[3].arm = renderer.loadTexture("prefabs/buildings/medium_house/medium_house_stone_arm.dds");
            static_mesh.materials[3].normal = renderer.loadTexture("prefabs/buildings/medium_house/medium_house_stone_normal.dds");
        }
    }

    {
        var fir = prefab_mgr.loadPrefabFromBinary("prefabs/environment/fir/fir.bin", fir_id, ecsu_world);
        const static_mesh_component = fir.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 2;

            static_mesh.materials[0] = fd.PBRMaterial.init();
            static_mesh.materials[0].albedo = renderer.loadTexture("prefabs/environment/fir/fir_bark_albedo.dds");

            static_mesh.materials[1] = fd.PBRMaterial.init();
            static_mesh.materials[1].albedo = renderer.loadTexture("prefabs/environment/fir/fir_branch_albedo.dds");
            static_mesh.materials[1].surface_type = .masked;
        }
    }

    {
        var sphere_test = prefab_mgr.loadPrefabFromBinary("prefabs/props/debug_sphere/debug_sphere.bin", debug_sphere_id, ecsu_world);
        const static_mesh_component = sphere_test.getMut(fd.StaticMeshComponent);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 22;

            for (0..11) |i| {
                const roughness: f32 = @as(f32, @floatFromInt(i)) / 10.0;
                static_mesh.materials[i] = fd.PBRMaterial.init();
                static_mesh.materials[i].base_color = fd.ColorRGB.init(1.0, 1.0, 1.0);
                static_mesh.materials[i].metallic = 0.0;
                static_mesh.materials[i].roughness = roughness;

                static_mesh.materials[i + 11] = fd.PBRMaterial.init();
                static_mesh.materials[i + 11].base_color = fd.ColorRGB.init(1.0, 1.0, 1.0);
                static_mesh.materials[i + 11].metallic = 1.0;
                static_mesh.materials[i + 11].roughness = roughness;
            }
        }
    }
}
