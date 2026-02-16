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
    new_column: bool = false,
};

const Text = struct {
    color_start: [4]f32 = [4]f32{ 183.0 / 255.0, 132.0 / 255.0, 78.0 / 255.0, 0.0 },
    color_end: [4]f32 = [4]f32{ 249.0 / 255.0, 207.0 / 255.0, 141.0 / 255.0, 1.0 },
    shadow_color: [4]f32 = [4]f32{ 0, 0, 0, 0.0 },
    shadow_blur: f32 = 14,
    lines: []const TextLine,
    size: f32 = 0,
    columns: u32 = 1,
};

const UI = struct {
    logo_ent: ecsu.Entity = .{},
    big_window_texture_handle: renderer.TextureHandle = undefined,
    big_window_ent: ecsu.Entity = .{},

    intro_text_ents: [intro.lines.len]ecsu.Entity = [_]ecsu.Entity{.{}} ** intro.lines.len,
    outro_game_over_text_ents: [outro_game_over.lines.len]ecsu.Entity = [_]ecsu.Entity{.{}} ** outro_game_over.lines.len,
    outro_win_text_ents: [outro_win.lines.len]ecsu.Entity = [_]ecsu.Entity{.{}} ** outro_win.lines.len,
    help_text_ents: [help.lines.len]ecsu.Entity = [_]ecsu.Entity{.{}} ** help.lines.len,
    credits_text_ents: [credits.lines.len]ecsu.Entity = [_]ecsu.Entity{.{}} ** credits.lines.len,
    help2_text_ents: [help2.lines.len]ecsu.Entity = [_]ecsu.Entity{.{}} ** help2.lines.len,

    main_window: *window.Window = undefined,
    ecsu_world: ecsu.World = undefined,
    renderer_ctx: *renderer.Renderer = undefined,
};

var self: UI = .{};

fn doText(text: Text, left_base: f32, bottom_base: f32, entities: []ecsu.Entity) void {
    var column_bottom = bottom_base;
    var bottom = bottom_base;
    var left = left_base;
    var size = text.size;
    var anchor_x: f32 = 0;
    for (text.lines, 0..) |line, i| {
        if (line.anchor_x != 0) {
            anchor_x = if (line.anchor_x == -1) 0 else line.anchor_x;
        }
        if (line.new_column) {
            if (line.size != 0) {
                left = left_base;
                column_bottom = bottom;
            } else {
                left = left_base + 400;
                bottom = column_bottom;
            }
        }
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
            uitext.left = left + anchor_x;
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
            .anchor_x = 120,
        },
        .{
            .text = "Hill 3: A Sense of Scale",
            .size = 42,
            .anchor_x = 70 + 90,
            .line_height = 1.5,
        },
        .{
            .size = 20,
            .anchor_x = -1,
        },
        .{ .text = "Hi! My name is Anders and this is the third iteration, or hill, as we", .anchor_x = 90 },
        .{ .text = "say, of the game we are working on. There's a whole bunch of jank but", .anchor_x = 70 },
        .{ .text = "also some cool things, so I hope you'll like it!", .anchor_x = 180 },
        .{ .text = "" },
        .{
            .text = "--------------------------------------------------------------",
            .anchor_x = 150,
        },
        .{ .text = "", .anchor_x = 50 },
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
        .{
            .text = "[Press Left Mouse Button to start game]",
            .anchor_x = 160,
            .size = 24,
        },
        .{
            .text = "[You can always press H for instructions]",
            .anchor_x = 155,
        },
        .{
            .text = "[Press C for credits]",
            .anchor_x = 265,
        },
    },
};

const outro_game_over: Text = .{
    .lines = &.{
        .{
            .text = "Tides of Revival",
            .size = 72,
            .anchor_x = 120,
        },
        .{
            .text = "Game Over!",
            .size = 42,
            .anchor_x = 70 + 195,
            .line_height = 1.5,
        },
        .{
            .size = 40,
        },
        .{ .text = "" },
        .{
            .text = "You succumed to the beast.",
            .anchor_x = 230,
            .size = 24,
        },
        .{
            .size = 48,
        },
        .{ .text = "" },
        .{ .text = "" },
        .{
            .text = "Restart the game to try again... if you dare!",
            .anchor_x = 140,
            .size = 24,
        },
        .{ .text = "" },
    },
};

