const std = @import("std");
const math = std.math;
const types = @import("../types.zig");
const grid = @import("../grid.zig");
const zm = @import("zmath");
const znoise = @import("znoise");
const nodes = @import("nodes.zig");

const io = @import("../io.zig");
const loadFile = io.loadFile;
const writeFile = io.writeFile;
const hash = io.hash;
const print = io.print;
const write = io.write;
const writeLine = io.writeLine;
const writeEmptyLine = io.writeEmptyLine;

const Prop = struct {
    name: []const u8,
    pos: [3]f32,
    rot: f32,
    scale: ?[3]f32 = null,
    level: i32,
};

pub fn writeVillageScript(props: *std.ArrayList(Prop), name: []const u8, rand: *const std.Random) void {
    _ = rand; // autofix
    var folderbuf: [256]u8 = undefined;
    var namebuf: [256]u8 = undefined;

    const folderbufslice = std.fmt.bufPrintZ(
        folderbuf[0..folderbuf.len],
        "../../../../content/settlements",
        .{},
    ) catch unreachable;

    std.fs.cwd().makeDir(folderbufslice) catch {};

    var output_file_data = std.ArrayList(u8).initCapacity(std.heap.c_allocator, @sizeOf(Prop) * 1024) catch unreachable;
    defer output_file_data.deinit();
    const writer = output_file_data.writer();

    writeLine(writer, "using flecs.meta", .{});

    for (0..3) |settlement_level| {
        writeEmptyLine(writer);
        writeLine(writer, "if $settlement_level == {d} {{    ", .{settlement_level});
        for (props.items, 0..) |prop, prop_i| {
            if (prop.level != settlement_level) {
                continue;
            }
            const pos = prop.pos;
            const rot_y = prop.rot;
            const rot = zm.quatFromRollPitchYaw(0, rot_y, 0);
            writeLine(writer, "    {s}_prop{d} : {s} {{", .{ name, prop_i, prop.name });
            writeLine(writer, "        config.flecs_data.Position: {{{d}, {d}, {d}}};", .{ pos[0], pos[1], pos[2] });
            writeLine(writer, "        config.flecs_data.Rotation: {{{d}, {d}, {d}, {d}}};", .{ rot[0], rot[1], rot[2], rot[3] });
            writeLine(writer, "        config.flecs_data.Dynamic: {{}};", .{}); // hack temp
            if (prop.scale) |scale| {
                writeLine(writer, "        config.flecs_data.Scale: {{{d},{d},{d}}};", .{ scale[0], scale[1], scale[2] }); // hack temp
            }

            // player_camera_ent.set(fd.PointLight{
            //     .color = .{ .r = 1, .g = 0.95, .b = 0.75 },
            //     .range = 5.0,
            //     .intensity = 1.0,
            // });
            writeLine(writer, "     }};", .{});
            writeEmptyLine(writer);
        }
        writeLine(writer, "}} // end settlement_level {d}", .{settlement_level});
    }

    const namebufslice = std.fmt.bufPrintZ(
        namebuf[0..namebuf.len],
        "{s}/{s}.flecs",
        .{ folderbufslice, name },
    ) catch unreachable;
    const file = std.fs.cwd().createFile(namebufslice, .{ .read = true }) catch unreachable;
    defer file.close();
    _ = file.writeAll(output_file_data.items) catch unreachable;
}

const PathResult = struct {
    pos: [2]f32,
};

const PathNode = struct {
    pos: [2]f32,
    angle: f32,
    pub fn hash(self: PathNode) u64 {
        const grid_size = 16;
        const pos_x: u64 = @intFromFloat(self.pos[0] / grid_size);
        const pos_z: u64 = @intFromFloat(self.pos[1] / grid_size);
        const angle_to_segment: f32 = (1.0 / math.tau) * 8.0;
        var self_angle_positive = self.angle;
        while (self_angle_positive < 0) {
            self_angle_positive += math.tau;
        }
        const angle: u64 = @intFromFloat(self_angle_positive * angle_to_segment);
        return pos_x + pos_z * (16000 / grid_size) + angle * 10_000_000;
    }
    pub fn distManhattan(self: PathNode, pos: [2]f32) f32 {
        return @abs(self.pos[0] - pos[0]) + @abs(self.pos[1] - pos[1]);
    }
    pub fn dist(self: PathNode, pos: [2]f32) f32 {
        const x = self.pos[0] - pos[0];
        const z = self.pos[1] - pos[1];
        return @sqrt(x * x + z * z);
    }
};

