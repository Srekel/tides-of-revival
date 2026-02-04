const std = @import("std");
const renderer = @import("renderer/renderer.zig");
const window = @import("renderer/window.zig");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util/flecs_util.zig");
const fd = @import("config/flecs_data.zig");
const input = @import("input.zig");
const config = @import("config/config.zig");

const logo_size: f32 = 100;
const logo_margin: f32 = 20;

const TextLine = struct {
    text: [:0]const u8 = "",
    size: f32 = 0,
    anchor_x: f32 = 0,
    anchor_y: f32 = 0,
    line_height: f32 = 1.25,
};

const Text = struct {
    color_start: [4]f32 = [4]f32{ 163.0 / 255.0, 112.0 / 255.0, 58.0 / 255.0, 0.0 },
    color_end: [4]f32 = [4]f32{ 229.0 / 255.0, 207.0 / 255.0, 121.0 / 255.0, 1.0 },
    shadow_color: [4]f32 = [4]f32{ 0, 0, 0, 0.0 },
    shadow_blur: f32 = 14,
    lines: []const TextLine,
    size: f32 = 0,
};

const UI = struct {
    logo_ent: ecsu.Entity = .{},

    intro_ent: ecsu.Entity = .{},
    intro_text_ents: [intro.lines.len]ecsu.Entity = [_]ecsu.Entity{.{}} ** intro.lines.len,

    outro_ent: ecsu.Entity = .{},
    outro_text_ents: [outro.lines.len]ecsu.Entity = [_]ecsu.Entity{.{}} ** outro.lines.len,

    main_window: *window.Window = undefined,
    ecsu_world: ecsu.World = undefined,
    renderer_ctx: *renderer.Renderer = undefined,
};

var self: UI = .{};

fn doText(text: Text, left: f32, bottom_base: f32, entities: []ecsu.Entity) void {
    var bottom = bottom_base;
    var size = text.size;
    for (text.lines, 0..) |line, i| {
        size = if (line.size > 0) line.size else size;
        if (entities[i].id == 0) {
            entities[i] = self.ecsu_world.newEntity();
            entities[i].set(fd.UIText{
                .left = left + line.anchor_x,
                .bottom = bottom,
                .font_size = size,
                .text_color = text.color_start,
                .shadow_color = text.shadow_color,
                .shadow = true,
                .shadow_blur = 0,
                .shadow_offset_x = 0,
                .shadow_offset_y = 0,
                .text = line.text,
            });
        } else {
            var uitext = entities[i].getMut(fd.UIText).?;
            uitext.left = left + line.anchor_x;
            uitext.bottom = bottom;
        }

        bottom += size * line.line_height;
    }
}

const intro: Text = .{
    .lines = &.{
        .{
            .text = "Tides of Revival",
            .size = 72,
            .anchor_x = 50,
        },
        .{
            .text = "Hill 3: A Sense of Scale",
            .size = 42,
            .anchor_x = 90,
            .line_height = 2,
        },
        .{
            .size = 18,
        },
        .{ .text = "Your boat capsized in a storm. Drifting for days, clinging to a chunk of" },
        .{ .text = "wood, you finally make it to a beach. Rescued by a nearby village, you" },
        .{ .text = "have been brought back to life and vigor." },
        .{ .text = "" },
        .{ .text = "You tell them of your past. Your skills. They ask for one favor in return." },
        .{ .text = "" },
        .{ .text = "\"Slay the beast. Track it at night. Hunt during the day.\"" },
        .{ .text = "" },
        .{ .text = "Just as you are about to leave, the village ranger has one last piece of advice." },
        .{ .text = "" },
        .{ .text = "\"Never travel in darkness.\"" },
        .{ .text = "" },
        .{ .text = "" },
        .{
            .text = "[Press Left Mouse Button to start game]",
            .anchor_x = 145,
        },
        .{
            .text = "[You can always press H for instructions]",
            .anchor_x = 140,
        },
    },
};

