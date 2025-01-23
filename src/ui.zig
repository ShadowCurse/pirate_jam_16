const std = @import("std");
const stygian = @import("stygian_runtime");

const Allocator = std.mem.Allocator;

const Text = stygian.text;
const Font = stygian.font;
const Physics = stygian.physics;
const Color = stygian.color.Color;
const Textures = stygian.textures;
const ScreenQuads = stygian.screen_quads;
const CameraController2d = stygian.camera.CameraController2d;

const _math = stygian.math;
const Vec2 = _math.Vec2;

const _runtime = @import("runtime.zig");
const GlobalContext = _runtime.GlobalContext;

const Game = @import("game.zig");

pub const CAMERA_MAIN_MENU: Vec2 = .{ .x = -1280.0 };
pub const CAMERA_SETTINGS: Vec2 = .{ .x = -1280.0, .y = 1000.0 };
pub const CAMERA_IN_GAME: Vec2 = .{};
pub const CAMERA_IN_GAME_SHOP: Vec2 = .{ .y = 617 };

const UI_BACKGROUND_COLOR = Color.GREY;
const UI_BACKGROUND_COLOR_PLAYING = Color.GREEN;

pub const UiPanel = struct {
    position: Vec2,
    size: Vec2,
    color: Color,

    pub fn init(position: Vec2, size: Vec2, color: Color) UiPanel {
        return .{
            .position = position,
            .size = size,
            .color = color,
        };
    }

    pub fn to_screen_quad(
        self: UiPanel,
        context: *GlobalContext,
    ) void {
        const position = context.camera.transform(self.position.extend(0.0));
        context.screen_quads.add_quad(.{
            .color = self.color,
            .texture_id = Textures.Texture.ID_SOLID_COLOR,
            .position = position.xy().extend(0.0),
            .size = self.size.mul_f32(position.z),
            .options = .{ .clip = false, .no_scale_rotate = true, .no_alpha_blend = true },
        });
    }
};

pub const UiText = struct {
    pub const Options = struct {
        world_space: bool = true,
        hilight: bool = false,
    };
    pub fn to_screen_quads(
        context: *GlobalContext,
        position: Vec2,
        text_size: f32,
        comptime format: []const u8,
        args: anytype,
        comptime options: Options,
    ) bool {
        const t = std.fmt.allocPrint(
            context.alloc(),
            format,
            args,
        ) catch unreachable;

        const text =
            Text.init(
            &context.font,
            t,
            text_size,
            position.extend(0.0),
            0.0,
            .{},
            .{ .dont_clip = true },
        );

        const text_quads = if (!options.world_space)
            text.to_screen_quads_raw(context.alloc())
        else
            text.to_screen_quads_world_space_raw(
                context.alloc(),
                &context.camera,
            );

        const collision_rectangle: Physics.Rectangle = .{
            .size = .{
                .x = text_quads.total_width,
                .y = text.size,
            },
        };
        const rectangle_position: Vec2 =
            text.position.xy().add(.{ .y = -text.size / 2.0 });

        const mouse_pos = if (options.world_space)
            context.input.mouse_pos_world
        else
            context.input.mouse_pos;

        const intersects = Physics.point_rectangle_intersect(
            mouse_pos,
            collision_rectangle,
            rectangle_position,
        );
        if (options.hilight and intersects) {
            for (text_quads.quads) |*quad| {
                quad.color = Color.RED;
                quad.options.with_tint = true;
            }
        }
        for (text_quads.quads) |quad| {
            context.screen_quads.add_quad(quad);
        }
        return intersects;
    }
};

