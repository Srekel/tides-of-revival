const std = @import("std");
const math = std.math;
const zignav = @import("zignav");
const Recast = zignav.Recast;
const DetourNavMesh = zignav.DetourNavMesh;
const DetourNavMeshBuilder = zignav.DetourNavMeshBuilder;
const DetourNavMeshQuery = zignav.DetourNavMeshQuery;
const DetourStatus = zignav.DetourStatus;

// For more on all this, see here:
// https://recastnav.com/md_Docs__1_Introducation.html

pub const GameConfig = struct {
    character_height: f32 = 2.0,
    character_radius: f32 = 0.4,
    max_step_climb: f32 = 0.2,
    tile_size: i32 = 48, // from sample
    offset: [3]f32 = .{ 0, 0, 0 },
    indoors: bool,
};

pub fn generateConfig(game_config: GameConfig) Recast.rcConfig {
    // Standard values as suggested by docs
    const cell_precision: f32 = if (game_config.indoors) 3.0 else 2.0;
    const cell_size_xz = game_config.character_radius / cell_precision;
    const cell_size_y = cell_size_xz * 0.5;
    const walkable_climb: i32 = @intFromFloat(math.ceil(game_config.max_step_climb / cell_size_y));
    const walkable_height: i32 = @intFromFloat(math.ceil(game_config.character_height / cell_size_y));
    const walkable_radius: i32 = @intFromFloat(math.ceil(game_config.character_radius / cell_size_xz));
    const max_edge_len = walkable_radius * 8;
    const tile_size = game_config.tile_size;
    const border_size = walkable_radius + 3; // from sample
    const padding = cell_size_xz * @as(f32, @floatFromInt(border_size));

    var config: Recast.rcConfig = .{
        .width = tile_size + border_size * 2, // from sample
        .height = tile_size + border_size * 2, // from sample
        .tileSize = tile_size,
        .borderSize = border_size,
        .cs = cell_size_xz,
        .ch = cell_size_y,
        .bmin = .{
            game_config.offset[0] - padding,
            0, // padding?
            game_config.offset[2] - padding,
        },
        .bmax = .{
            @as(f32, @floatFromInt(tile_size)) + game_config.offset[0] + padding,
            10000, // padding?
            @as(f32, @floatFromInt(tile_size)) + game_config.offset[2] + padding,
        },
        .walkableSlopeAngle = 45,
        .walkableHeight = walkable_height,
        .walkableClimb = walkable_climb,
        .walkableRadius = walkable_radius,
        .maxEdgeLen = max_edge_len,
        .maxSimplificationError = 1.3,
        .minRegionArea = 8, // taken from other recast samples
        .mergeRegionArea = 20, // taken from other recast samples
        .maxVertsPerPoly = 6, // taken from other recast samples
        .detailSampleDist = 6, // taken from other recast samples
        .detailSampleMaxError = 1, // taken from other recast samples
    };

    Recast.rcCalcGridSize(&config.bmin, &config.bmax, config.cs, &config.width, &config.height);

    return config;
}

pub fn rasterizePolygonSoup(
    config: Recast.rcConfig,
    nav_ctx: *Recast.rcContext,
    heightfield: *Recast.rcHeightfield,
    vertices: []const f32,
    triangles: []const i32,
) !void {
    if (!Recast.rcCreateHeightfield(
        nav_ctx,
        heightfield,
        config.width,
        config.height,
        &config.bmin,
        &config.bmax,
        config.cs,
        config.ch,
    )) {
        return;
    }

    const vertices_count = vertices.len / 3;
    const triangle_count = triangles.len / 3;

    const allocator = std.heap.page_allocator;
    var triangle_areas = std.ArrayList(u8).init(allocator);
    triangle_areas.appendNTimes(0, triangle_count) catch unreachable;

    Recast.rcMarkWalkableTriangles(
        nav_ctx,
        config.walkableSlopeAngle,
        vertices.ptr,
        @intCast(vertices_count),
        triangles.ptr,
        @intCast(triangle_count),
        triangle_areas.items.ptr,
    );

    if (!Recast.rcRasterizeTriangles(
        nav_ctx,
        vertices.ptr,
        @intCast(vertices_count),
        triangles.ptr,
        triangle_areas.items.ptr,
        @intCast(triangle_count),
        heightfield,
        .{},
    )) {
        return;
    }

    //
    // Step 3. Filter walkable surfaces.
    //

    Recast.rcFilterLowHangingWalkableObstacles(nav_ctx, config.walkableClimb, heightfield);
    Recast.rcFilterLedgeSpans(nav_ctx, config.walkableHeight, config.walkableClimb, heightfield);
    Recast.rcFilterWalkableLowHeightSpans(nav_ctx, config.walkableHeight, heightfield);
}