const outro: Text = .{
    .lines = &.{
        .{
            .text = "Tides of Revival",
            .size = 72,
            .anchor_x = 50,
        },
        .{
            .text = "Hill 3: A Sense of Scale",
            .size = 42,
            .anchor_x = 90,
            .line_height = 2,
        },
        .{
            .size = 18,
        },
        .{ .text = "lol" },
        .{ .text = "u ded" },
    },
};

pub fn init(renderer_ctx: *renderer.Renderer, main_window: *window.Window, ecsu_world: ecsu.World) void {
    self.main_window = main_window;
    self.ecsu_world = ecsu_world;
    self.renderer_ctx = renderer_ctx;

    const window_size_x: f32 = @floatFromInt(main_window.frame_buffer_size[0]);
    const window_size_y: f32 = @floatFromInt(main_window.frame_buffer_size[1]);

    // Watermark Logo
    {
        const logo_texture = renderer_ctx.loadTexture("textures/ui/tides_logo_ui.dds");
        const bottom = @as(f32, @floatFromInt(main_window.frame_buffer_size[1])) - logo_margin - logo_size;
        const left = @as(f32, @floatFromInt(main_window.frame_buffer_size[0])) - logo_margin - logo_size;

        self.logo_ent = ecsu_world.newEntity();
        self.logo_ent.set(fd.UIImage{
            .rect = .{
                .x = left,
                .y = bottom,
                .width = logo_size,
                .height = logo_size,
            },
            .material = .{
                .color = [4]f32{ 1, 1, 1, 1 },
                .texture = logo_texture,
            },
        });
    }

    // Intro
    {
        const texture_handle = renderer_ctx.loadTexture("textures/ui/intro.dds");
        const texture = renderer_ctx.getTexture(texture_handle);
        const width: f32 = @floatFromInt(texture[0].bitfield_1.mWidth);
        const height: f32 = @floatFromInt(texture[0].bitfield_1.mHeight);

        const left = window_size_x / 2 - width / 2;
        const bottom = window_size_y / 2 - height / 2;

        self.intro_ent = ecsu_world.newEntity();
        self.intro_ent.set(fd.UIImage{
            .rect = .{
                .x = left,
                .y = bottom,
                .width = width,
                .height = height,
            },
            .material = .{
                .color = [4]f32{ 1, 1, 1, 0 },
                .texture = texture_handle,
            },
        });

        doText(intro, left + 50, bottom + 50, &self.intro_text_ents);
    }

    // Outro
    {
        const texture_handle = renderer_ctx.loadTexture("textures/ui/intro.dds");
        const texture = renderer_ctx.getTexture(texture_handle);
        const width: f32 = @floatFromInt(texture[0].bitfield_1.mWidth);
        const height: f32 = @floatFromInt(texture[0].bitfield_1.mHeight);

        const left = window_size_x / 2 - width / 2;
        const bottom = window_size_y / 2 - height / 2;

        self.outro_ent = ecsu_world.newEntity();
        self.outro_ent.set(fd.UIImage{
            .rect = .{
                .x = left,
                .y = bottom,
                .width = width,
                .height = height,
            },
            .material = .{
                .color = [4]f32{ 1, 1, 1, 0 },
                .texture = texture_handle,
            },
        });

        doText(outro, left + 50, bottom + 50, &self.outro_text_ents);
    }
}

pub fn deinit() void {}

