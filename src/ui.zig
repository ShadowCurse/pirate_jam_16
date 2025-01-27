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
pub const CAMERA_IN_GAME_SHOP: Vec2 = .{ .y = 630 };
pub const CAMERA_END_GAME: Vec2 = .{ .y = -1000.0 };

pub const UI_HILIGHT_TINT = Color.from_parts(128, 10, 10, 128);
pub const UI_BACKGROUND_COLOR = Color.GREY;
pub const UI_BACKGROUND_COLOR_PLAYING = Color.GREEN;

pub const UiPanel = struct {
    position: Vec2,
    tint: ?Color,
    texture_id: Textures.Texture.Id,

    pub fn init(
        position: Vec2,
        texture_id: Textures.Texture.Id,
        tint: ?Color,
    ) UiPanel {
        return .{
            .position = position,
            .tint = tint,
            .texture_id = texture_id,
        };
    }

    pub fn hovered(self: UiPanel, context: *GlobalContext) bool {
        const collision_rectangle: Physics.Rectangle = .{
            .size = .{
                .x = @floatFromInt(context.texture_store.get_texture(self.texture_id).width),
                .y = @floatFromInt(context.texture_store.get_texture(self.texture_id).height),
            },
        };
        return Physics.point_rectangle_intersect(
            context.player_input.mouse_pos_world,
            collision_rectangle,
            self.position,
        );
    }

    pub fn to_screen_quad(
        self: UiPanel,
        context: *GlobalContext,
    ) void {
        const position = context.camera.transform(self.position.extend(0.0));
        if (self.tint) |t| {
            context.screen_quads.add_quad(.{
                .color = t,
                .texture_id = self.texture_id,
                .position = position.xy().extend(0.0),
                .uv_size = .{
                    .x = @floatFromInt(context.texture_store.get_texture(self.texture_id).width),
                    .y = @floatFromInt(context.texture_store.get_texture(self.texture_id).height),
                },
                .options = .{
                    // .draw_aabb = true,
                    .clip = false,
                    .no_scale_rotate = true,
                    // .no_alpha_blend = true,
                    .with_tint = true,
                },
            });
        } else {
            context.screen_quads.add_quad(.{
                .texture_id = self.texture_id,
                .position = position.xy().extend(0.0),
                .uv_size = .{
                    .x = @floatFromInt(context.texture_store.get_texture(self.texture_id).width),
                    .y = @floatFromInt(context.texture_store.get_texture(self.texture_id).height),
                },
                .options = .{
                    // .draw_aabb = true,
                    .clip = false,
                    .no_scale_rotate = true,
                    // .no_alpha_blend = true,
                },
            });
        }
    }
};

pub const UiText = struct {
    pub fn to_screen_quads(
        context: *GlobalContext,
        position: Vec2,
        text_size: f32,
        comptime format: []const u8,
        args: anytype,
        tint: ?Color,
    ) void {
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

        const r = text.to_screen_quads_world_space_raw(
            context.alloc(),
            &context.camera,
        );

        if (tint) |ti| {
            for (r.quad_lines) |quad_line| {
                for (quad_line) |*quad| {
                    quad.color = ti;
                    quad.options.with_tint = true;
                }
            }
        }
        for (r.quad_lines) |quad_line| {
            for (quad_line) |quad| {
                context.screen_quads.add_quad(quad);
            }
        }
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

pub fn add_button(
    context: *GlobalContext,
    position: Vec2,
    comptime text: []const u8,
    comptime on_press: fn (anytype) void,
    args: anytype,
) void {
    const panel = UiPanel.init(
        position,
        context.assets.button,
        null,
    );
    const panel_hovered = panel.hovered(context);
    const tint: ?Color = if (panel_hovered) UI_HILIGHT_TINT else null;
    panel.to_screen_quad(context);
    UiText.to_screen_quads(
        context,
        position,
        32.0,
        text,
        .{},
        tint,
    );
    if (panel_hovered and context.player_input.lmb == .Pressed) {
        on_press(args);
    }
}

pub fn main_menu(game: *Game, context: *GlobalContext) void {
    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.game.restart();
                args.context.state.in_game = true;
                args.context.state_change_animation.set(CAMERA_IN_GAME, .{
                    .in_game = true,
                    .debug = args.context.state.debug,
                });
            }
        };
        add_button(
            context,
            CAMERA_MAIN_MENU,
            "Start",
            S.on_press,
            .{ .game = game, .context = context },
        );
    }
    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.context.state.settings = true;
                args.context.state_change_animation.set(CAMERA_SETTINGS, .{
                    .settings = true,
                    .debug = args.context.state.debug,
                });
            }
        };
        add_button(
            context,
            CAMERA_MAIN_MENU.add(.{ .y = 80.0 }),
            "Settings",
            S.on_press,
            .{ .context = context },
        );
    }
}

pub fn settings(context: *GlobalContext) void {
    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.context.state.main_menu = true;
                args.context.state_change_animation.set(CAMERA_MAIN_MENU, .{
                    .main_menu = true,
                    .debug = args.context.state.debug,
                });
            }
        };
        add_button(
            context,
            CAMERA_SETTINGS,
            "Back",
            S.on_press,
            .{ .context = context },
        );
    }
}