const outro_win: Text = .{
    .lines = &.{
        .{
            .text = "Tides of Revival",
            .size = 72,
            .anchor_x = 120,
        },
        .{
            .text = "You won!",
            .size = 42,
            .anchor_x = 70 + 195,
            .line_height = 1.5,
        },
        .{
            .size = 50,
        },
        .{
            .text = "You have slain the beast, and the villages complete their road!",
            .size = 24,
            .anchor_x = 45,
        },
        .{
            .size = 20,
        },
        .{},
        .{
            .text = "--------------------------------------------------------------",
            .anchor_x = 150,
        },
        .{},
        .{ .anchor_x = -1 },
        .{ .text = "So, what's next for Tides of Revival?" },
        .{ .text = "Well, we have lofty goals!" },
        .{ .text = "" },
        .{ .text = "The world you just played in is roughly 16 by 16 km wide." },
        .{ .text = "As a comparison, Skyrim's is 8x8 km. I know, I know, Skyrim's seems bigger! :)." },
        .{ .text = "For Hill 4, we are aiming for a world that's 64x64 km big." },
        .{ .text = "" },
        .{ .text = "To do this we will write a new engine from scratch. In a new language!" },
        .{ .text = "Our goals include supporting really really big worlds, better debugging," },
        .{ .text = "improved performance, modding support, and more. " },
        .{ .text = "" },
        .{ .text = "So, Hill 4 will primarily a tech foundation and demo to show off and build off of." },
        .{ .text = "" },
        .{ .text = "There's more to be said, but the space is limited! Come join us on our journey!" },
    },
};

const help: Text = .{
    .lines = &.{
        .{
            .text = "Tides of Revival",
            .size = 72,
            .anchor_x = 120,
        },
        .{
            .text = "How to play",
            .size = 42,
            .anchor_x = 70 + 195,
            .line_height = 1.5,
        },
        .{
            .size = 20,
            .anchor_x = -1,
        },
        .{ .text = "Look around by moving the mouse." },
        .{ .text = "Press and hold down Left Mouse Button to draw and shoot your bow." },
        .{ .text = "" },
        .{ .text = "Press W, A, S, D to move. " },
        .{ .text = "Hold shift to run." },
        .{ .text = "" },
        .{ .text = "To journey long distances, aim somewhere and when the boot icon" },
        .{ .text = "is white, press F to travel there." },
        .{ .text = "" },
        .{ .text = "To rest, look at the ground. When the fireplace icon" },
        .{ .text = "is white, press R to rest. You will rest here until morning." },
        .{ .text = "" },
        .{ .text = "Tip: Travel to hilltops with a view. Rest there over night and" },
        .{ .text = "look out for mama slime!" },
    },
};

const help2: Text = .{
    .color_start = [4]f32{ 200.0 / 255.0, 200.0 / 255.0, 200.0 / 255.0, 1.0 },
    .color_end = [4]f32{ 0.0 / 255.0, 0.0 / 255.0, 0.0 / 255.0, 1.0 },
    .lines = &.{
        .{
            .text = "Tides of Revival: A Sense of Scale. February 2026.",
            .size = 25,
        },
        .{
            .text = "[H] Help",
        },
        .{
            .text = "[C] Credits",
        },
    },
};

const credits: Text = .{
    .lines = &.{
        .{
            .text = "Tides of Revival",
            .size = 72,
            .anchor_x = 120,
        },
        .{
            .text = "Credits",
            .size = 42,
            .anchor_x = 70 + 195,
            .line_height = 1.5,
        },

        .{ .text = "Project Lead: Anders Elfgren", .new_column = true, .size = 20, .anchor_x = -1 },
        .{ .text = "Gameplay programming: Anders Elfgren" },
        .{ .text = "Graphics programming: Giuseppe Modarelli" },
        .{ .text = "Additional stuff: Alexander Dahl" },
        .{ .text = "Art: Giulia Di Noia", .new_column = true },
        .{ .text = "Art: Anders Elfgren" },
        .{ .text = "Sound effects: River Blue" },
        .{ .text = "Music: Solvej von Malmborg" },
        .{ .text = "" },
        .{ .text = "Additional content", .size = 30, .new_column = true },
        .{ .text = "Google Fonts", .size = 20, .new_column = true },
        .{ .text = "Sonniss" },
        .{ .text = "PMSFX" },
        .{ .text = "Poly Haven" },
        .{ .text = "Nature Manufacture", .new_column = true },
        .{ .text = "Kenney Assets" },
        .{ .text = "Quaternius" },
        .{ .text = "Textures.com" },
        .{ .text = "" },
        .{ .text = "Thanks to", .size = 30, .new_column = true },
        .{ .text = "Jurgita Elfgren for wifing", .size = 20, .new_column = true },
        .{ .text = "Ted and Ben Elfgren for playtesting" },
        .{ .text = "Open World Gamedev", .new_column = true },
        .{ .text = "Jeremy Laumon for Asset Cooker" },
        .{ .text = "" },
        .{ .text = "Production babies", .size = 30, .new_column = true },
        .{ .text = "Martin Elfgren", .size = 20 },
    },
};