const AStarContext = struct {
    allocator: std.mem.Allocator,
    path: *std.ArrayList(PathNode),
    heightmap: types.ImageF32,
    gradient: types.ImageF32,
};

fn pathCostHeuristic(pos: [2]f32, target: [2]f32) f32 {
    const x = pos[0] - target[0];
    const z = pos[1] - target[1];
    return @sqrt(x * x + z * z);
}

fn doAStar(start: PathNode, target: PathNode, ctx: AStarContext) void {
    var all_nodes = std.ArrayListUnmanaged(PathNode).initCapacity(ctx.allocator, 1024 * 1024 * 16) catch unreachable;
    var came_from = std.ArrayListUnmanaged(u32).initCapacity(ctx.allocator, 1024 * 1024 * 16) catch unreachable;
    came_from.appendNTimesAssumeCapacity(math.maxInt(u32), came_from.capacity);

    var hash_to_index: std.AutoHashMapUnmanaged(u64, u32) = .empty;
    defer hash_to_index.deinit(ctx.allocator);
    hash_to_index.ensureTotalCapacity(ctx.allocator, 1024 * 1024 * 16) catch unreachable;

    // gScore
    var known_costs = std.ArrayListUnmanaged(f32).initCapacity(ctx.allocator, 1024 * 1024 * 16) catch unreachable;
    known_costs.appendNTimesAssumeCapacity(math.floatMax(f32), known_costs.capacity);
    // fScore
    var open_costs = std.ArrayListUnmanaged(f32).initCapacity(ctx.allocator, 1024 * 1024 * 16) catch unreachable;
    open_costs.appendNTimesAssumeCapacity(math.floatMax(f32), open_costs.capacity);

    var open_set = std.ArrayListUnmanaged(u32).initCapacity(ctx.allocator, 1024 * 1024 * 16) catch unreachable;

    all_nodes.appendAssumeCapacity(start);
    hash_to_index.putAssumeCapacity(start.hash(), 0);
    known_costs.items[0] = 0;
    open_costs.items[0] = pathCostHeuristic(start.pos, target.pos);
    open_set.appendAssumeCapacity(0);

    while (open_set.items.len > 0) {
        var best_cost = math.floatMax(f32);
        var best_open_index: u64 = 0;
        for (open_set.items, 0..) |opennode, i_node| {
            if (open_costs.items[opennode] < best_cost) {
                best_cost = open_costs.items[opennode];
                best_open_index = i_node;
            }
        }

        const best_index = open_set.items[best_open_index];
        _ = open_set.swapRemove(best_open_index);

        const node = all_nodes.items[best_index];
        const dist = node.dist(target.pos);
        if (dist < 100) {
            std.log.info("Pathfinding close {d}", .{best_index});
            var next = best_index;
            while (next != std.math.maxInt(u32)) {
                std.log.info("Pathfinding next {d}", .{next});
                ctx.path.appendAssumeCapacity(all_nodes.items[next]);
                next = came_from.items[next];
            }
            return;
        }

        std.log.info("Pathfinding {d}/{d} cost:{d} pos:{d},{d} dist:{d}", .{ best_index, all_nodes.items.len, best_cost, node.pos[0], node.pos[1], dist });
        const cost_current = known_costs.items[best_index];

        const dist_points = 50;
        const angle_fwd = node.angle;
        const pos_curr = node.pos;
        const height = ctx.heightmap.getFromFloat(pos_curr[0], pos_curr[1]);
        const angle_offset: f32 = math.degreesToRadians(20);
        for (0..3) |i_angle| {
            const angle_next = angle_fwd + (@as(f32, @floatFromInt(i_angle)) - 1) * angle_offset;
            const dir_next = .{ math.cos(angle_next), math.sin(angle_next) };
            const pos_next = .{ pos_curr[0] + dir_next[0] * dist_points, pos_curr[1] + dir_next[1] * dist_points };
            const height_next = ctx.heightmap.getFromFloat(pos_next[0], pos_next[1]);
            const cost_height = 1 + @abs(height - height_next) * 0.1;

            const cost = dist_points * cost_height;
            const tentative_cost = cost_current + cost;

            if (height_next < 20) {
                continue;
            }

            const node_next: PathNode = .{
                .pos = pos_next,
                .angle = angle_next,
            };
            const hash_next = node_next.hash();

            const index_next_opt = hash_to_index.get(hash_next);

            if (index_next_opt) |index_next| {
                const known_cost = known_costs.items[index_next];
                if (known_cost <= tentative_cost) {
                    // This node was already tested in a better way, don't re-test it
                    continue;
                }

                // We've already tried this node but found a better approach to it
                known_costs.items[index_next] = tentative_cost;
            } else {
                all_nodes.appendAssumeCapacity(node_next);
                hash_to_index.putAssumeCapacity(hash_next, @intCast(all_nodes.items.len - 1));
            }

            const index_next = hash_to_index.get(hash_next).?;
            came_from.items[index_next] = best_index;
            known_costs.items[index_next] = tentative_cost;
            open_costs.items[index_next] = tentative_cost + pathCostHeuristic(pos_next, target.pos);
            open_set.appendAssumeCapacity(index_next);
        }
    }
}