pub fn partitionWalkableSurfaceToRegions(
    config: Recast.rcConfig,
    nav_ctx: *Recast.rcContext,
    heightfield: *Recast.rcHeightfield,
    compact_heightfield: *Recast.rcCompactHeightfield,
) !void {
    if (!Recast.rcBuildCompactHeightfield(
        nav_ctx,
        config.walkableHeight,
        config.walkableClimb,
        heightfield,
        compact_heightfield,
    )) {
        return error.CouldNotBuildCompactHeightField;
    }

    if (!Recast.rcErodeWalkableArea(nav_ctx, config.walkableRadius, compact_heightfield)) {
        return error.CouldNotErodeWalkableArea;
    }

    // rcMarkConvexPolyArea(m_ctx, vols[i].verts, vols[i].nverts, vols[i].hmin, vols[i].hmax, (unsigned char)vols[i].area, *m_chf);

    const PartitionType = enum {
        watershed,
        monotone,
        layer,
    };
    const partition_type: PartitionType = .watershed;

    switch (partition_type) {
        .watershed => {
            if (!Recast.rcBuildDistanceField(nav_ctx, compact_heightfield)) {
                return;
            }

            // Partition the walkable surface into simple regions without holes.
            if (!Recast.rcBuildRegions(nav_ctx, compact_heightfield, 0, config.minRegionArea, config.mergeRegionArea)) {
                return;
            }
        },
        else => unreachable,
    }
}

pub fn buildPolygonMesh(
    config: Recast.rcConfig,
    nav_ctx: *Recast.rcContext,
    contour_set: *Recast.rcContourSet,
    compact_heightfield: *Recast.rcCompactHeightfield,
    poly_mesh: *Recast.rcPolyMesh,
    poly_mesh_detail: *Recast.rcPolyMeshDetail,
) !void {

    // Build polygon navmesh from the contours.
    if (!Recast.rcBuildPolyMesh(nav_ctx, contour_set, config.maxVertsPerPoly, poly_mesh)) {
        // nav_ctx.log(RC_LOG_ERROR, "buildNavigation: Could not triangulate contours.");
        return error.BuildPolyMesh;
    }

    //
    // Step 7. Create detail mesh which allows to access approximate height on each polygon.
    //

    if (!Recast.rcBuildPolyMeshDetail(
        nav_ctx,
        poly_mesh,
        compact_heightfield,
        config.detailSampleDist,
        config.detailSampleMaxError,
        poly_mesh_detail,
    )) {
        // nav_ctx.log(RC_LOG_ERROR, "buildNavigation: Could not build detail mesh.");
        return error.BuildPolyMeshDetail;
    }
}

pub fn buildFullNavMesh(
    config: Recast.rcConfig,
    nav_ctx: *Recast.rcContext,
    vertices: []const f32,
    triangles: []const i32,
    heightfield: *Recast.rcHeightfield,
    compact_heightfield: *Recast.rcCompactHeightfield,
    contour_set: *Recast.rcContourSet,
    poly_mesh: *Recast.rcPolyMesh,
    poly_mesh_detail: *Recast.rcPolyMeshDetail,
) !void {
    try rasterizePolygonSoup(config, nav_ctx, heightfield, vertices, triangles);

    try partitionWalkableSurfaceToRegions(config, nav_ctx, heightfield, compact_heightfield);

    if (!Recast.rcBuildContours(
        nav_ctx,
        compact_heightfield,
        config.maxSimplificationError,
        config.maxEdgeLen,
        contour_set,
        .{},
    )) {
        // nav_ctx.log(RC_LOG_ERROR, "buildNavigation: Could not create contours.");
        return error.BuildContours;
    }

    try buildPolygonMesh(
        config,
        nav_ctx,
        contour_set,
        compact_heightfield,
        poly_mesh,
        poly_mesh_detail,
    );
}

// Detour / Pathfinding