pub fn init(renderer_ctx: *renderer.Renderer, main_window: *window.Window, ecsu_world: ecsu.World) void {
    self.main_window = main_window;
    self.ecsu_world = ecsu_world;
    self.renderer_ctx = renderer_ctx;

    const window_size_x: f32 = @floatFromInt(main_window.frame_buffer_size[0]);
    const window_size_y: f32 = @floatFromInt(main_window.frame_buffer_size[1]);

    self.big_window_texture_handle = renderer_ctx.loadTexture("textures/ui/intro.dds");
    const big_window_texture = self.renderer_ctx.getTexture(self.big_window_texture_handle);
    const big_window_width: f32 = @floatFromInt(big_window_texture[0].bitfield_1.mWidth);
    const big_window_height: f32 = @floatFromInt(big_window_texture[0].bitfield_1.mHeight);
    const big_window_left = window_size_x / 2 - big_window_width / 2;
    const big_window_bottom = window_size_y / 2 - big_window_height / 2;

    self.big_window_ent = ecsu_world.newEntity();
    self.big_window_ent.set(fd.UIImage{
        .rect = .{
            .x = big_window_left,
            .y = big_window_bottom,
            .width = big_window_width,
            .height = big_window_height,
        },
        .material = .{
            .color = [4]f32{ 1, 1, 1, 0 },
            .texture = self.big_window_texture_handle,
        },
        .render_order = 10,
    });

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
        const texture = renderer_ctx.getTexture(self.big_window_texture_handle);
        const width: f32 = @floatFromInt(texture[0].bitfield_1.mWidth);
        const height: f32 = @floatFromInt(texture[0].bitfield_1.mHeight);

        const left = window_size_x / 2 - width / 2;
        const bottom = window_size_y / 2 - height / 2;

        doText(intro, left + 120, bottom + 50, &self.intro_text_ents);
    }

    // Outro
    {
        const texture = renderer_ctx.getTexture(self.big_window_texture_handle);
        const width: f32 = @floatFromInt(texture[0].bitfield_1.mWidth);
        const height: f32 = @floatFromInt(texture[0].bitfield_1.mHeight);

        const left = window_size_x / 2 - width / 2;
        const bottom = window_size_y / 2 - height / 2;

        doText(outro_game_over, left + 120, bottom + 50, &self.outro_game_over_text_ents);
    }
    {
        const texture = renderer_ctx.getTexture(self.big_window_texture_handle);
        const width: f32 = @floatFromInt(texture[0].bitfield_1.mWidth);
        const height: f32 = @floatFromInt(texture[0].bitfield_1.mHeight);

        const left = window_size_x / 2 - width / 2;
        const bottom = window_size_y / 2 - height / 2;

        doText(outro_win, left + 120, bottom + 50, &self.outro_win_text_ents);
    }

    // Help
    {
        const texture = renderer_ctx.getTexture(self.big_window_texture_handle);
        const width: f32 = @floatFromInt(texture[0].bitfield_1.mWidth);
        const height: f32 = @floatFromInt(texture[0].bitfield_1.mHeight);

        const left = window_size_x / 2 - width / 2;
        const bottom = window_size_y / 2 - height / 2;

        doText(help, left + 120, bottom + 50, &self.help_text_ents);
    }

    // Credits
    {
        const texture = renderer_ctx.getTexture(self.big_window_texture_handle);
        const width: f32 = @floatFromInt(texture[0].bitfield_1.mWidth);
        const height: f32 = @floatFromInt(texture[0].bitfield_1.mHeight);

        const left = window_size_x / 2 - width / 2;
        const bottom = window_size_y / 2 - height / 2;

        doText(credits, left + 120, bottom + 50, &self.credits_text_ents);
    }

    {
        const left = 10;
        const bottom = 10;

        doText(help2, left, bottom, &self.help2_text_ents);
    }
}