pub fn cities(world_settings: types.WorldSettings, heightmap: types.ImageF32, gradient: types.ImageF32, city_points: *const types.BackedListVec2, cities_out: *std.ArrayList([3]f32)) void {
    _ = world_settings; // autofix

    // var buf: [512 * 1024]u8 = undefined;
    // const template = loadTemplate("../../../content/flecs_script/templates/village_small_poor.template.flecs", buf);

    // temp via https://www.fantasynamegenerators.com/fantasy-town-names.php
    const names = [_][]const u8{
        "Rockpond",
        "Losttide",
        "Autumnfront",
        "Wolfvale",
        "Eagleglen",
        "Mudsummit",
        "Glimmerside",
        "Thornward",
        "Quickbreak",
        "Dryvein",
        "Ravenfrost",
        "Smallmoor",
        "Dimbreach",
        "Arrowland",
        "Chillacre",
        "Silvercoast",
        "Rockburn",
        "Crystalfair",
        "Basinwell",
        "Duskborough",
    };

    const seed: u64 = 123;
    const cell_size_f: f32 = 25;
    const radius = 2.5 * cell_size_f;
    const radius_palisades = 3.2 * cell_size_f;
    const perimeter = radius_palisades * math.pi * 2;

    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    var props = std.ArrayList(Prop).initCapacity(std.heap.c_allocator, 1024 * 4) catch unreachable;

    var valid_settlement_i: u32 = 0;
    for (city_points.backed_slice[0..city_points.count], 0..) |pt, i_city| {
        props.clearRetainingCapacity();

        const x = pt[0];
        const z = pt[1];

        const settlement_height = heightmap.get(@as(u32, @intFromFloat(x)), @as(u32, @intFromFloat(z)));
        if (settlement_height < 60) {
            continue; // hack for sea level
        }
        if (settlement_height > 250) {
            continue; // hack for mountains
        }

        // Internal props
        for (0..5) |offset_z| {
            const cutoff_z: f32 = if (offset_z == 0 or offset_z == 4) 0.7 else 1;
            for (0..5) |offset_x| {
                const cutoff_x: f32 = if (offset_x == 0 or offset_x == 4) 0.7 else 1;
                if ((offset_x == 0 or offset_x == 4) and (offset_z == 0 or offset_z == 4)) {
                    continue; // roundify village
                }
                if (offset_x == 2 and offset_z == 2) {
                    // Hack for "well"
                    continue;
                }
                const final_x = x + @as(f32, @floatFromInt(offset_x)) * cell_size_f + rand.float(f32) * cell_size_f * 0.3 - radius;
                const final_z = z + @as(f32, @floatFromInt(offset_z)) * cell_size_f + rand.float(f32) * cell_size_f * 0.3 - radius;
                const house_height = heightmap.get(@as(u32, @intFromFloat(final_x)), @as(u32, @intFromFloat(final_z)));
                if (house_height < 40) {
                    continue; // hack for sea level
                }

                const name = if (rand.float(f32) * cutoff_x * cutoff_z > 0.3)
                    "house_3x5_id"
                else
                    "brazier_2_id";

                props.appendAssumeCapacity(.{
                    .name = name,
                    .pos = .{ final_x, house_height, final_z },
                    .rot = rand.float(f32) * std.math.tau,
                    .level = 1,
                });
            }
        }

        // Palisades
        const palisade_length = 4;
        const palisade_count = math.ceil(perimeter / palisade_length);
        for (0..palisade_count) |i_palisade| {
            const percent = @as(f32, @floatFromInt(i_palisade)) / palisade_count;
            const angle_rad = percent * math.tau;
            const is_palisade = i_palisade < palisade_count - 3;
            var pos = [3]f32{
                x + math.cos(angle_rad) * radius_palisades,
                0,
                z + math.sin(angle_rad) * radius_palisades,
            };

            pos[1] = heightmap.get(@as(u32, @intFromFloat(pos[0])), @as(u32, @intFromFloat(pos[2])));
            if (pos[1] < 30) {
                continue; // hack for sea level
            }

            const name = switch (is_palisade) {
                true => if (rand.boolean()) "palisade_400x300_a_id" else "palisade_400x300_b_id",
                else => "brazier_1_id",
            };

            props.appendAssumeCapacity(.{
                .name = name,
                .pos = pos,
                .rot = -angle_rad + math.pi * 0.5,
                .level = 1,
            });
        }

        // Roads

        std.log.info("Pathfinding!", .{});
        for (city_points.backed_slice[i_city + 1 .. city_points.count]) |pt2| {
            const settlement_height2 = heightmap.get(@as(u32, @intFromFloat(pt2[0])), @as(u32, @intFromFloat(pt2[1])));
            if (settlement_height2 < 60) {
                continue; // hack for sea level
            }
            if (settlement_height2 > 250) {
                continue; // hack for mountains
            }

            var path_nodes = std.ArrayList(PathNode).initCapacity(std.heap.c_allocator, 1024 * 1024) catch unreachable;
            defer path_nodes.deinit();

            std.log.info("Pathfinding...", .{});
            doAStar(
                .{ .pos = pt, .angle = 0 },
                .{ .pos = pt2, .angle = 0 },
                .{
                    .path = &path_nodes,
                    .allocator = std.heap.c_allocator,
                    .gradient = gradient,
                    .heightmap = heightmap,
                },
            );
            std.log.info("Pathfinding done! {d}", .{path_nodes.items.len});

            for (path_nodes.items) |node| {
                if (rand.float(f32) > 0.5) {
                    continue;
                }
                const pos = [_]f32{
                    node.pos[0],
                    heightmap.getFromFloat(node.pos[0], node.pos[1]),
                    node.pos[1],
                };
                props.appendAssumeCapacity(.{
                    .name = "stacked_stones",
                    .pos = pos,
                    .rot = node.angle,
                    // .scale = .{ 2, 3, 2 },
                    .level = 1,
                });
            }

            break; // hack for having a reasonable amount of roads..
        }

        cities_out.appendAssumeCapacity(.{ x, settlement_height, z });

        writeVillageScript(&props, names[valid_settlement_i], &rand);
        valid_settlement_i += 1;
    }

    var folderbuf: [256]u8 = undefined;
    var namebuf: [256]u8 = undefined;

    const folderbufslice = std.fmt.bufPrintZ(
        folderbuf[0..folderbuf.len],
        "../../../../content/systems",
        .{},
    ) catch unreachable;

    std.fs.cwd().makeDir(folderbufslice) catch {};

    var output_file_data = std.ArrayList(u8).initCapacity(std.heap.c_allocator, cities_out.items.len * 500) catch unreachable;
    defer output_file_data.deinit();
    var writer = output_file_data.writer();

    for (cities_out.items, 0..) |city, settlement_i| {
        writer.print("city,{d:.3},{d:.3},{d:.3},{s}\n", .{ city[0], city[1], city[2], names[settlement_i] }) catch unreachable;
    }

    const namebufslice = std.fmt.bufPrintZ(
        namebuf[0..namebuf.len],
        "{s}/cities.txt",
        .{
            folderbufslice,
        },
    ) catch unreachable;
    const file = std.fs.cwd().createFile(namebufslice, .{ .read = true }) catch unreachable;
    defer file.close();
    _ = file.writeAll(output_file_data.items) catch unreachable;
}