pub fn update(input_frame_data: *input.FrameData, dt: f32) void {
    var debugself = self;
    debugself.intro_ent = debugself.intro_ent;

    const window_size_x: f32 = @floatFromInt(self.main_window.frame_buffer_size[0]);
    const window_size_y: f32 = @floatFromInt(self.main_window.frame_buffer_size[1]);

    const big_window_texture_handle = self.renderer_ctx.loadTexture("textures/ui/intro.dds");
    const big_window_texture = self.renderer_ctx.getTexture(big_window_texture_handle);
    const big_window_width: f32 = @floatFromInt(big_window_texture[0].bitfield_1.mWidth);
    const big_window_height: f32 = @floatFromInt(big_window_texture[0].bitfield_1.mHeight);
    const big_window_left = window_size_x / 2 - big_window_width / 2;
    const big_window_bottom = window_size_y / 2 - big_window_height / 2;

    // LOGO
    {
        const logo = self.logo_ent.getMut(fd.UIImage).?;
        logo.rect.x = window_size_x - logo_margin - logo_size;
        logo.rect.y = window_size_y - logo_margin - logo_size;
    }

    // Intro
    if (self.intro_text_ents[0].id != 0) {
        const intro_image = self.intro_ent.getMut(fd.UIImage).?;
        intro_image.rect.x = big_window_left;
        intro_image.rect.y = big_window_bottom;
        doText(intro, big_window_left + 50, big_window_bottom + 50, &self.intro_text_ents);

        if (input_frame_data.just_pressed(config.input.wielded_use_primary)) {
            self.ecsu_world.delete(self.intro_ent.id);
            for (self.intro_text_ents) |ent| {
                if (ent.id != 0) {
                    self.ecsu_world.delete(ent.id);
                }
            }
            self.intro_text_ents[0].id = 0;
        } else if (intro_image.material.color[3] < 1) {
            intro_image.material.color[3] = @min(1, intro_image.material.color[3] + dt * 4);
        } else {
            for (self.intro_text_ents) |ent| {
                const text = ent.getMut(fd.UIText).?;
                if (text.shadow_color[3] < 1.0) {
                    text.text_color[3] = 1;
                    text.shadow_color[3] = @min(1, text.shadow_color[3] + dt * 2.5);
                    text.shadow_blur = @min(text.font_size / 5, text.shadow_blur + dt * 20);
                    for (0..3) |i| {
                        text.text_color[i] = std.math.lerp(intro.color_start[i], intro.color_end[i], text.shadow_color[3]);
                    }
                    break;
                }
            }
        }
    }

    // Outro
    const player_ent = ecs.lookup(self.ecsu_world.world, "main_player");
    const player_health = ecs.get(self.ecsu_world.world, player_ent, fd.Health).?;
    // std.log.warn("lol1 {} {}", .{ self.intro_text_ents[0].id, player_health.value });
    if (self.intro_text_ents[0].id == 0 and player_health.value == 0) {
        // if (self.intro_text_ents[0].id == 0) {
        const outro_image = self.outro_ent.getMut(fd.UIImage).?;
        outro_image.rect.x = big_window_left;
        outro_image.rect.y = big_window_bottom;
        doText(outro, big_window_left + 50, big_window_bottom + 50, &self.outro_text_ents);

        // std.log.warn("lol2 {} {}", .{ self.intro_text_ents[0].id, player_health.value });
        const environment_info = self.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
        if (environment_info.active_camera.?.id != environment_info.player_camera.?.id) {
            outro_image.material.color[3] = @max(0, outro_image.material.color[3] - dt * 4);
        } else if (outro_image.material.color[3] < 1) {
            outro_image.material.color[3] = @min(1, outro_image.material.color[3] + dt * 4);
        } else {
            for (self.outro_text_ents) |ent| {
                const text = ent.getMut(fd.UIText).?;
                if (text.shadow_color[3] < 1.0) {
                    text.text_color[3] = 1;
                    text.shadow_color[3] = @min(1, text.shadow_color[3] + dt * 2.5);
                    text.shadow_blur = @min(text.font_size / 5, text.shadow_blur + dt * 20);
                    for (0..3) |i| {
                        text.text_color[i] = std.math.lerp(outro.color_start[i], outro.color_end[i], text.shadow_color[3]);
                    }
                    break;
                }
            }
        }
    }
}