pub fn deinit() void {}

pub fn update(input_frame_data: *input.FrameData, dt: f32) void {
    // var debugself = self;

    const environment_info = self.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    const window_size_x: f32 = @floatFromInt(self.main_window.frame_buffer_size[0]);
    const window_size_y: f32 = @floatFromInt(self.main_window.frame_buffer_size[1]);

    const big_window_texture = self.renderer_ctx.getTexture(self.big_window_texture_handle);
    const big_window_width: f32 = @floatFromInt(big_window_texture[0].bitfield_1.mWidth);
    const big_window_height: f32 = @floatFromInt(big_window_texture[0].bitfield_1.mHeight);
    const big_window_left = window_size_x / 2 - big_window_width / 2;
    const big_window_bottom = window_size_y / 2 - big_window_height / 2;
    const big_window_image = self.big_window_ent.getMut(fd.UIImage).?;

    // BG image
    {
        big_window_image.rect.x = big_window_left;
        big_window_image.rect.y = big_window_bottom;
    }

    // LOGO
    {
        const logo = self.logo_ent.getMut(fd.UIImage).?;
        logo.rect.x = window_size_x - logo_margin - logo_size;
        logo.rect.y = window_size_y - logo_margin - logo_size;
    }

    const help_pressed = input_frame_data.held(config.input.help);
    const credits_pressed = input_frame_data.held(config.input.credits);

    // Intro
    if (self.intro_text_ents[0].id != 0) {
        doText(intro, big_window_left + 30, big_window_bottom + 50, &self.intro_text_ents);

        if (input_frame_data.just_pressed(config.input.wielded_use_primary) or help_pressed or credits_pressed) {
            for (self.intro_text_ents) |ent| {
                if (ent.id != 0) {
                    self.ecsu_world.delete(ent.id);
                }
            }
            self.intro_text_ents[0].id = 0;
            big_window_image.material.color[3] = 0;
        } else if (big_window_image.material.color[3] < 1) {
            big_window_image.material.color[3] = @min(1, big_window_image.material.color[3] + dt * 4);
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
    if (self.intro_text_ents[0].id == 0) {
        const player_ent = ecs.lookup(self.ecsu_world.world, "main_player");
        const player_health = ecs.get(self.ecsu_world.world, player_ent, fd.Health).?;
        if (player_health.value == 0) {
            environment_info.game_state = .game_over;
            doText(outro_game_over, big_window_left + 30, big_window_bottom + 50, &self.outro_game_over_text_ents);

            // std.log.warn("lol2 {} {}", .{ self.intro_text_ents[0].id, player_health.value });
            if (environment_info.active_camera.?.id != environment_info.player_camera.?.id) {
                big_window_image.material.color[3] = @max(0, big_window_image.material.color[3] - dt * 4);
            } else if (big_window_image.material.color[3] < 1) {
                big_window_image.material.color[3] = @min(1, big_window_image.material.color[3] + dt * 4);
            } else {
                for (self.outro_game_over_text_ents) |ent| {
                    const text = ent.getMut(fd.UIText).?;
                    if (text.shadow_color[3] < 1.0) {
                        text.text_color[3] = 1;
                        text.shadow_color[3] = @min(1, text.shadow_color[3] + dt * 2.5);
                        text.shadow_blur = @min(text.font_size / 5, text.shadow_blur + dt * 20);
                        for (0..3) |i| {
                            text.text_color[i] = std.math.lerp(outro_game_over.color_start[i], outro_game_over.color_end[i], text.shadow_color[3]);
                        }
                        break;
                    }
                }
            }
        } else {
            const query = ecs.query_init(self.ecsu_world.world, &.{
                .terms = [_]ecs.term_t{
                    .{ .id = ecs.id(fd.Enemy), .inout = .In },
                    .{ .id = ecs.id(fd.Health), .inout = .In },
                } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2),
            }) catch unreachable;

            var query_iter = ecs.query_iter(self.ecsu_world.world, query);
            const slime_alive = blk: {
                while (ecs.query_next(&query_iter)) {
                    const enemies = ecs.field(&query_iter, fd.Enemy, 0).?;
                    const healths = ecs.field(&query_iter, fd.Health, 1).?;
                    for (enemies, healths, query_iter.entities()) |enemy, health, ent| {
                        _ = enemy; // autofix
                        _ = ent; // autofix
                        if (health.value > 0) {
                            ecs.iter_fini(&query_iter);
                            break :blk true;
                        }
                    }
                }
                break :blk false;
            };

            if (!slime_alive) {
                environment_info.game_state = .game_over;
                doText(outro_win, big_window_left + 30, big_window_bottom + 50, &self.outro_win_text_ents);

                if (environment_info.active_camera.?.id != environment_info.player_camera.?.id) {
                    big_window_image.material.color[3] = @max(0, big_window_image.material.color[3] - dt * 4);
                } else if (big_window_image.material.color[3] < 1) {
                    big_window_image.material.color[3] = @min(1, big_window_image.material.color[3] + dt * 4);
                } else {
                    for (self.outro_win_text_ents) |ent| {
                        const text = ent.getMut(fd.UIText).?;
                        if (text.shadow_color[3] < 1.0) {
                            text.text_color[3] = 1;
                            text.shadow_color[3] = @min(1, text.shadow_color[3] + dt * 2.5);
                            text.shadow_blur = @min(text.font_size / 5, text.shadow_blur + dt * 20);
                            for (0..3) |i| {
                                text.text_color[i] = std.math.lerp(outro_win.color_start[i], outro_win.color_end[i], text.shadow_color[3]);
                            }
                            break;
                        }
                    }
                }
            }
        }
    }

    // Intro
    if (help_pressed) {
        doText(help, big_window_left + 30, big_window_bottom + 50, &self.help_text_ents);
        if (big_window_image.material.color[3] < 1) {
            big_window_image.material.color[3] = @min(1, big_window_image.material.color[3] + dt * 10);
        } else {
            for (self.help_text_ents) |ent| {
                const text = ent.getMut(fd.UIText).?;
                if (text.shadow_color[3] < 1.0) {
                    text.text_color[3] = 1;
                    text.shadow_color[3] = @min(1, text.shadow_color[3] + dt * 20);
                    text.shadow_blur = @min(text.font_size / 5, text.shadow_blur + dt * 20);
                    for (0..3) |i| {
                        text.text_color[i] = std.math.lerp(help.color_start[i], intro.color_end[i], text.shadow_color[3]);
                    }
                    break;
                }
            }
        }
    } else if (credits_pressed) {
        doText(credits, big_window_left + 30, big_window_bottom + 50, &self.credits_text_ents);
        if (big_window_image.material.color[3] < 1) {
            big_window_image.material.color[3] = @min(1, big_window_image.material.color[3] + dt * 10);
        } else {
            for (self.credits_text_ents) |ent| {
                const text = ent.getMut(fd.UIText).?;
                if (text.shadow_color[3] < 1.0) {
                    text.text_color[3] = 1;
                    text.shadow_color[3] = @min(1, text.shadow_color[3] + dt * 20);
                    text.shadow_blur = @min(text.font_size / 5, text.shadow_blur + dt * 20);
                    for (0..3) |i| {
                        text.text_color[i] = std.math.lerp(credits.color_start[i], intro.color_end[i], text.shadow_color[3]);
                    }
                    break;
                }
            }
        }
    } else if (self.intro_text_ents[0].id == 0 and environment_info.game_state == .running) {
        big_window_image.material.color[3] = 0;
        for (self.help_text_ents) |ent| {
            const text = ent.getMut(fd.UIText).?;
            text.shadow_color[3] = 0;
            text.text_color[3] = 0;
        }
        for (self.credits_text_ents) |ent| {
            const text = ent.getMut(fd.UIText).?;
            text.shadow_color[3] = 0;
            text.text_color[3] = 0;
        }
        for (self.help2_text_ents) |ent| {
            const text = ent.getMut(fd.UIText).?;
            text.shadow_color[3] = 1;
            text.text_color[3] = 1;
        }
    }
}