pub fn points_distribution_grid(filter: types.ImageF32, score_min: f32, grid_settings: grid.Grid, pts_out: *types.PatchDataPts2d) void {
    const cells_x = grid_settings.size.width / grid_settings.cell_size;
    const cells_y = grid_settings.size.height / grid_settings.cell_size;
    const seed: u64 = 123;
    // std.posix.getrandom(std.mem.asBytes(&seed)) catch unreachable;

    const cell_size_f: f32 = @as(f32, @floatFromInt(grid_settings.cell_size));
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    for (0..cells_y) |y| {
        const filter_y = filter.size.height * y / cells_y;
        const patch_y = pts_out.size.height * y / cells_y;
        for (0..cells_x) |x| {
            const filter_x = filter.size.width * x / cells_x;
            const val = filter.get(filter_x, filter_y);
            if (val < score_min) {
                continue;
            }

            const pt_x: f32 = @as(f32, @floatFromInt(filter_x)) + rand.float(f32) * cell_size_f * 0.95;
            const pt_y: f32 = @as(f32, @floatFromInt(filter_y)) + rand.float(f32) * cell_size_f * 0.95;
            const patch_x = pts_out.size.width * x / cells_x;
            pts_out.addToPatch(patch_x, patch_y, .{ pt_x, pt_y });
        }
    }
}

