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

pub const palisade_400x300_a_id = ID("palisade_400x300_a");
pub const palisade_400x300_b_id = ID("palisade_400x300_b");
pub const palisade_sloped_400x300_a_id = ID("palisade_sloped_400x300_a");
pub const palisade_sloped_400x300_b_id = ID("palisade_sloped_400x300_b");
pub const house_3x5_id = ID("house_3x5_id");

pub const prefabs = [_]IdLocal{
    arrow_id,
    bow_id,
    giant_ant_id,
    beech_tree_04_id,
    house_3x5_id,
    palisade_400x300_a_id,
    palisade_400x300_b_id,
    palisade_sloped_400x300_a_id,
    palisade_sloped_400x300_b_id,
};

// TODO(gmodarelli): We need an Asset Database to store meshes, textures, materials and prefabs instead of managing them all through prefabs
pub fn initPrefabs(prefab_mgr: *prefab_manager.PrefabManager, ecsu_world: ecsu.World) void {
    // TODO: Declare this in pso so we can reuse the IdLocal instead of initializing them here again
    const pipeline_lit_gbuffer_opaque_id = IdLocal.init("lit_gbuffer_opaque");
    const pipeline_lit_depth_only_opaque_id = IdLocal.init("lit_depth_only_opaque");
    const pipeline_lit_gbuffer_cutout_id = IdLocal.init("lit_gbuffer_cutout");
    _ = pipeline_lit_gbuffer_cutout_id;
    const pipeline_lit_depth_only_cutout_id = IdLocal.init("lit_depth_only_cutout");
    _ = pipeline_lit_depth_only_cutout_id;

    const pipeline_tree_gbuffer_opaque_id = IdLocal.init("tree_gbuffer_opaque");
    const pipeline_tree_gbuffer_cutout_id = IdLocal.init("tree_gbuffer_cutout");
    const pipeline_tree_depth_only_opaque_id = IdLocal.init("tree_depth_only_opaque");
    const pipeline_tree_depth_only_cutout_id = IdLocal.init("tree_depth_only_cutout");

    const pipeline_shadow_caster_opaque_id = IdLocal.init("lit_shadow_caster_opaque");
    const pipeline_shadow_caster_cutout_id = IdLocal.init("lit_shadow_caster_cutout");
    _ = pipeline_shadow_caster_cutout_id;
    const pipeline_tree_shadow_caster_opaque_id = IdLocal.init("tree_shadow_caster_opaque");
    const pipeline_tree_shadow_caster_masked_id = IdLocal.init("tree_shadow_caster_cutout");

    var default_material = fd.UberShader.initNoTexture(fd.ColorRGB.init(0.5, 0.5, 0.5), 0.8, 0.0);
    default_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
    default_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
    default_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
    const default_material_handle = prefab_mgr.rctx.uploadMaterial(default_material) catch unreachable;

    const pos_uv0_nor_tan_col_vertex_layout = IdLocal.init("pos_uv0_nor_tan_col");
    const pos_uv0_nor_tan_col_uv1_vertex_layout = IdLocal.init("pos_uv0_nor_tan_col_uv1");

    {
        player = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/characters/player/player", player_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        player.setOverride(fd.Dynamic{});

        const lod_group_component = player.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                for (0..lod_group.lods[i].materials.items.len) |material_index| {
                    lod_group.lods[i].materials.items[material_index] = default_material_handle;
                }
            }
        }
    }

    {
        var material = fd.UberShader.init();
        material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        material.albedo = prefab_mgr.rctx.loadTexture("textures/debug/round_aluminum_panel_albedo.dds");
        material.arm = prefab_mgr.rctx.loadTexture("textures/debug/round_aluminum_panel_arm.dds");
        material.normal = prefab_mgr.rctx.loadTexture("textures/debug/round_aluminum_panel_normal.dds");
        const material_handle = prefab_mgr.rctx.uploadMaterial(material) catch unreachable;

        matball = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/primitives/matball", matball_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        matball.setOverride(fd.Dynamic{});

        const lod_group_component = matball.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials.items.len == 1);
                lod_group.lods[i].materials.items[0] = material_handle;
            }
        }
    }

    {
        var material = fd.UberShader.init();
        material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        material.albedo = prefab_mgr.rctx.loadTexture("prefabs/props/color_calibrator/color_checker_albedo.dds");
        const material_handle = prefab_mgr.rctx.uploadMaterial(material) catch unreachable;

        color_calibrator = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/props/color_calibrator/color_calibrator", color_calibrator_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        color_calibrator.setOverride(fd.Dynamic{});

        const lod_group_component = color_calibrator.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials.items.len == 1);
                lod_group.lods[i].materials.items[0] = material_handle;
            }
        }
    }

    {
        var material = fd.UberShader.init();
        material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        material.albedo = prefab_mgr.rctx.loadTexture("prefabs/creatures/giant_ant/giant_ant_albedo.dds");
        material.arm = prefab_mgr.rctx.loadTexture("prefabs/creatures/giant_ant/giant_ant_arm.dds");
        material.normal = prefab_mgr.rctx.loadTexture("prefabs/creatures/giant_ant/giant_ant_normal.dds");
        const material_handle = prefab_mgr.rctx.uploadMaterial(material) catch unreachable;

        giant_ant = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/creatures/giant_ant/giant_ant", giant_ant_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        giant_ant.setOverride(fd.Dynamic{});

        const lod_group_component = giant_ant.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials.items.len == 1);
                lod_group.lods[i].materials.items[0] = material_handle;
            }
        }
    }

    {
        var material = fd.UberShader.init();
        material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        material.albedo = prefab_mgr.rctx.loadTexture("prefabs/props/bow_arrow/bow_arrow_albedo.dds");
        material.arm = prefab_mgr.rctx.loadTexture("prefabs/props/bow_arrow/bow_arrow_arm.dds");
        material.normal = prefab_mgr.rctx.loadTexture("prefabs/props/bow_arrow/bow_arrow_normal.dds");
        const material_handle = prefab_mgr.rctx.uploadMaterial(material) catch unreachable;

        {
            bow = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/props/bow_arrow/bow", bow_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
            bow.setOverride(fd.Dynamic{});

            const lod_group_component = bow.getMut(fd.LodGroup);
            if (lod_group_component) |lod_group| {
                for (0..lod_group.lod_count) |i| {
                    std.debug.assert(lod_group.lods[i].materials.items.len == 1);
                    lod_group.lods[i].materials.items[0] = material_handle;
                }
            }
        }

        {
            var arrow = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/props/bow_arrow/arrow", arrow_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
            arrow.setOverride(fd.Dynamic{});

            const lod_group_component = arrow.getMut(fd.LodGroup);
            if (lod_group_component) |lod_group| {
                for (0..lod_group.lod_count) |i| {
                    std.debug.assert(lod_group.lods[i].materials.items.len == 1);
                    lod_group.lods[i].materials.items[0] = material_handle;
                }
            }
        }
    }

    {
        default_cube = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/primitives/primitive_cube", cube_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        default_cube.setOverride(fd.Dynamic{});

        const lod_group_component = default_cube.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials.items.len == 1);
                lod_group.lods[i].materials.items[0] = default_material_handle;
            }
        }
    }

    {
        var cylinder = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/primitives/primitive_cylinder", cylinder_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        cylinder.setOverride(fd.Dynamic{});

        const lod_group_component = cylinder.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials.items.len == 1);
                lod_group.lods[i].materials.items[0] = default_material_handle;
            }
        }
    }

    {
        var plane = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/primitives/primitive_plane", plane_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        plane.setOverride(fd.Dynamic{});

        const lod_group_component = plane.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials.items.len == 1);
                lod_group.lods[i].materials.items[0] = default_material_handle;
            }
        }
    }

    {
        var sphere = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/primitives/primitive_sphere", sphere_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        sphere.setOverride(fd.Dynamic{});

        const lod_group_component = sphere.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials.items.len == 1);
                lod_group.lods[i].materials.items[0] = default_material_handle;
            }
        }
    }

    {
        var roof_material = fd.UberShader.init();
        roof_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        roof_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        roof_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        roof_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_roof_albedo.dds");
        roof_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_roof_arm.dds");
        roof_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_roof_normal.dds");
        const roof_material_handle = prefab_mgr.rctx.uploadMaterial(roof_material) catch unreachable;

        var wood_material = fd.UberShader.init();
        wood_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        wood_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        wood_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        wood_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_wood_albedo.dds");
        wood_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_wood_arm.dds");
        wood_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_wood_normal.dds");
        const wood_material_handle = prefab_mgr.rctx.uploadMaterial(wood_material) catch unreachable;

        var plaster_material = fd.UberShader.init();
        plaster_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        plaster_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        plaster_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        plaster_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_albedo.dds");
        plaster_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_arm.dds");
        plaster_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_normal.dds");
        const plaster_material_handle = prefab_mgr.rctx.uploadMaterial(plaster_material) catch unreachable;

        var stone_material = fd.UberShader.init();
        stone_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        stone_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        stone_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        stone_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_stone_albedo.dds");
        stone_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_stone_arm.dds");
        stone_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_stone_normal.dds");
        const stone_material_handle = prefab_mgr.rctx.uploadMaterial(stone_material) catch unreachable;

        var medium_house = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/buildings/medium_house/medium_house", medium_house_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        const lod_group_component = medium_house.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials.items.len == 4);

                lod_group.lods[i].materials.items[0] = roof_material_handle;
                lod_group.lods[i].materials.items[1] = wood_material_handle;
                lod_group.lods[i].materials.items[2] = plaster_material_handle;
                lod_group.lods[i].materials.items[3] = stone_material_handle;
            }
        }
    }

    {
        var beech_trunk_04_material = fd.UberShader.init();
        beech_trunk_04_material.depth_only_pipeline_id = pipeline_tree_depth_only_opaque_id;
        beech_trunk_04_material.gbuffer_pipeline_id = pipeline_tree_gbuffer_opaque_id;
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
        beech_atlas_v2_material.depth_only_pipeline_id = pipeline_tree_depth_only_cutout_id;
        beech_atlas_v2_material.gbuffer_pipeline_id = pipeline_tree_gbuffer_cutout_id;
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

        var beech_tree_04 = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/environment/beech/beech_tree_04", beech_tree_04_id, pos_uv0_nor_tan_col_uv1_vertex_layout, ecsu_world);
        const lod_group_component = beech_tree_04.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {

                std.debug.assert(lod_group.lods[i].materials.items.len == 2);

                lod_group.lods[i].materials.items[0] = beech_trunk_04_material_handle;
                lod_group.lods[i].materials.items[1] = beech_atlas_v2_material_handle;
            }
        }
    }

    {
        var palisade_400x300_a = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/props/palisades/palisade_400x300_a", palisade_400x300_a_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);

        const lod_group_component = palisade_400x300_a.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                for (0..lod_group.lods[i].materials.items.len) |material_index| {
                    lod_group.lods[i].materials.items[material_index] = default_material_handle;
                }
            }
        }
    }

    {
        var palisade_400x300_b = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/props/palisades/palisade_400x300_b", palisade_400x300_b_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);

        const lod_group_component = palisade_400x300_b.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                for (0..lod_group.lods[i].materials.items.len) |material_index| {
                    lod_group.lods[i].materials.items[material_index] = default_material_handle;
                }
            }
        }
    }

    {
        var palisade_sloped_400x300_a = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/props/palisades/palisade_sloped_400x300_a", palisade_sloped_400x300_a_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);

        const lod_group_component = palisade_sloped_400x300_a.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                for (0..lod_group.lods[i].materials.items.len) |material_index| {
                    lod_group.lods[i].materials.items[material_index] = default_material_handle;
                }
            }
        }
    }

    {
        var palisade_sloped_400x300_b = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/props/palisades/palisade_sloped_400x300_b", palisade_sloped_400x300_b_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);

        const lod_group_component = palisade_sloped_400x300_b.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                for (0..lod_group.lods[i].materials.items.len) |material_index| {
                    lod_group.lods[i].materials.items[material_index] = default_material_handle;
                }
            }
        }
    }

    {
        // var vine_material = fd.UberShader.init();
        // vine_material.depth_only_pipeline_id = pipeline_lit_depth_only_cutout_id;
        // vine_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_cutout_id;
        // vine_material.shadow_caster_pipeline_id = pipeline_shadow_caster_cutout_id;
        // vine_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_VineLeaf_BaseColor.dds");
        // vine_material.base_color = fd.ColorRGB.init(0.1, 0.34, 0);
        // const vine_material_handle = prefab_mgr.rctx.uploadMaterial(vine_material) catch unreachable;

        var wood_trim_material = fd.UberShader.init();
        wood_trim_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        wood_trim_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        wood_trim_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        wood_trim_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_WoodTrim_BaseColor.dds");
        wood_trim_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_WoodTrim_Roughness.dds");
        wood_trim_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_WoodTrim_Normal.dds");
        const wood_trim_material_handle = prefab_mgr.rctx.uploadMaterial(wood_trim_material) catch unreachable;

        var plaster_material = fd.UberShader.init();
        plaster_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        plaster_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        plaster_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        plaster_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_Plaster_BaseColor.dds");
        plaster_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_Plaster_ORM.dds");
        plaster_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_Plaster_Normal.dds");
        const plaster_material_handle = prefab_mgr.rctx.uploadMaterial(plaster_material) catch unreachable;

        var brick_material = fd.UberShader.init();
        brick_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        brick_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        brick_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        brick_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_Brick_BaseColor.dds");
        brick_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_Brick_Roughness.dds");
        brick_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_Brick_Normal.dds");
        const brick_material_handle = prefab_mgr.rctx.uploadMaterial(brick_material) catch unreachable;

        var uneven_brick_material = fd.UberShader.init();
        uneven_brick_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        uneven_brick_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        uneven_brick_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        uneven_brick_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_UnevenBrick_BaseColor.dds");
        uneven_brick_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_UnevenBrick_Roughness.dds");
        uneven_brick_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_UnevenBrick_Normal.dds");
        const uneven_brick_material_handle = prefab_mgr.rctx.uploadMaterial(uneven_brick_material) catch unreachable;

        var flat_tiles_material = fd.UberShader.init();
        flat_tiles_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        flat_tiles_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        flat_tiles_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        flat_tiles_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_FlatTiles_BaseColor.dds");
        flat_tiles_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_FlatTiles_Roughness.dds");
        flat_tiles_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_FlatTiles_Normal.dds");
        flat_tiles_material.normal_intensity = 0.5;
        const flat_tiles_material_handle = prefab_mgr.rctx.uploadMaterial(flat_tiles_material) catch unreachable;

        var round_tiles_material = fd.UberShader.init();
        round_tiles_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        round_tiles_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        round_tiles_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        round_tiles_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_RoundTiles_BaseColor.dds");
        round_tiles_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_RoundTiles_Roughness.dds");
        round_tiles_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_RoundTiles_Normal.dds");
        const round_tiles_material_handle = prefab_mgr.rctx.uploadMaterial(round_tiles_material) catch unreachable;

        // var window_glass_material = fd.UberShader.initNoTexture(fd.ColorRGB.init(0.8, 0.8, 0.8), 0.5, 0.0);
        // window_glass_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        // window_glass_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        // window_glass_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        // const window_glass_material_handle = prefab_mgr.rctx.uploadMaterial(window_glass_material) catch unreachable;

        var rock_trim_material = fd.UberShader.init();
        rock_trim_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        rock_trim_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        rock_trim_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        rock_trim_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_RockTrim_BaseColor.dds");
        rock_trim_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_RockTrim_ORM.dds");
        rock_trim_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_RockTrim_Normal.dds");
        const rock_trim_material_handle = prefab_mgr.rctx.uploadMaterial(rock_trim_material) catch unreachable;

        var metal_ornaments_material = fd.UberShader.init();
        metal_ornaments_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        metal_ornaments_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        metal_ornaments_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        metal_ornaments_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_MetalOrnaments_BaseColor.dds");
        metal_ornaments_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_MetalOrnaments_Roughness.dds");
        const metal_ornaments_material_handle = prefab_mgr.rctx.uploadMaterial(metal_ornaments_material) catch unreachable;

        var house_3x5 = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/buildings/medieval_village/houses/house_3x5", house_3x5_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);

        const lod_group_component = house_3x5.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials.items.len == 9);

                lod_group.lods[i].materials.items[0] = wood_trim_material_handle;
                lod_group.lods[i].materials.items[1] = plaster_material_handle;
                lod_group.lods[i].materials.items[2] = brick_material_handle;
                lod_group.lods[i].materials.items[3] = flat_tiles_material_handle;
                lod_group.lods[i].materials.items[4] = round_tiles_material_handle;
                lod_group.lods[i].materials.items[5] = rock_trim_material_handle;
                lod_group.lods[i].materials.items[6] = wood_trim_material_handle;
                lod_group.lods[i].materials.items[7] = metal_ornaments_material_handle;
                lod_group.lods[i].materials.items[8] = uneven_brick_material_handle;
            }
        }
    }
}
