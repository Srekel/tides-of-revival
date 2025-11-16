const std = @import("std");
const prefab_manager = @import("../prefab_manager.zig");
const core = @import("../core/core.zig");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("flecs_data.zig");
const renderer = @import("../renderer/renderer.zig");
const IdLocal = core.IdLocal;
const ID = @import("../core/core.zig").ID;

pub var bow: ecsu.Entity = undefined;
pub var color_calibrator: ecsu.Entity = undefined;
pub var default_cube: ecsu.Entity = undefined;
pub var giant_ant: ecsu.Entity = undefined;
pub var matball: ecsu.Entity = undefined;
pub var player: ecsu.Entity = undefined;
pub var slime: ecsu.Entity = undefined;
pub var slime_trail: ecsu.Entity = undefined;
pub var campfire: ecsu.Entity = undefined;

pub const arrow_id = ID("prefab_arrow");
pub const beech_tree_04_id = ID("beech_tree_04");
pub const bow_id = ID("prefab_bow");
pub const color_calibrator_id = ID("color_calibrator");
pub const giant_ant_id = ID("prefab_giant_ant");
pub const matball_id = ID("prefab_matball");
pub const medium_house_id = ID("prefab_medium_house");
pub const player_id = ID("prefab_player");
pub const skybox_id = ID("prefab_skybox");
pub const slime_id = ID("prefab_slime");
pub const slime_trail_id = ID("prefab_slime_trail");

pub const cube_id = ID("prefab_cube");
pub const cylinder_id = ID("prefab_cylinder");
pub const debug_sphere_id = ID("prefab_debug_sphere");
pub const plane_id = ID("prefab_plane");
pub const sphere_id = ID("prefab_sphere");

pub const palisade_400x300_a_id = ID("palisade_400x300_a_id");
pub const palisade_400x300_b_id = ID("palisade_400x300_b_id");
pub const palisade_sloped_400x300_a_id = ID("palisade_sloped_400x300_a");
pub const palisade_sloped_400x300_b_id = ID("palisade_sloped_400x300_b");
pub const house_3x5_id = ID("house_3x5_id");

pub const brazier_1_id = ID("brazier_1_id");
pub const brazier_2_id = ID("brazier_2_id");
pub const stacked_stones_id = ID("stacked_stones");

// pub const prefabs = [_]IdLocal{
//     arrow_id,
//     bow_id,
//     brazier_1_id,
//     brazier_2_id,
//     giant_ant_id,
//     house_3x5_id,
//     palisade_400x300_a_id,
//     palisade_400x300_b_id,
//     palisade_sloped_400x300_a_id,
//     palisade_sloped_400x300_b_id,
//     slime_id,
//     slime_trail_id,
//     stacked_stones_id,
// };

