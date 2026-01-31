const renderer = @import("renderer/renderer.zig");
const window = @import("renderer/window.zig");
const ecsu = @import("flecs_util/flecs_util.zig");
const fd = @import("config/flecs_data.zig");
const input = @import("input.zig");
const config = @import("config/config.zig");

const logo_size: f32 = 100;
const logo_margin: f32 = 20;

const UI = struct {
    logo_ent: ecsu.Entity,
    intro_ent: ecsu.Entity,

    intro_text_ent: ecsu.Entity,
    intro_text: [:0]const u8,

    main_window: *window.Window,
    ecsu_world: ecsu.World,
};

var self: UI = undefined;

pub fn init(renderer_ctx: *renderer.Renderer, main_window: *window.Window, ecsu_world: ecsu.World) void {
    self.main_window = main_window;
    self.ecsu_world = ecsu_world;

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
                .color = [4]f32{ 1, 1, 1, 1 },
                .texture = texture_handle,
            },
        });
    }

    // Test text
    {
        self.intro_text = "Hello Shadows";
        self.intro_text_ent = ecsu_world.newEntity();
        self.intro_text_ent.set(fd.UIText{
            .left = 10,
            .bottom = 200,
            .font_size = 72,
            .text_color = [4]f32{ 226.0 / 255.0, 198.0 / 255.0, 83.0 / 255.0, 1.0 },
            .shadow_color = [4]f32{ 0, 0, 0, 1.0 },
            .shadow = true,
            .shadow_blur = 2,
            .shadow_offset_x = 2,
            .shadow_offset_y = 2,
            .text = self.intro_text,
        });
    }
}

pub fn deinit() void {}

pub fn update(input_frame_data: *input.FrameData) void {
    const left = @as(f32, @floatFromInt(self.main_window.frame_buffer_size[0])) - logo_margin - logo_size;

    // LOGO
    const logo = self.logo_ent.getMut(fd.UIImage).?;
    logo.rect.x = left;
    logo.rect.y = @as(f32, @floatFromInt(self.main_window.frame_buffer_size[1])) - logo_margin - logo_size;

    // Intro
    if (self.intro_ent.id != 0 and input_frame_data.just_pressed(config.input.wielded_use_primary)) {
        self.ecsu_world.delete(self.intro_ent.id);
        self.intro_ent.id = 0;
    }
}