pub const UiDashedLine = struct {
    start: Vec2,
    end: Vec2,

    const COLOR = Color.WHITE;
    const WIDTH: f32 = 10;
    const SEGMENT_GAP: f32 = 10;
    const SEGMENT_LENGTH: f32 = 30;
    const TOTAL_SEGMENT_LEN: f32 = SEGMENT_LENGTH + SEGMENT_GAP;

    const ARROW_ANGLE: f32 = std.math.pi / 4.0;
    const ARROW_H = std.math.sqrt((SEGMENT_LENGTH / 2 * SEGMENT_LENGTH / 2) + (WIDTH / 2 * WIDTH / 2));
    const ARROW_ANGLE_A: f32 = std.math.atan(WIDTH / SEGMENT_LENGTH);
    const ARROW_ANGLE_A_ADJ: f32 = std.math.pi / 4.0 - ARROW_ANGLE_A;
    const ARROW_ANGLE_C: f32 = std.math.pi / 2.0 - ARROW_ANGLE_A_ADJ;
    const ARROW_DELTA: f32 = @sin(ARROW_ANGLE_C) * ARROW_H;
    const ARROW_DELTA_PERP: f32 = @cos(ARROW_ANGLE_C) * ARROW_H;

    pub fn to_screen_quads(
        self: UiDashedLine,
        context: *GlobalContext,
    ) void {
        const delta = self.end.sub(self.start);
        const delta_len = delta.len();
        const delta_normalized = delta.mul_f32(1.0 / delta_len);
        const c = delta_normalized.cross(.{ .y = 1 });
        const d = delta_normalized.dot(.{ .y = 1 });
        const rotation = if (c < 0.0) -std.math.acos(d) else std.math.acos(d);
        const num_segments: u32 =
            @intFromFloat(@floor(delta_len / TOTAL_SEGMENT_LEN));
        var last_segment_len =
            delta_len - @as(f32, @floatFromInt(num_segments)) * TOTAL_SEGMENT_LEN - ARROW_DELTA;
        var segment_positon = self.start.add(delta_normalized.mul_f32(SEGMENT_LENGTH / 2));
        for (0..num_segments) |_| {
            const position = context.camera.transform(segment_positon.extend(0.0));
            const size: Vec2 = .{ .x = WIDTH, .y = SEGMENT_LENGTH };
            context.screen_quads.add_quad(.{
                .color = COLOR,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .rotation = rotation,
                .size = size.mul_f32(position.z),
                .options = .{ .no_alpha_blend = true },
            });

            segment_positon =
                segment_positon.add(delta_normalized.mul_f32(TOTAL_SEGMENT_LEN));
        }

        if (0.0 < last_segment_len) {
            last_segment_len = @min(last_segment_len, SEGMENT_LENGTH);
            segment_positon = segment_positon
                .add(delta_normalized
                .mul_f32(-SEGMENT_LENGTH / 2 + last_segment_len / 2.0));
            const position = context.camera.transform(segment_positon.extend(0.0));
            const size: Vec2 = .{ .x = WIDTH, .y = last_segment_len };
            context.screen_quads.add_quad(.{
                .color = COLOR,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .rotation = rotation,
                .size = size.mul_f32(position.z),
                .options = .{ .no_alpha_blend = true },
            });
        }

        const delta_perp = delta_normalized.perp();

        {
            const arrow_left_segment_positon = self.end.add(delta_normalized
                .mul_f32(-ARROW_DELTA)).add(delta_perp.mul_f32(ARROW_DELTA_PERP));
            const position = context.camera.transform(arrow_left_segment_positon.extend(0.0));
            const size: Vec2 = .{ .x = WIDTH, .y = SEGMENT_LENGTH };
            context.screen_quads.add_quad(.{
                .color = COLOR,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .rotation = rotation + ARROW_ANGLE,
                .size = size.mul_f32(position.z),
                .options = .{ .no_alpha_blend = true },
            });
        }

        {
            const arrow_right_segment_positon = self.end.add(delta_normalized
                .mul_f32(-ARROW_DELTA)).add(delta_perp.mul_f32(-ARROW_DELTA_PERP));
            const position = context.camera.transform(arrow_right_segment_positon.extend(0.0));
            const size: Vec2 = .{ .x = WIDTH, .y = SEGMENT_LENGTH };
            context.screen_quads.add_quad(.{
                .color = COLOR,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .rotation = rotation - ARROW_ANGLE,
                .size = size.mul_f32(position.z),
                .options = .{ .no_alpha_blend = true },
            });
        }
    }
};

pub fn main_menu(game: *Game, context: *GlobalContext) void {
    if (UiText.to_screen_quads(
        context,
        CAMERA_MAIN_MENU,
        32.0,
        "Start",
        .{},
        .{ .hilight = true },
    ) and context.input.lmb) {
        game.restart();
        context.state.in_game = true;
        context.state_change_animation.set(CAMERA_IN_GAME, .{
            .in_game = true,
            .debug = context.state.debug,
        });
    }

    if (UiText.to_screen_quads(
        context,
        CAMERA_MAIN_MENU.add(.{ .y = 50.0 }),
        32.0,
        "Settings",
        .{},
        .{ .hilight = true },
    ) and context.input.lmb) {
        context.state.settings = true;
        context.state_change_animation.set(CAMERA_SETTINGS, .{
            .settings = true,
            .debug = context.state.debug,
        });
    }
}