// TODO(gmodarelli): We need an Asset Database to store meshes, textures, materials and prefabs instead of managing them all through prefabs
pub fn initPrefabs(prefab_mgr: *prefab_manager.PrefabManager, ecsu_world: ecsu.World) void {
    // TODO: Declare this in pso so we can reuse the IdLocal instead of initializing them here again
    const pipeline_lit_gbuffer_opaque_id = IdLocal.init("lit_gbuffer_opaque");
    const pipeline_lit_gbuffer_cutout_id = IdLocal.init("lit_gbuffer_cutout");
    _ = pipeline_lit_gbuffer_cutout_id;

    const pso_meshlet_opaque_gbuffer_id = IdLocal.init("meshlet_gbuffer_opaque");
    const pso_meshlet_masked_gbuffer_id = IdLocal.init("meshlet_gbuffer_masked");

    const pipeline_shadow_caster_opaque_id = IdLocal.init("lit_shadow_caster_opaque");

    const default_material_id = ID("legacy_default");
    var default_material = renderer.UberShaderMaterialData.initNoTexture(fd.ColorRGB.init(0.5, 0.5, 0.5), 0.8, 0.0);
    default_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
    default_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
    prefab_mgr.rctx.loadMaterial(default_material_id, default_material) catch unreachable;

    const pos_uv0_nor_tan_col_vertex_layout = IdLocal.init("pos_uv0_nor_tan_col");

    {
        player = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/characters/player/player", player_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        player.setOverride(fd.Dynamic{});

        const lod_group_component = player.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                for (0..lod_group.lods[i].materials_count) |material_index| {
                    lod_group.lods[i].materials[material_index] = default_material_id;
                }
            }
        }
    }

    {
        var material = renderer.UberShaderMaterialData.init();
        material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        material.albedo = prefab_mgr.rctx.loadTexture("textures/debug/round_aluminum_panel_albedo.dds");
        material.arm = prefab_mgr.rctx.loadTexture("textures/debug/round_aluminum_panel_arm.dds");
        material.normal = prefab_mgr.rctx.loadTexture("textures/debug/round_aluminum_panel_normal.dds");
        const material_id = ID("round_aluminum");
        prefab_mgr.rctx.loadMaterial(material_id, material) catch unreachable;

        matball = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/primitives/matball", matball_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        matball.setOverride(fd.Dynamic{});

        const lod_group_component = matball.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials_count == 1);
                lod_group.lods[i].materials[0] = material_id;
            }
        }
    }

    {
        var material = renderer.UberShaderMaterialData.init();
        material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        material.albedo = prefab_mgr.rctx.loadTexture("prefabs/props/color_calibrator/color_checker_albedo.dds");
        const material_id = ID("color_checker");
        prefab_mgr.rctx.loadMaterial(material_id, material) catch unreachable;

        color_calibrator = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/props/color_calibrator/color_calibrator", color_calibrator_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        color_calibrator.setOverride(fd.Dynamic{});

        const lod_group_component = color_calibrator.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials_count == 1);
                lod_group.lods[i].materials[0] = material_id;
            }
        }
    }

    {
        var material = renderer.UberShaderMaterialData.init();
        material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        material.albedo = prefab_mgr.rctx.loadTexture("prefabs/creatures/giant_ant/giant_ant_albedo.dds");
        material.arm = prefab_mgr.rctx.loadTexture("prefabs/creatures/giant_ant/giant_ant_arm.dds");
        material.normal = prefab_mgr.rctx.loadTexture("prefabs/creatures/giant_ant/giant_ant_normal.dds");
        const material_id = ID("giant_ant");
        prefab_mgr.rctx.loadMaterial(material_id, material) catch unreachable;

        giant_ant = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/creatures/giant_ant/giant_ant", giant_ant_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        giant_ant.setOverride(fd.Dynamic{});

        const lod_group_component = giant_ant.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials_count == 1);
                lod_group.lods[i].materials[0] = material_id;
            }
        }
    }

    {
        var material = renderer.UberShaderMaterialData.init();
        material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        material.albedo = prefab_mgr.rctx.loadTexture("prefabs/props/bow_arrow/bow_arrow_albedo.dds");
        material.arm = prefab_mgr.rctx.loadTexture("prefabs/props/bow_arrow/bow_arrow_arm.dds");
        material.normal = prefab_mgr.rctx.loadTexture("prefabs/props/bow_arrow/bow_arrow_normal.dds");
        const material_id = ID("bow_arrow");
        prefab_mgr.rctx.loadMaterial(material_id, material) catch unreachable;

        {
            bow = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/props/bow_arrow/bow", bow_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
            bow.setOverride(fd.Dynamic{});

            const lod_group_component = bow.getMut(fd.LodGroup);
            if (lod_group_component) |lod_group| {
                for (0..lod_group.lod_count) |i| {
                    std.debug.assert(lod_group.lods[i].materials_count == 1);
                    lod_group.lods[i].materials[0] = material_id;
                }
            }
        }

        {
            var arrow = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/props/bow_arrow/arrow", arrow_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
            arrow.setOverride(fd.Dynamic{});

            const lod_group_component = arrow.getMut(fd.LodGroup);
            if (lod_group_component) |lod_group| {
                for (0..lod_group.lod_count) |i| {
                    std.debug.assert(lod_group.lods[i].materials_count == 1);
                    lod_group.lods[i].materials[0] = material_id;
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
                std.debug.assert(lod_group.lods[i].materials_count == 1);
                lod_group.lods[i].materials[0] = default_material_id;
            }
        }
    }

    {
        var cylinder = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/primitives/primitive_cylinder", cylinder_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        cylinder.setOverride(fd.Dynamic{});

        const lod_group_component = cylinder.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials_count == 1);
                lod_group.lods[i].materials[0] = default_material_id;
            }
        }
    }

    {
        var plane = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/primitives/primitive_plane", plane_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        plane.setOverride(fd.Dynamic{});

        const lod_group_component = plane.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials_count == 1);
                lod_group.lods[i].materials[0] = default_material_id;
            }
        }
    }

    {
        var sphere = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/primitives/primitive_sphere", sphere_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        sphere.setOverride(fd.Dynamic{});

        const lod_group_component = sphere.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials_count == 1);
                lod_group.lods[i].materials[0] = default_material_id;
            }
        }
    }

    const slime_material_id = ID("slime");
    var slime_material = renderer.UberShaderMaterialData.initNoTexture(fd.ColorRGB.init(0.1, 0.6, 0.2), 0.3, 0.0);
    slime_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
    slime_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
    prefab_mgr.rctx.loadMaterial(slime_material_id, slime_material) catch unreachable;

    {
        slime = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/creatures/slime/slime", slime_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        slime.setOverride(fd.Dynamic{});

        const lod_group_component = slime.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials_count == 1);
                lod_group.lods[i].materials[0] = slime_material_id;
            }
        }
    }

    {
        slime_trail = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/creatures/slime/slime_trail", slime_trail_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        slime_trail.setOverride(fd.Dynamic{});

        const lod_group_component = slime_trail.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials_count == 1);
                lod_group.lods[i].materials[0] = slime_material_id;
            }
        }
    }

    {
        var roof_material = renderer.UberShaderMaterialData.init();
        roof_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        roof_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        roof_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_roof_albedo.dds");
        roof_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_roof_arm.dds");
        roof_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_roof_normal.dds");
        const roof_material_id = ID("medium_house_roof");
        prefab_mgr.rctx.loadMaterial(roof_material_id, roof_material) catch unreachable;

        var wood_material = renderer.UberShaderMaterialData.init();
        wood_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        wood_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        wood_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_wood_albedo.dds");
        wood_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_wood_arm.dds");
        wood_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_wood_normal.dds");
        const wood_material_id = ID("medium_house_wood");
        prefab_mgr.rctx.loadMaterial(wood_material_id, wood_material) catch unreachable;

        var plaster_material = renderer.UberShaderMaterialData.init();
        plaster_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        plaster_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        plaster_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_albedo.dds");
        plaster_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_arm.dds");
        plaster_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_plaster_normal.dds");
        const plaster_material_id = ID("medium_house_plaster");
        prefab_mgr.rctx.loadMaterial(plaster_material_id, plaster_material) catch unreachable;

        var stone_material = renderer.UberShaderMaterialData.init();
        stone_material.gbuffer_pipeline_id = pipeline_lit_gbuffer_opaque_id;
        stone_material.shadow_caster_pipeline_id = pipeline_shadow_caster_opaque_id;
        stone_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_stone_albedo.dds");
        stone_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_stone_arm.dds");
        stone_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medium_house/medium_house_stone_normal.dds");
        const stone_material_id = ID("medium_house_stone");
        prefab_mgr.rctx.loadMaterial(stone_material_id, stone_material) catch unreachable;

        var medium_house = prefab_mgr.createHierarchicalStaticMeshPrefab("prefabs/buildings/medium_house/medium_house", medium_house_id, pos_uv0_nor_tan_col_vertex_layout, ecsu_world);
        const lod_group_component = medium_house.getMut(fd.LodGroup);
        if (lod_group_component) |lod_group| {
            for (0..lod_group.lod_count) |i| {
                std.debug.assert(lod_group.lods[i].materials_count == 4);

                lod_group.lods[i].materials[0] = roof_material_id;
                lod_group.lods[i].materials[1] = wood_material_id;
                lod_group.lods[i].materials[2] = plaster_material_id;
                lod_group.lods[i].materials[3] = stone_material_id;
            }
        }
    }

    {
        const beech_04_LOD0_id = ID("beech_tree_04_lod0");
        prefab_mgr.rctx.loadMesh("content/prefabs/environment/beech/beech_tree_04_LOD0.mesh", beech_04_LOD0_id) catch unreachable;
        const beech_04_LOD1_id = ID("beech_tree_04_lod1");
        prefab_mgr.rctx.loadMesh("content/prefabs/environment/beech/beech_tree_04_LOD1.mesh", beech_04_LOD1_id) catch unreachable;
        const beech_04_LOD2_id = ID("beech_tree_04_lod2");
        prefab_mgr.rctx.loadMesh("content/prefabs/environment/beech/beech_tree_04_LOD2.mesh", beech_04_LOD2_id) catch unreachable;
        const beech_04_LOD3_id = ID("beech_tree_04_lod3");
        prefab_mgr.rctx.loadMesh("content/prefabs/environment/beech/beech_tree_04_LOD3.mesh", beech_04_LOD3_id) catch unreachable;

        var beech_trunk_04_material = renderer.UberShaderMaterialData.init();
        beech_trunk_04_material.gbuffer_pipeline_id = pso_meshlet_opaque_gbuffer_id;
        beech_trunk_04_material.shadow_caster_pipeline_id = null;
        beech_trunk_04_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_trunk_04_albedo.dds");
        beech_trunk_04_material.arm = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_trunk_04_arm.dds");
        beech_trunk_04_material.normal = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_trunk_04_normal.dds");

        const beech_trunk_04_material_id = ID("beech_trunk_04");
        prefab_mgr.rctx.loadMaterial(beech_trunk_04_material_id, beech_trunk_04_material) catch unreachable;

        var beech_atlas_v2_material = renderer.UberShaderMaterialData.init();
        beech_atlas_v2_material.alpha_test = true;
        beech_atlas_v2_material.gbuffer_pipeline_id = pso_meshlet_masked_gbuffer_id;
        beech_atlas_v2_material.shadow_caster_pipeline_id = null;
        beech_atlas_v2_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_atlas_v2_albedo.dds");
        beech_atlas_v2_material.arm = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_atlas_arm.dds");
        beech_atlas_v2_material.normal = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_atlas_normal.dds");
        beech_atlas_v2_material.random_color_feature_enabled = true;
        beech_atlas_v2_material.random_color_noise_scale = 0.01;
        beech_atlas_v2_material.random_color_gradient = prefab_mgr.rctx.loadTexture("textures/debug/grass_gradient.dds");

        const beech_atlas_v2_material_id = ID("beech_atlas_v2");
        prefab_mgr.rctx.loadMaterial(beech_atlas_v2_material_id, beech_atlas_v2_material) catch unreachable;

        var beech_04_impostor_material = renderer.UberShaderMaterialData.init();
        beech_04_impostor_material.alpha_test = true;
        beech_04_impostor_material.gbuffer_pipeline_id = pso_meshlet_masked_gbuffer_id;
        beech_04_impostor_material.shadow_caster_pipeline_id = null;
        beech_04_impostor_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_04_impostor_albedo.dds");
        beech_04_impostor_material.normal = prefab_mgr.rctx.loadTexture("prefabs/environment/beech/beech_04_impostor_normal.dds");
        beech_04_impostor_material.roughness = 0.95;
        beech_04_impostor_material.random_color_feature_enabled = true;
        beech_04_impostor_material.random_color_noise_scale = 0.01;
        beech_04_impostor_material.random_color_gradient = beech_atlas_v2_material.random_color_gradient;

        const beech_04_impostor_material_id = ID("beech_04_impostor");
        prefab_mgr.rctx.loadMaterial(beech_04_impostor_material_id, beech_04_impostor_material) catch unreachable;

        var renderable_desc = renderer.RenderableDesc{
            .lods_count = 3,
            .lods = undefined,
        };
        renderable_desc.lods[0].mesh_id = beech_04_LOD0_id;
        renderable_desc.lods[0].materials_count = 2;
        renderable_desc.lods[0].materials[0] = beech_trunk_04_material_id;
        renderable_desc.lods[0].materials[1] = beech_atlas_v2_material_id;
        // renderable_desc.lods[0].screen_percentage_range[0] = 0.8;
        // renderable_desc.lods[0].screen_percentage_range[1] = 1.0;
        renderable_desc.lods[0].screen_percentage_range[0] = 0;
        renderable_desc.lods[0].screen_percentage_range[1] = 60;
        // renderable_desc.lods[1].mesh_id = beech_04_LOD1_id;
        // renderable_desc.lods[1].materials_count = 2;
        // renderable_desc.lods[1].materials[0] = beech_trunk_04_material_id;
        // renderable_desc.lods[1].materials[1] = beech_atlas_v2_material_id;
        // // renderable_desc.lods[1].screen_percentage_range[0] = 0.6;
        // // renderable_desc.lods[1].screen_percentage_range[1] = 0.8;
        // renderable_desc.lods[1].screen_percentage_range[0] = 19.5;
        // renderable_desc.lods[1].screen_percentage_range[1] = 40;
        renderable_desc.lods[1].mesh_id = beech_04_LOD2_id;
        renderable_desc.lods[1].materials_count = 2;
        renderable_desc.lods[1].materials[0] = beech_trunk_04_material_id;
        renderable_desc.lods[1].materials[1] = beech_atlas_v2_material_id;
        // renderable_desc.lods[1].screen_percentage_range[0] = 0.4;
        // renderable_desc.lods[1].screen_percentage_range[1] = 0.6;
        renderable_desc.lods[1].screen_percentage_range[0] = 59.5;
        renderable_desc.lods[1].screen_percentage_range[1] = 120;
        renderable_desc.lods[2].mesh_id = beech_04_LOD3_id;
        renderable_desc.lods[2].materials_count = 1;
        renderable_desc.lods[2].materials[0] = beech_04_impostor_material_id;
        // renderable_desc.lods[2].screen_percentage_range[0] = 0.0;
        // renderable_desc.lods[2].screen_percentage_range[1] = 0.4;
        renderable_desc.lods[2].screen_percentage_range[0] = 119.5;
        renderable_desc.lods[2].screen_percentage_range[1] = 30000;

        prefab_mgr.rctx.registerRenderable(beech_tree_04_id, renderable_desc);

        const beech_tree_04 = prefab_mgr.createRenderablePrefab(beech_tree_04_id, ecsu_world);
        var renderable = beech_tree_04.getMut(fd.Renderable).?;
        renderable.id = beech_tree_04_id;
    }

    {
        prefab_mgr.rctx.loadMesh("content/prefabs/props/roads/stacked_stones.mesh", stacked_stones_id) catch unreachable;

        const stacked_stone_material_id = ID("stacked_stone");
        var stacked_stone_material = renderer.UberShaderMaterialData.init();
        stacked_stone_material.gbuffer_pipeline_id = pso_meshlet_opaque_gbuffer_id;
        stacked_stone_material.shadow_caster_pipeline_id = null;
        stacked_stone_material.base_color = fd.ColorRGB.init(0.3, 0.3, 0.3);
        stacked_stone_material.roughness = 0.8;
        prefab_mgr.rctx.loadMaterial(stacked_stone_material_id, stacked_stone_material) catch unreachable;

        var renderable_desc = renderer.RenderableDesc{
            .lods_count = 1,
            .lods = undefined,
        };
        renderable_desc.lods[0].mesh_id = stacked_stones_id;
        renderable_desc.lods[0].materials_count = 1;
        renderable_desc.lods[0].materials[0] = stacked_stone_material_id;
        // renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        // renderable_desc.lods[0].screen_percentage_range[1] = 1.0;
        renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        renderable_desc.lods[0].screen_percentage_range[1] = 30000.0;
        prefab_mgr.rctx.registerRenderable(stacked_stones_id, renderable_desc);

        const stacked_stones = prefab_mgr.createRenderablePrefab(stacked_stones_id, ecsu_world);
        var renderable = stacked_stones.getMut(fd.Renderable).?;
        renderable.id = stacked_stones_id;

        // TEMP: Lantern light
        const light_ent = ecsu_world.newEntity();
        light_ent.childOf(stacked_stones);
        light_ent.set(fd.Position{ .x = 0, .y = 2, .z = 0 });
        light_ent.set(fd.Rotation{});
        light_ent.set(fd.Scale.createScalar(1));
        light_ent.set(fd.Transform{});
        light_ent.set(fd.Dynamic{});

        light_ent.set(fd.PointLight{
            .color = .{ .r = 1.0, .g = 0.8, .b = 0.6 },
            .range = 10,
            .intensity = 5,
        });
    }

    const wood_trim_material_id = ID("house_wood_trim");
    const metal_ornaments_material_id = ID("house_metal_ornaments");

    {
        var wood_trim_material = renderer.UberShaderMaterialData.init();
        wood_trim_material.gbuffer_pipeline_id = pso_meshlet_opaque_gbuffer_id;
        wood_trim_material.shadow_caster_pipeline_id = null;
        wood_trim_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_WoodTrim_BaseColor.dds");
        wood_trim_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_WoodTrim_Roughness.dds");
        wood_trim_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_WoodTrim_Normal.dds");
        prefab_mgr.rctx.loadMaterial(wood_trim_material_id, wood_trim_material) catch unreachable;

        var plaster_material = renderer.UberShaderMaterialData.init();
        plaster_material.gbuffer_pipeline_id = pso_meshlet_opaque_gbuffer_id;
        plaster_material.shadow_caster_pipeline_id = null;
        plaster_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_Plaster_BaseColor.dds");
        plaster_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_Plaster_ORM.dds");
        plaster_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_Plaster_Normal.dds");
        const plaster_material_id = ID("house_plaster");
        prefab_mgr.rctx.loadMaterial(plaster_material_id, plaster_material) catch unreachable;

        var brick_material = renderer.UberShaderMaterialData.init();
        brick_material.gbuffer_pipeline_id = pso_meshlet_opaque_gbuffer_id;
        brick_material.shadow_caster_pipeline_id = null;
        brick_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_Brick_BaseColor.dds");
        brick_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_Brick_Roughness.dds");
        brick_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_Brick_Normal.dds");
        const brick_material_id = ID("house_brick");
        prefab_mgr.rctx.loadMaterial(brick_material_id, brick_material) catch unreachable;

        var uneven_brick_material = renderer.UberShaderMaterialData.init();
        uneven_brick_material.gbuffer_pipeline_id = pso_meshlet_opaque_gbuffer_id;
        uneven_brick_material.shadow_caster_pipeline_id = null;
        uneven_brick_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_UnevenBrick_BaseColor.dds");
        uneven_brick_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_UnevenBrick_Roughness.dds");
        uneven_brick_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_UnevenBrick_Normal.dds");
        const uneven_brick_material_id = ID("house_uneven_brick");
        prefab_mgr.rctx.loadMaterial(uneven_brick_material_id, uneven_brick_material) catch unreachable;

        var flat_tiles_material = renderer.UberShaderMaterialData.init();
        flat_tiles_material.gbuffer_pipeline_id = pso_meshlet_opaque_gbuffer_id;
        flat_tiles_material.shadow_caster_pipeline_id = null;
        flat_tiles_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_FlatTiles_BaseColor.dds");
        flat_tiles_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_FlatTiles_Roughness.dds");
        flat_tiles_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_FlatTiles_Normal.dds");
        flat_tiles_material.normal_intensity = 0.5;
        const flat_tiles_material_id = ID("house_flat_tiles");
        prefab_mgr.rctx.loadMaterial(flat_tiles_material_id, flat_tiles_material) catch unreachable;

        var round_tiles_material = renderer.UberShaderMaterialData.init();
        round_tiles_material.gbuffer_pipeline_id = pso_meshlet_opaque_gbuffer_id;
        round_tiles_material.shadow_caster_pipeline_id = null;
        round_tiles_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_RoundTiles_BaseColor.dds");
        round_tiles_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_RoundTiles_Roughness.dds");
        round_tiles_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_RoundTiles_Normal.dds");
        const round_tiles_material_id = ID("house_round_tiles");
        prefab_mgr.rctx.loadMaterial(round_tiles_material_id, round_tiles_material) catch unreachable;

        // var window_glass_material = renderer.UberShaderMaterialData.initNoTexture(fd.ColorRGB.init(0.8, 0.8, 0.8), 0.5, 0.0);
        // window_glass_material.depth_only_pipeline_id = pipeline_lit_depth_only_opaque_id;
        // window_glass_material.gbuffer_pipeline_id = pso_meshlet_opaque_gbuffer_id;
        // window_glass_material.shadow_caster_pipeline_id = null;
        // const window_glass_material_id = ID("house_glass");
        // prefab_mgr.rctx.loadMaterial(window_glass_material_id, window_glass_material) catch unreachable;

        var rock_trim_material = renderer.UberShaderMaterialData.init();
        rock_trim_material.gbuffer_pipeline_id = pso_meshlet_opaque_gbuffer_id;
        rock_trim_material.shadow_caster_pipeline_id = null;
        rock_trim_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_RockTrim_BaseColor.dds");
        rock_trim_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_RockTrim_ORM.dds");
        rock_trim_material.normal = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_RockTrim_Normal.dds");
        const rock_trim_material_id = ID("house_rock_trim");
        prefab_mgr.rctx.loadMaterial(rock_trim_material_id, rock_trim_material) catch unreachable;

        var metal_ornaments_material = renderer.UberShaderMaterialData.init();
        metal_ornaments_material.gbuffer_pipeline_id = pso_meshlet_opaque_gbuffer_id;
        metal_ornaments_material.shadow_caster_pipeline_id = null;
        metal_ornaments_material.albedo = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_MetalOrnaments_BaseColor.dds");
        metal_ornaments_material.arm = prefab_mgr.rctx.loadTexture("prefabs/buildings/medieval_village/houses/T_MetalOrnaments_Roughness.dds");
        prefab_mgr.rctx.loadMaterial(metal_ornaments_material_id, metal_ornaments_material) catch unreachable;

        prefab_mgr.rctx.loadMesh("content/prefabs/buildings/medieval_village/houses/house_3x5.mesh", house_3x5_id) catch unreachable;

        var renderable_desc = renderer.RenderableDesc{
            .lods_count = 1,
            .lods = undefined,
        };
        renderable_desc.lods[0].mesh_id = house_3x5_id;
        renderable_desc.lods[0].materials_count = 9;
        renderable_desc.lods[0].materials[0] = wood_trim_material_id;
        renderable_desc.lods[0].materials[1] = plaster_material_id;
        renderable_desc.lods[0].materials[2] = brick_material_id;
        renderable_desc.lods[0].materials[3] = flat_tiles_material_id;
        renderable_desc.lods[0].materials[4] = round_tiles_material_id;
        renderable_desc.lods[0].materials[5] = rock_trim_material_id;
        renderable_desc.lods[0].materials[6] = wood_trim_material_id;
        renderable_desc.lods[0].materials[7] = metal_ornaments_material_id;
        renderable_desc.lods[0].materials[8] = uneven_brick_material_id;
        // renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        // renderable_desc.lods[0].screen_percentage_range[1] = 1.0;
        renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        renderable_desc.lods[0].screen_percentage_range[1] = 30000.0;
        prefab_mgr.rctx.registerRenderable(house_3x5_id, renderable_desc);

        const entity = prefab_mgr.createRenderablePrefab(house_3x5_id, ecsu_world);
        var renderable = entity.getMut(fd.Renderable).?;
        renderable.id = house_3x5_id;
    }

    {
        prefab_mgr.rctx.loadMesh("content/prefabs/props/palisades/palisade_400x300_a.mesh", palisade_400x300_a_id) catch unreachable;

        var renderable_desc = renderer.RenderableDesc{
            .lods_count = 1,
            .lods = undefined,
        };
        renderable_desc.lods[0].mesh_id = palisade_400x300_a_id;
        renderable_desc.lods[0].materials_count = 1;
        renderable_desc.lods[0].materials[0] = wood_trim_material_id;
        // renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        // renderable_desc.lods[0].screen_percentage_range[1] = 1.0;
        renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        renderable_desc.lods[0].screen_percentage_range[1] = 30000.0;
        prefab_mgr.rctx.registerRenderable(palisade_400x300_a_id, renderable_desc);

        const entity = prefab_mgr.createRenderablePrefab(palisade_400x300_a_id, ecsu_world);
        var renderable = entity.getMut(fd.Renderable).?;
        renderable.id = palisade_400x300_a_id;
    }

    {
        prefab_mgr.rctx.loadMesh("content/prefabs/props/palisades/palisade_400x300_b.mesh", palisade_400x300_b_id) catch unreachable;

        var renderable_desc = renderer.RenderableDesc{
            .lods_count = 1,
            .lods = undefined,
        };
        renderable_desc.lods[0].mesh_id = palisade_400x300_b_id;
        renderable_desc.lods[0].materials_count = 1;
        renderable_desc.lods[0].materials[0] = wood_trim_material_id;
        // renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        // renderable_desc.lods[0].screen_percentage_range[1] = 1.0;
        renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        renderable_desc.lods[0].screen_percentage_range[1] = 30000.0;
        prefab_mgr.rctx.registerRenderable(palisade_400x300_b_id, renderable_desc);

        const entity = prefab_mgr.createRenderablePrefab(palisade_400x300_b_id, ecsu_world);
        var renderable = entity.getMut(fd.Renderable).?;
        renderable.id = palisade_400x300_b_id;
    }

    {
        prefab_mgr.rctx.loadMesh("content/prefabs/props/palisades/palisade_sloped_400x300_a.mesh", palisade_sloped_400x300_a_id) catch unreachable;

        var renderable_desc = renderer.RenderableDesc{
            .lods_count = 1,
            .lods = undefined,
        };
        renderable_desc.lods[0].mesh_id = palisade_sloped_400x300_a_id;
        renderable_desc.lods[0].materials_count = 1;
        renderable_desc.lods[0].materials[0] = wood_trim_material_id;
        // renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        // renderable_desc.lods[0].screen_percentage_range[1] = 1.0;
        renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        renderable_desc.lods[0].screen_percentage_range[1] = 30000.0;
        prefab_mgr.rctx.registerRenderable(palisade_sloped_400x300_a_id, renderable_desc);

        const entity = prefab_mgr.createRenderablePrefab(palisade_sloped_400x300_a_id, ecsu_world);
        var renderable = entity.getMut(fd.Renderable).?;
        renderable.id = palisade_sloped_400x300_a_id;
    }

    {
        prefab_mgr.rctx.loadMesh("content/prefabs/props/palisades/palisade_sloped_400x300_b.mesh", palisade_sloped_400x300_b_id) catch unreachable;

        var renderable_desc = renderer.RenderableDesc{
            .lods_count = 1,
            .lods = undefined,
        };
        renderable_desc.lods[0].mesh_id = palisade_sloped_400x300_b_id;
        renderable_desc.lods[0].materials_count = 1;
        renderable_desc.lods[0].materials[0] = wood_trim_material_id;
        // renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        // renderable_desc.lods[0].screen_percentage_range[1] = 1.0;
        renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        renderable_desc.lods[0].screen_percentage_range[1] = 30000.0;
        prefab_mgr.rctx.registerRenderable(palisade_sloped_400x300_b_id, renderable_desc);

        const entity = prefab_mgr.createRenderablePrefab(palisade_sloped_400x300_b_id, ecsu_world);
        var renderable = entity.getMut(fd.Renderable).?;
        renderable.id = palisade_sloped_400x300_b_id;
    }

    {
        prefab_mgr.rctx.loadMesh("content/prefabs/props/braziers/brazier_1.mesh", brazier_1_id) catch unreachable;

        var renderable_desc = renderer.RenderableDesc{
            .lods_count = 1,
            .lods = undefined,
        };
        renderable_desc.lods[0].mesh_id = brazier_1_id;
        renderable_desc.lods[0].materials_count = 2;
        renderable_desc.lods[0].materials[0] = wood_trim_material_id;
        renderable_desc.lods[0].materials[1] = metal_ornaments_material_id;
        // renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        // renderable_desc.lods[0].screen_percentage_range[1] = 1.0;
        renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        renderable_desc.lods[0].screen_percentage_range[1] = 30000.0;
        prefab_mgr.rctx.registerRenderable(brazier_1_id, renderable_desc);

        campfire = prefab_mgr.createRenderablePrefab(brazier_1_id, ecsu_world);
        var renderable = campfire.getMut(fd.Renderable).?;
        renderable.id = brazier_1_id;

        // TEMP: Lantern light
        const light_ent = ecsu_world.newEntity();
        light_ent.childOf(campfire);
        light_ent.set(fd.Position{ .x = 0, .y = 2, .z = 0 });
        light_ent.set(fd.Rotation{});
        light_ent.set(fd.Scale.createScalar(1));
        light_ent.set(fd.Transform{});
        light_ent.set(fd.Dynamic{});

        light_ent.set(fd.PointLight{
            .color = .{ .r = 1.0, .g = 0.8, .b = 0.6 },
            .range = 10,
            .intensity = 5,
        });
    }

    {
        prefab_mgr.rctx.loadMesh("content/prefabs/props/braziers/brazier_2.mesh", brazier_2_id) catch unreachable;

        var renderable_desc = renderer.RenderableDesc{
            .lods_count = 1,
            .lods = undefined,
        };
        renderable_desc.lods[0].mesh_id = brazier_2_id;
        renderable_desc.lods[0].materials_count = 2;
        renderable_desc.lods[0].materials[0] = wood_trim_material_id;
        renderable_desc.lods[0].materials[1] = metal_ornaments_material_id;
        // renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        // renderable_desc.lods[0].screen_percentage_range[1] = 1.0;
        renderable_desc.lods[0].screen_percentage_range[0] = 0.0;
        renderable_desc.lods[0].screen_percentage_range[1] = 30000.0;
        prefab_mgr.rctx.registerRenderable(brazier_2_id, renderable_desc);

        const entity = prefab_mgr.createRenderablePrefab(brazier_2_id, ecsu_world);
        var renderable = entity.getMut(fd.Renderable).?;
        renderable.id = brazier_2_id;
        renderable.draw_bounds = true;

        // TEMP: Lantern light
        const light_ent = ecsu_world.newEntity();
        light_ent.childOf(entity);
        light_ent.set(fd.Position{ .x = 0, .y = 2, .z = 0 });
        light_ent.set(fd.Rotation{});
        light_ent.set(fd.Scale.createScalar(1));
        light_ent.set(fd.Transform{});
        light_ent.set(fd.Dynamic{});

        light_ent.set(fd.PointLight{
            .color = .{ .r = 1.0, .g = 0.8, .b = 0.6 },
            .range = 10,
            .intensity = 5,
        });
    }
}
