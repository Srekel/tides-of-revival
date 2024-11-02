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
pub var color_calibrator: ecsu.Entity = undefined;

pub const arrow_id = ID("prefab_arrow");
pub const beech_tree_04_id = ID("beech_tree_04");
pub const bow_id = ID("prefab_bow");
pub const cube_id = ID("prefab_cube");
pub const cylinder_id = ID("prefab_cylinder");
pub const plane_id = ID("prefab_plane");
pub const debug_sphere_id = ID("prefab_debug_sphere");
pub const giant_ant_id = ID("prefab_giant_ant");
pub const matball_id = ID("prefab_matball");
pub const medium_house_id = ID("prefab_medium_house");
pub const player_id = ID("prefab_player");
pub const sphere_id = ID("prefab_sphere");
pub const color_calibrator_id = ID("color_calibrator");

// TODO(gmodarelli): We need an Asset Database to store meshes, textures, materials and prefabs instead of managing them all through prefabs
pub fn initPrefabs(prefab_mgr: *prefab_manager.PrefabManager, ecsu_world: ecsu.World) void {
    const pipeline_lit_opaque_id = IdLocal.init("lit");
    const pipeline_lit_masked_id = IdLocal.init("lit_masked");
    _ = pipeline_lit_masked_id;
    const pipeline_tree_opaque_id = IdLocal.init("tree");
    const pipeline_tree_masked_id = IdLocal.init("tree_masked");

    const pipeline_shadow_caster_opaque_id = IdLocal.init("shadows_lit");
    const pipeline_shadow_caster_masked_id = IdLocal.init("shadows_lit_masked");
    _ = pipeline_shadow_caster_masked_id;
    const pipeline_tree_shadow_caster_opaque_id = IdLocal.init("shadows_tree");
    const pipeline_tree_shadow_caster_masked_id = IdLocal.init("shadows_tree_masked");

    var default_material = fd.UberShader.initNoTexture(fd.ColorRGB.init(1, 1, 1), 0.8, 0.0);
    default_material.gbuffer_pipeline_id = pipeline_lit_opaque_id;
    default_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
    const default_material_handle = prefab_mgr.rctx.uploadMaterial(default_material) catch unreachable;

    const pos_uv0_nor_tan_col_vertex_layout = IdLocal.init("pos_uv0_nor_tan_col");
    const pos_uv0_nor_tan_col_uv1_vertex_layout = IdLocal.init("pos_uv0_nor_tan_col_uv1");

    {
        player = prefab_mgr.loadPrefabFromBinary("prefabs/characters/player/player.bin", player_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        player.setOverride(fd.Dynamic{});

        const static_mesh_component = player.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = default_material_handle;
        }
    }

    {
        var material = fd.UberShader.init();
        material.gbuffer_pipeline_id = pipeline_lit_opaque_id;
        material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        material.albedo = prefab_mgr.rctx.loadTexture("textures/debug/round_aluminum_panel_albedo.dds");
        material.arm = prefab_mgr.rctx.loadTexture("textures/debug/round_aluminum_panel_arm.dds");
        material.normal = prefab_mgr.rctx.loadTexture("textures/debug/round_aluminum_panel_normal.dds");
        const material_handle = prefab_mgr.rctx.uploadMaterial(material) catch unreachable;

        matball = prefab_mgr.loadPrefabFromBinary("prefabs/primitives/matball.bin", matball_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        matball.setOverride(fd.Dynamic{});

        const static_mesh_component = matball.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = material_handle;
        }
    }

    {
        var material = fd.UberShader.init();
        material.gbuffer_pipeline_id = pipeline_lit_opaque_id;
        material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        material.albedo = prefab_mgr.rctx.loadTexture("prefabs/props/color_calibrator/color_checker_albedo.dds");
        const material_handle = prefab_mgr.rctx.uploadMaterial(material) catch unreachable;

        color_calibrator = prefab_mgr.loadPrefabFromBinary("prefabs/props/color_calibrator/color_calibrator.bin", color_calibrator_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        color_calibrator.setOverride(fd.Dynamic{});

        const static_mesh_component = color_calibrator.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = material_handle;
        }
    }

    {
        var material = fd.UberShader.init();
        material.gbuffer_pipeline_id = pipeline_lit_opaque_id;
        material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        material.albedo = prefab_mgr.rctx.loadTexture("prefabs/creatures/giant_ant/giant_ant_albedo.dds");
        material.arm = prefab_mgr.rctx.loadTexture("prefabs/creatures/giant_ant/giant_ant_arm.dds");
        material.normal = prefab_mgr.rctx.loadTexture("prefabs/creatures/giant_ant/giant_ant_normal.dds");
        const material_handle = prefab_mgr.rctx.uploadMaterial(material) catch unreachable;

        giant_ant = prefab_mgr.loadPrefabFromBinary("prefabs/creatures/giant_ant/giant_ant.bin", giant_ant_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        giant_ant.setOverride(fd.Dynamic{});

        const static_mesh_component = giant_ant.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = material_handle;
        }
    }

    {
        var material = fd.UberShader.init();
        material.gbuffer_pipeline_id = pipeline_lit_opaque_id;
        material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        material.albedo = prefab_mgr.rctx.loadTexture("prefabs/props/bow_arrow/bow_arrow_albedo.dds");
        material.arm = prefab_mgr.rctx.loadTexture("prefabs/props/bow_arrow/bow_arrow_arm.dds");
        material.normal = prefab_mgr.rctx.loadTexture("prefabs/props/bow_arrow/bow_arrow_normal.dds");
        const material_handle = prefab_mgr.rctx.uploadMaterial(material) catch unreachable;

        bow = prefab_mgr.loadPrefabFromBinary("prefabs/props/bow_arrow/bow.bin", bow_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        bow.setOverride(fd.Dynamic{});
        var static_mesh_component = bow.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = material_handle;
        }

        var arrow = prefab_mgr.loadPrefabFromBinary("prefabs/props/bow_arrow/arrow.bin", arrow_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        arrow.setOverride(fd.Dynamic{});
        static_mesh_component = arrow.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = material_handle;
        }
    }

    {
        default_cube = prefab_mgr.loadPrefabFromBinary("prefabs/primitives/primitive_cube.bin", cube_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        default_cube.setOverride(fd.Dynamic{});
        const static_mesh_component = default_cube.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = default_material_handle;
        }
    }

    {
        var cylinder = prefab_mgr.loadPrefabFromBinary("prefabs/primitives/primitive_cylinder.bin", cylinder_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        cylinder.setOverride(fd.Dynamic{});
        const static_mesh_component = cylinder.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = default_material_handle;
        }
    }

    {
        var plane = prefab_mgr.loadPrefabFromBinary("prefabs/primitives/primitive_plane.bin", plane_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        plane.setOverride(fd.Dynamic{});
        const static_mesh_component = plane.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = default_material_handle;
        }
    }

    {
        var sphere = prefab_mgr.loadPrefabFromBinary("prefabs/primitives/primitive_sphere.bin", sphere_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        sphere.setOverride(fd.Dynamic{});
        const static_mesh_component = sphere.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 1;
            static_mesh.materials[0] = default_material_handle;
        }
    }

    {
        var roof_material = fd.UberShader.init();
        roof_material.gbuffer_pipeline_id = pipeline_lit_opaque_id;
        roof_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        roof_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_roof_albedo.dds");
        roof_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_roof_arm.dds");
        roof_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_roof_normal.dds");
        const roof_material_handle = prefab_mgr.rctx.uploadMaterial(roof_material) catch unreachable;

        var wood_material = fd.UberShader.init();
        wood_material.gbuffer_pipeline_id = pipeline_lit_opaque_id;
        wood_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        wood_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_wood_albedo.dds");
        wood_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_wood_arm.dds");
        wood_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_wood_normal.dds");
        const wood_material_handle = prefab_mgr.rctx.uploadMaterial(wood_material) catch unreachable;

        var plaster_material = fd.UberShader.init();
        plaster_material.gbuffer_pipeline_id = pipeline_lit_opaque_id;
        plaster_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        plaster_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_albedo.dds");
        plaster_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_arm.dds");
        plaster_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_normal.dds");
        const plaster_material_handle = prefab_mgr.rctx.uploadMaterial(plaster_material) catch unreachable;

        var stone_material = fd.UberShader.init();
        stone_material.gbuffer_pipeline_id = pipeline_lit_opaque_id;
        stone_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        stone_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_stone_albedo.dds");
        stone_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_stone_arm.dds");
        stone_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_stone_normal.dds");
        const stone_material_handle = prefab_mgr.rctx.uploadMaterial(stone_material) catch unreachable;

        var medium_house = prefab_mgr.loadPrefabFromBinary("prefabs/buildings/medium_house/medium_house.bin", medium_house_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        const static_mesh_component = medium_house.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 4;

            static_mesh.materials[0] = roof_material_handle;
            static_mesh.materials[1] = wood_material_handle;
            static_mesh.materials[2] = plaster_material_handle;
            static_mesh.materials[3] = stone_material_handle;
        }
    }

    {
        var beech_trunk_04_material = fd.UberShader.init();
        beech_trunk_04_material.gbuffer_pipeline_id = pipeline_tree_opaque_id;
        beech_trunk_04_material.shadow_caster_pipeline_id = pipeline_tree_shadow_caster_opaque_id;
        beech_trunk_04_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_trunk_04_albedo.dds");
        beech_trunk_04_material.arm = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_trunk_04_arm.dds");
        beech_trunk_04_material.normal = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_trunk_04_normal.dds");
        beech_trunk_04_material.detail_feature = true;
        beech_trunk_04_material.detail_use_uv2 = true;
        beech_trunk_04_material.detail_mask = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_trunk_04_maska.dds");
        beech_trunk_04_material.detail_base_color = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_bark_01_albedo.dds");
        beech_trunk_04_material.detail_normal = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_bark_01_normal.dds");
        beech_trunk_04_material.detail_arm = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_bark_01_arm.dds");
        beech_trunk_04_material.wind_feature = false;
        beech_trunk_04_material.wind_initial_bend = 1.0;
        beech_trunk_04_material.wind_stifness = 1.0;
        beech_trunk_04_material.wind_drag = 0.1;
        const beech_trunk_04_material_handle = prefab_mgr.rctx.uploadMaterial(beech_trunk_04_material) catch unreachable;

        var beech_atlas_v2_material = fd.UberShader.init();
        beech_atlas_v2_material.gbuffer_pipeline_id = pipeline_tree_masked_id;
        beech_atlas_v2_material.shadow_caster_pipeline_id = pipeline_tree_shadow_caster_masked_id;
        beech_atlas_v2_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_atlas_v2_albedo.dds");
        beech_atlas_v2_material.arm = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_atlas_arm.dds");
        beech_atlas_v2_material.normal = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_atlas_normal.dds");
        beech_atlas_v2_material.wind_feature = false;
        beech_atlas_v2_material.wind_initial_bend = 1.0;
        beech_atlas_v2_material.wind_stifness = 1.0;
        beech_atlas_v2_material.wind_drag = 0.1;
        beech_atlas_v2_material.wind_shiver_feature = false;
        beech_atlas_v2_material.wind_shiver_drag = 0.1;
        beech_atlas_v2_material.wind_normal_influence = 0.2;
        beech_atlas_v2_material.wind_shiver_directionality = 0.4;
        const beech_atlas_v2_material_handle = prefab_mgr.rctx.uploadMaterial(beech_atlas_v2_material) catch unreachable;

        var beech_tree_04 = prefab_mgr.loadPrefabFromBinary("prefabs/environment/beech/beech_tree_04_LOD0.bin", beech_tree_04_id, pos_uv0_nor_tan_col_uv1_vertex_layout, ecsu_world);
        const static_mesh_component = beech_tree_04.getMut(fd.StaticMesh);
        if (static_mesh_component) |static_mesh| {
            static_mesh.material_count = 2;

            static_mesh.materials[0] = beech_trunk_04_material_handle;
            static_mesh.materials[1] = beech_atlas_v2_material_handle;
        }
    }
}
