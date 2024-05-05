const std = @import("std");
const prefab_manager = @import("../prefab_manager.zig");
const core = @import("../core/core.zig");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("flecs_data.zig");
const renderer = @import("../renderer/renderer.zig");
const IdLocal = core.IdLocal;
const ID = @import("../core/core.zig").ID;

pub var player: ecsu.Entity = undefined;
pub var giant_ant: ecsu.Entity = undefined;
pub var bow: ecsu.Entity = undefined;
pub var default_cube: ecsu.Entity = undefined;
pub var matball: ecsu.Entity = undefined;

pub const arrow_id = ID("prefab_arrow");
pub const beech_tree_04_id = ID("beech_tree_04");
pub const bow_id = ID("prefab_bow");
pub const cube_id = ID("prefab_cube");
pub const cylinder_id = ID("prefab_cylinder");
pub const debug_sphere_id = ID("prefab_debug_sphere");
pub const giant_ant_id = ID("prefab_giant_ant");
pub const matball_id = ID("prefab_matball");
pub const medium_house_id = ID("prefab_medium_house");
pub const player_id = ID("prefab_player");
pub const sphere_id = ID("prefab_sphere");

// TODO(gmodarelli): We need an Asset Database to store meshes, textures, materials and prefabs instead of managing them all through prefabs
pub fn initPrefabs(prefab_mgr: *prefab_manager.PrefabManager, ecsu_world: ecsu.World) void {
    const default_material = fd.UberShader.initNoTexture(fd.ColorRGB.init(1, 1, 1), 0.8, 0.0);
    const default_material_id = IdLocal.init("M_default");
    prefab_mgr.storeMaterial(default_material_id, default_material);

    const vertex_layout_id = IdLocal.init("pos_uv0_nor_tan_col");

    {
        player = prefab_mgr.loadPrefabFromBinary("prefabs/characters/player/player.bin", player_id, vertex_layout_id, ecsu_world);
        player.setOverride(fd.Dynamic{});

        const static_mesh_component = player.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = default_material_id;
        }
    }

    {
        var material = fd.UberShader.init();
        material.albedo = prefab_mgr.rctx.loadTexture("textures/debug/round_aluminum_panel_albedo.dds");
        material.arm = prefab_mgr.rctx.loadTexture("textures/debug/round_aluminum_panel_arm.dds");
        material.normal = prefab_mgr.rctx.loadTexture("textures/debug/round_aluminum_panel_normal.dds");
        const material_id = IdLocal.init("M_round_aluminium_panel");
        prefab_mgr.storeMaterial(material_id, material);

        matball = prefab_mgr.loadPrefabFromBinary("prefabs/primitives/matball.bin", matball_id, vertex_layout_id, ecsu_world);
        matball.setOverride(fd.Dynamic{});

        const static_mesh_component = matball.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = material_id;
        }
    }

    {
        var material = fd.UberShader.init();
        material.albedo = prefab_mgr.rctx.loadTexture("prefabs/creatures/giant_ant/giant_ant_albedo.dds");
        material.arm = prefab_mgr.rctx.loadTexture("prefabs/creatures/giant_ant/giant_ant_arm.dds");
        material.normal = prefab_mgr.rctx.loadTexture("prefabs/creatures/giant_ant/giant_ant_normal.dds");
        const material_id = IdLocal.init("M_giant_ant");
        prefab_mgr.storeMaterial(material_id, material);

        giant_ant = prefab_mgr.loadPrefabFromBinary("prefabs/creatures/giant_ant/giant_ant.bin", giant_ant_id, vertex_layout_id, ecsu_world);
        giant_ant.setOverride(fd.Dynamic{});

        const static_mesh_component = giant_ant.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = material_id;
        }
    }

    {
        var material = fd.UberShader.init();
        material.albedo = prefab_mgr.rctx.loadTexture("prefabs/props/bow_arrow/bow_arrow_albedo.dds");
        material.arm = prefab_mgr.rctx.loadTexture("prefabs/props/bow_arrow/bow_arrow_arm.dds");
        material.normal = prefab_mgr.rctx.loadTexture("prefabs/props/bow_arrow/bow_arrow_normal.dds");
        const material_id = IdLocal.init("M_bow");
        prefab_mgr.storeMaterial(material_id, material);

        bow = prefab_mgr.loadPrefabFromBinary("prefabs/props/bow_arrow/bow.bin", bow_id, vertex_layout_id, ecsu_world);
        bow.setOverride(fd.Dynamic{});
        var static_mesh_component = bow.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = material_id;
        }

        var arrow = prefab_mgr.loadPrefabFromBinary("prefabs/props/bow_arrow/arrow.bin", arrow_id, vertex_layout_id, ecsu_world);
        arrow.setOverride(fd.Dynamic{});
        static_mesh_component = arrow.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = material_id;
        }
    }

    {
        default_cube = prefab_mgr.loadPrefabFromBinary("prefabs/primitives/primitive_cube.bin", cube_id, vertex_layout_id, ecsu_world);
        default_cube.setOverride(fd.Dynamic{});
        const static_mesh_component = default_cube.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = default_material_id;
        }
    }

    {
        var cylinder = prefab_mgr.loadPrefabFromBinary("prefabs/primitives/primitive_cylinder.bin", cylinder_id, vertex_layout_id, ecsu_world);
        cylinder.setOverride(fd.Dynamic{});
        const static_mesh_component = cylinder.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = default_material_id;
        }
    }

    {
        var sphere = prefab_mgr.loadPrefabFromBinary("prefabs/primitives/primitive_sphere.bin", sphere_id, vertex_layout_id, ecsu_world);
        sphere.setOverride(fd.Dynamic{});
        const static_mesh_component = sphere.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = default_material_id;
        }
    }

    {
        var roof_material = fd.UberShader.init();
        roof_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_roof_albedo.dds");
        roof_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_roof_arm.dds");
        roof_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_roof_normal.dds");
        const roof_material_id = IdLocal.init("M_medium_house_roof");
        prefab_mgr.storeMaterial(roof_material_id, roof_material);

        var wood_material = fd.UberShader.init();
        wood_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_wood_albedo.dds");
        wood_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_wood_arm.dds");
        wood_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_wood_normal.dds");
        const wood_material_id = IdLocal.init("M_medium_house_wood");
        prefab_mgr.storeMaterial(wood_material_id, wood_material);

        var plaster_material = fd.UberShader.init();
        plaster_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_albedo.dds");
        plaster_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_arm.dds");
        plaster_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_normal.dds");
        const plaster_material_id = IdLocal.init("M_medium_house_plaster");
        prefab_mgr.storeMaterial(plaster_material_id, plaster_material);

        var stone_material = fd.UberShader.init();
        stone_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_stone_albedo.dds");
        stone_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_stone_arm.dds");
        stone_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_stone_normal.dds");
        const stone_material_id = IdLocal.init("M_medium_house_stone");
        prefab_mgr.storeMaterial(stone_material_id, stone_material);

        var medium_house = prefab_mgr.loadPrefabFromBinary("prefabs/buildings/medium_house/medium_house.bin", medium_house_id, vertex_layout_id, ecsu_world);
        const static_mesh_component = medium_house.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 4;

            static_mesh.materials[0] = roof_material_id;
            static_mesh.materials[1] = wood_material_id;
            static_mesh.materials[2] = plaster_material_id;
            static_mesh.materials[3] = stone_material_id;
        }
    }

    {
        var beech_trunk_04_material = fd.UberShader.init();
        beech_trunk_04_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_trunk_04_albedo.dds");
        beech_trunk_04_material.arm = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_trunk_04_arm.dds");
        beech_trunk_04_material.normal = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_trunk_04_normal.dds");
        beech_trunk_04_material.wind_feature = true;
        beech_trunk_04_material.wind_initial_bend = 1.0;
        beech_trunk_04_material.wind_stifness = 1.0;
        beech_trunk_04_material.wind_drag = 0.1;
        const beech_trunk_04_material_id = IdLocal.init("M_beech_trunk_04");
        prefab_mgr.storeMaterial(beech_trunk_04_material_id, beech_trunk_04_material);

        var beech_atlas_v2_material = fd.UberShader.init();
        beech_atlas_v2_material.surface_type = .masked;
        beech_atlas_v2_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_atlas_v2_albedo.dds");
        beech_atlas_v2_material.arm = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_atlas_arm.dds");
        beech_atlas_v2_material.normal = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_atlas_normal.dds");
        beech_atlas_v2_material.wind_feature = true;
        beech_atlas_v2_material.wind_initial_bend = 1.0;
        beech_atlas_v2_material.wind_stifness = 1.0;
        beech_atlas_v2_material.wind_drag = 0.1;
        beech_atlas_v2_material.wind_shiver_feature = true;
        beech_atlas_v2_material.wind_shiver_drag = 0.1;
        beech_atlas_v2_material.wind_normal_influence = 0.2;
        beech_atlas_v2_material.wind_shiver_directionality = 0.4;
        const beech_atlas_v2_material_id = IdLocal.init("M_beech_atlas_v2");
        prefab_mgr.storeMaterial(beech_atlas_v2_material_id, beech_atlas_v2_material);

        var beech_tree_04 = prefab_mgr.loadPrefabFromBinary("prefabs/environment/beech/prefab_beech_tree_04_LOD0.bin", beech_tree_04_id, vertex_layout_id, ecsu_world);
        const static_mesh_component = beech_tree_04.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 2;

            static_mesh.materials[0] = beech_trunk_04_material_id;
            static_mesh.materials[1] = beech_atlas_v2_material_id;
        }
    }
}