pub fn write_trees(heightmap: types.ImageF32, points: types.PatchDataPts2d) void {
    var folderbuf: [256]u8 = undefined;
    var namebuf: [256]u8 = undefined;

    const PROPS_LOD = 1;
    _ = PROPS_LOD; // autofix

    const folderbufslice = std.fmt.bufPrintZ(
        folderbuf[0..folderbuf.len],
        "../../../../content/patch/props/lod{}",
        .{points.lod},
    ) catch unreachable;

    std.fs.cwd().makeDir(folderbufslice) catch {};

    for (0..points.size.height) |patch_z| {
        for (0..points.size.width) |patch_x| {
            const namebufslice = std.fmt.bufPrintZ(
                namebuf[0..namebuf.len],
                "{s}/props_x{}_z{}.txt",
                .{
                    folderbufslice,
                    patch_x,
                    patch_z,
                },
            ) catch unreachable;

            const props = points.getPatch(patch_x, patch_z);
            if (props.len == 0) {
                std.fs.cwd().deleteFile(namebufslice) catch {};
                continue;
            }

            var output_file_data = std.ArrayList(u8).initCapacity(std.heap.c_allocator, props.len * 50) catch unreachable;
            var writer = output_file_data.writer();

            for (props) |prop| {
                // city,1072.000,145.403,1152.000,43
                const height = heightmap.get(
                    @as(u64, @intFromFloat(@trunc(prop[0]))),
                    @as(u64, @intFromFloat(@trunc(prop[1]))),
                );
                if (height < 150) {
                    continue; // HACK
                }

                const rot = 0;
                writer.print("tree,{d:.3},{d:.3},{d:.3},{}\n", .{ prop[0], height, prop[1], rot }) catch unreachable;
            }

            const file = std.fs.cwd().createFile(namebufslice, .{ .read = true }) catch unreachable;
            defer file.close();
            _ = file.writeAll(output_file_data.items) catch unreachable;
        }
    }
}

// pub fn voronoi_to_water(voronoi_image: types.ImageRGBA, water_image: *types.ImageF32) void {
pub fn voronoi_to_water(voronoi_image: []u8, water_image: *types.ImageF32) void {
    for (0..water_image.size.height) |y| {
        for (0..water_image.size.width) |x| {
            const voronoi_index_r = (x + y * water_image.size.width) * 4;
            _ = voronoi_index_r; // autofix
            const voronoi_index_g = (x + y * water_image.size.width) * 4 + 1;
            if (voronoi_image[voronoi_index_g] == 255) {
                // PLAINS
                water_image.set(x, y, 0.5);
            } else if (voronoi_image[voronoi_index_g] == 0) {
                // WATER
                water_image.set(x, y, 0.2);
            } else if (voronoi_image[voronoi_index_g] == 127) {
                // HILLS
                water_image.set(x, y, 1);
            }
        }
    }
}

pub fn water(water_image: types.ImageF32, heightmap: *types.ImageF32) void {
    for (0..water_image.size.height) |y| {
        for (0..water_image.size.width) |x| {
            const height_curr = heightmap.get(x, y);
            const water_curr = water_image.get(x, y);
            heightmap.set(x, y, height_curr * water_curr);
        }
    }
}