pub fn initNavMeshFromPolyMesh(
    poly_mesh: [*c]const Recast.rcPolyMesh,
    poly_mesh_detail: [*c]const Recast.rcPolyMeshDetail,
    config: Recast.rcConfig,
    nav_mesh: [*c]DetourNavMesh.dtNavMesh,
) !void {
    const nav_tile = try createTileFromPolyMesh(
        poly_mesh,
        poly_mesh_detail,
        config,
        0,
        0,
    );

    const status = nav_mesh.*.init__Overload3(nav_tile.data, nav_tile.data_size, DetourNavMesh.dtTileFlags.DT_TILE_FREE_DATA.bits);
    if (DetourStatus.dtStatusFailed(status)) {
        return error.FailedNavMeshInit;
    }
}

pub fn createTileFromPolyMesh(
    poly_mesh: [*c]const Recast.rcPolyMesh,
    poly_mesh_detail: [*c]const Recast.rcPolyMeshDetail,
    config: Recast.rcConfig,
    tile_x: c_int,
    tile_y: c_int,
) !struct { data: [*c]u8, data_size: c_int } {
    var nav_mesh_params: DetourNavMeshBuilder.dtNavMeshCreateParams = .{
        .verts = poly_mesh.*.verts,
        .vertCount = poly_mesh.*.nverts,
        .polys = poly_mesh.*.polys,
        .polyAreas = poly_mesh.*.areas,
        .polyFlags = poly_mesh.*.flags,
        .polyCount = poly_mesh.*.npolys,
        .nvp = poly_mesh.*.nvp,
        .detailMeshes = poly_mesh_detail.*.meshes,
        .detailVerts = poly_mesh_detail.*.verts,
        .detailVertsCount = poly_mesh_detail.*.nverts,
        .detailTris = poly_mesh_detail.*.tris,
        .detailTriCount = poly_mesh_detail.*.ntris,
        .offMeshConVerts = undefined,
        .offMeshConRad = undefined,
        .offMeshConDir = undefined,
        .offMeshConAreas = undefined,
        .offMeshConFlags = undefined,
        .offMeshConUserID = undefined,
        .offMeshConCount = 0,
        .walkableHeight = @floatFromInt(config.walkableHeight),
        .walkableRadius = @floatFromInt(config.walkableRadius),
        .walkableClimb = @floatFromInt(config.walkableClimb),
        .cs = config.cs,
        .ch = config.ch,
        .buildBvTree = true,
        .userId = 0,
        .tileX = tile_x,
        .tileY = tile_y,
        .tileLayer = 0,
        .bmin = config.bmin,
        .bmax = config.bmax,
    };

    var nav_data: [*c]u8 = null;
    var nav_data_size: c_int = 0;
    if (!DetourNavMeshBuilder.dtCreateNavMeshData(&nav_mesh_params, &nav_data, &nav_data_size)) {
        return error.FailedBuildingDetourMesh;
    }

    return .{
        .data = nav_data,
        .data_size = nav_data_size,
    };
}

pub const Path = struct {
    start_poly: DetourNavMesh.dtPolyRef = undefined,
    start_pos: [3]f32 = undefined,
    end_poly: DetourNavMesh.dtPolyRef = undefined,
    end_pos: [3]f32 = undefined,
    poly_buffer: []DetourNavMesh.dtPolyRef,
    path_length: c_int = 0,
};

pub fn findPath(
    query: [*c]const DetourNavMeshQuery.dtNavMeshQuery,
    start: [*c]const f32,
    end: [*c]const f32,
    half_extents: [*c]const f32,
    filter: [*c]const DetourNavMeshQuery.dtQueryFilter,
    path: *Path,
) !void {
    var status = query.*.findNearestPoly(start, half_extents, filter, &path.start_poly, &path.start_pos);

    if (DetourStatus.dtStatusFailed(status)) {
        return error.FailedNavQueryPoly;
    }
    if (path.start_poly == 0) {
        return error.FailedNavQueryPolyZero;
    }

    status = query.*.findNearestPoly(end, half_extents, filter, &path.end_poly, &path.end_pos);

    if (DetourStatus.dtStatusFailed(status)) {
        return error.FailedNavQueryPoly;
    }
    if (path.end_poly == 0) {
        return error.FailedNavQueryPolyZero;
    }

    status = query.*.findPath(
        path.start_poly,
        path.end_poly,
        &path.start_pos,
        &path.end_pos,
        filter,
        path.poly_buffer.ptr,
        &path.path_length,
        @intCast(path.poly_buffer.len),
    );
    if (DetourStatus.dtStatusFailed(status)) {
        return error.FailedNavQueryPath;
    }
}