pub fn settings(context: *GlobalContext) void {
    if (UiText.to_screen_quads(
        context,
        CAMERA_SETTINGS,
        32.0,
        "Back",
        .{},
        .{ .hilight = true },
    ) and context.input.lmb) {
        context.state.main_menu = true;
        context.state_change_animation.set(CAMERA_MAIN_MENU, .{
            .main_menu = true,
            .debug = context.state.debug,
        });
    }
}

pub fn in_game(game: *Game, context: *GlobalContext) void {
    const top_panel = UiPanel.init(
        .{ .y = -310.0 },
        .{ .x = 900.0, .y = 80.0 },
        UI_BACKGROUND_COLOR,
    );
    top_panel.to_screen_quad(context);

    const bot_panel = UiPanel.init(
        .{ .y = 310.0 },
        .{ .x = 900.0, .y = 80.0 },
        UI_BACKGROUND_COLOR,
    );
    bot_panel.to_screen_quad(context);

    const left_info_opponent_panel = UiPanel.init(
        .{ .x = -550.0, .y = -300 },
        .{ .x = 140.0, .y = 100.0 },
        if (game.turn_owner == .Opponent) UI_BACKGROUND_COLOR_PLAYING else UI_BACKGROUND_COLOR,
    );
    left_info_opponent_panel.to_screen_quad(context);

    const left_info_player_panel = UiPanel.init(
        .{ .x = -550.0, .y = 300 },
        .{ .x = 140.0, .y = 100.0 },
        if (game.turn_owner == .Player) UI_BACKGROUND_COLOR_PLAYING else UI_BACKGROUND_COLOR,
    );
    left_info_player_panel.to_screen_quad(context);

    _ = UiText.to_screen_quads(
        context,
        .{ .x = -550.0, .y = -300 },
        25.0,
        "HP: {d}",
        .{game.opponent.hp},
        .{},
    );
    _ = UiText.to_screen_quads(
        context,
        .{ .x = -550.0, .y = -280 },
        25.0,
        "HP overhead: {d}",
        .{game.opponent.hp_overhead},
        .{},
    );

    _ = UiText.to_screen_quads(
        context,
        .{ .x = -550.0, .y = 280 },
        25.0,
        "HP: {d}",
        .{game.player.hp},
        .{},
    );
    _ = UiText.to_screen_quads(
        context,
        .{ .x = -550.0, .y = 300 },
        25.0,
        "HP overhead: {d}",
        .{game.player.hp_overhead},
        .{},
    );

    const left_cue_panel = UiPanel.init(
        .{ .x = -550.0 },
        .{ .x = 140.0, .y = 480.0 },
        UI_BACKGROUND_COLOR,
    );
    left_cue_panel.to_screen_quad(context);

    const right_cue_panel = UiPanel.init(
        .{ .x = 550.0 },
        .{ .x = 140.0, .y = 480.0 },
        UI_BACKGROUND_COLOR,
    );
    right_cue_panel.to_screen_quad(context);

    if (UiText.to_screen_quads(
        context,
        .{ .x = 350.0, .y = 320.0 },
        32.0,
        "SHOP",
        .{},
        .{ .hilight = true },
    ) and context.input.lmb and
        !context.state_change_animation.is_playing())
    {
        if (context.state.in_game_shop) {
            context.state_change_animation.set(CAMERA_IN_GAME, .{
                .in_game = true,
                .debug = context.state.debug,
            });
        } else {
            context.state.in_game_shop = true;
            context.state_change_animation.set(CAMERA_IN_GAME_SHOP, context.state);
        }
    }

    if (UiText.to_screen_quads(
        context,
        .{ .x = 550.0, .y = 320.0 },
        32.0,
        "GIVE UP",
        .{},
        .{ .hilight = true },
    ) and context.input.lmb) {
        context.state.main_menu = true;
        context.state_change_animation.set(CAMERA_MAIN_MENU, .{
            .main_menu = true,
            .debug = context.state.debug,
        });
    }
}

pub fn debug(context: *GlobalContext) void {
    _ = UiText.to_screen_quads(
        context,
        .{
            .x = 1280.0 / 2.0,
            .y = 720.0 / 2.0 + 300.0,
        },
        32.0,
        "FPS: {d:.1} FT: {d:.3}s",
        .{ 1.0 / context.dt, context.dt },
        .{ .world_space = false },
    );
}