pub fn in_game(game: *Game, context: *GlobalContext) void {
    const PANEL_PLAYER_INFO_POSITION: Vec2 = .{ .x = -520.0, .y = -315.0 };
    const PANEL_OPPONENT_INFO_POSITION: Vec2 = .{ .x = 520.0, .y = -315.0 };

    const PANEL_BLOOD_OFFSET = .{ .x = -100.0, .y = -10.0 };
    const PANEL_HP_OFFSET = .{ .x = -50.0 };
    const PANEL_SOULS_OFFSET = .{ .y = -5.0 };
    const PANEL_OVERHEAL_OFFSET = .{ .x = 50.0 };

    // OPPONENT HP
    UiPanel.init(
        PANEL_OPPONENT_INFO_POSITION.add(PANEL_BLOOD_OFFSET),
        context.assets.blood,
        null,
    ).to_screen_quad(context);
    _ = UiText.to_screen_quads(
        context,
        PANEL_OPPONENT_INFO_POSITION.add(PANEL_HP_OFFSET),
        25.0,
        "{d}",
        .{game.opponent.hp},
        null,
    );
    // OPPONENT Overheal
    UiPanel.init(
        PANEL_OPPONENT_INFO_POSITION.add(PANEL_SOULS_OFFSET),
        context.assets.souls,
        null,
    ).to_screen_quad(context);
    _ = UiText.to_screen_quads(
        context,
        PANEL_OPPONENT_INFO_POSITION.add(PANEL_OVERHEAL_OFFSET),
        25.0,
        "{d}",
        .{game.opponent.hp_overhead},
        null,
    );

    // PLAYER HP
    UiPanel.init(
        PANEL_PLAYER_INFO_POSITION.add(PANEL_BLOOD_OFFSET),
        context.assets.blood,
        null,
    ).to_screen_quad(context);
    _ = UiText.to_screen_quads(
        context,
        PANEL_PLAYER_INFO_POSITION.add(PANEL_HP_OFFSET),
        25.0,
        "{d}",
        .{game.player.hp},
        null,
    );
    // PLAYER Overheal
    UiPanel.init(
        PANEL_PLAYER_INFO_POSITION.add(PANEL_SOULS_OFFSET),
        context.assets.souls,
        null,
    ).to_screen_quad(context);
    _ = UiText.to_screen_quads(
        context,
        PANEL_PLAYER_INFO_POSITION.add(PANEL_OVERHEAL_OFFSET),
        25.0,
        "{d}",
        .{game.player.hp_overhead},
        null,
    );

    {
        const S = struct {
            fn on_press(args: anytype) void {
                if (args.context.state.in_game_shop) {
                    args.context.state_change_animation.set(CAMERA_IN_GAME, .{
                        .in_game = true,
                        .debug = args.context.state.debug,
                    });
                } else {
                    args.context.state.in_game_shop = true;
                    args.context.state_change_animation.set(
                        CAMERA_IN_GAME_SHOP,
                        args.context.state,
                    );
                }
            }
        };
        add_button(
            context,
            .{ .x = 350.0, .y = 320.0 },
            "SHOP",
            S.on_press,
            .{ .context = context },
        );
    }
    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.context.state.main_menu = true;
                args.context.state_change_animation.set(CAMERA_MAIN_MENU, .{
                    .main_menu = true,
                    .debug = args.context.state.debug,
                });
            }
        };
        add_button(
            context,
            .{ .x = 550.0, .y = 320.0 },
            "GIVE UP",
            S.on_press,
            .{ .context = context },
        );
    }
}

pub fn in_end_game_won(game: *Game, context: *GlobalContext) void {
    _ = UiText.to_screen_quads(
        context,
        CAMERA_END_GAME.add(.{ .y = -200.0 }),
        32.0,
        "YOU WON",
        .{},
        null,
    );

    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.game.restart();
                args.context.state.in_game = true;
                args.context.state_change_animation.set(CAMERA_IN_GAME, .{
                    .in_game = true,
                    .debug = args.context.state.debug,
                });
            }
        };
        add_button(
            context,
            CAMERA_END_GAME,
            "GO AGAIN",
            S.on_press,
            .{ .game = game, .context = context },
        );
    }
    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.context.state.main_menu = true;
                args.context.state_change_animation.set(CAMERA_MAIN_MENU, .{
                    .main_menu = true,
                    .debug = args.context.state.debug,
                });
            }
        };
        add_button(
            context,
            CAMERA_END_GAME.add(.{ .y = 100.0 }),
            "I'VE HAD ENOUGH",
            S.on_press,
            .{ .context = context },
        );
    }
}

pub fn in_end_game_lost(game: *Game, context: *GlobalContext) void {
    _ = UiText.to_screen_quads(
        context,
        CAMERA_END_GAME.add(.{ .y = -200.0 }),
        32.0,
        "YOU LOST",
        .{},
        null,
    );

    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.game.restart();
                args.context.state.in_game = true;
                args.context.state_change_animation.set(CAMERA_IN_GAME, .{
                    .in_game = true,
                    .debug = args.context.state.debug,
                });
            }
        };
        add_button(
            context,
            CAMERA_END_GAME,
            "TRY AGAIN",
            S.on_press,
            .{
                .game = game,
                .context = context,
            },
        );
    }
    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.context.state.main_menu = true;
                args.context.state_change_animation.set(CAMERA_MAIN_MENU, .{
                    .main_menu = true,
                    .debug = args.context.state.debug,
                });
            }
        };
        add_button(
            context,
            CAMERA_END_GAME.add(.{ .y = 100.0 }),
            "GIVE UP",
            S.on_press,
            .{ .context = context },
        );
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
        null,
    );
}
