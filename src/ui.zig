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
pub const CAMERA_RULES: Vec2 = .{ .x = -1280.0, .y = 1000.0 };
pub const CAMERA_IN_GAME: Vec2 = .{};
pub const CAMERA_IN_GAME_SHOP: Vec2 = .{ .y = 640 };
pub const CAMERA_END_GAME: Vec2 = .{ .y = -1000.0 };

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
    pub const Options = struct {
        tint: ?Color = null,
        center: bool = true,
    };
    pub fn to_screen_quads(
        context: *GlobalContext,
        position: Vec2,
        text_size: f32,
        comptime format: []const u8,
        args: anytype,
        options: Options,
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
            .{ .dont_clip = true, .center = options.center },
        );

        const r = text.to_screen_quads_world_space_raw(
            context.alloc(),
            &context.camera,
        );

        if (options.tint) |ti| {
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

pub const UiDashedLineStatic = struct {
    start: Vec2,
    end: Vec2,
    accumulator: f32,

    const COLOR = Color.from_parts(0, 240, 5, 200);
    const WIDTH: f32 = 2;
    const SEGMENT_GAP: f32 = 5;
    const SEGMENT_LENGTH: f32 = 10;
    const TOTAL_SEGMENT_LEN: f32 = SEGMENT_LENGTH + SEGMENT_GAP;
    const ANIMATION_SPEED = 50;

    pub fn to_screen_quads(
        self: *UiDashedLineStatic,
        context: *GlobalContext,
    ) void {
        self.accumulator += ANIMATION_SPEED * context.dt;
        const animation_offset = @rem(self.accumulator, SEGMENT_LENGTH + SEGMENT_GAP);

        const delta = self.end.sub(self.start);
        const delta_len = delta.len();
        const delta_normalized = delta.mul_f32(1.0 / delta_len);
        const actual_len = delta_len - animation_offset;
        if (actual_len <= 0.0)
            return;

        const c = delta_normalized.cross(.{ .y = 1 });
        const d = delta_normalized.dot(.{ .y = 1 });
        const rotation = if (c < 0.0) -std.math.acos(d) else std.math.acos(d);
        const num_segments: u32 =
            @intFromFloat(@floor(actual_len / TOTAL_SEGMENT_LEN));
        const first_segment_len = animation_offset - SEGMENT_GAP;
        var last_segment_len =
            actual_len - @as(f32, @floatFromInt(num_segments)) * TOTAL_SEGMENT_LEN;
        var segment_positon = self.start
            .add(delta_normalized.mul_f32(SEGMENT_LENGTH / 2 + animation_offset));
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

        if (0.0 < first_segment_len) {
            const first_segment_positon = self.start
                .add(delta_normalized
                .mul_f32(first_segment_len / 2.0));
            const position = context.camera.transform(first_segment_positon.extend(0.0));
            const size: Vec2 = .{ .x = WIDTH, .y = first_segment_len };
            context.screen_quads.add_quad(.{
                .color = COLOR,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .rotation = rotation,
                .size = size.mul_f32(position.z),
                .options = .{ .no_alpha_blend = true },
            });
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
    }
};

pub const UiDashedLine = struct {
    start: Vec2,
    end: Vec2,
    accumulator: f32,

    const COLOR = Color.WHITE;
    const WIDTH: f32 = 5;
    const SEGMENT_GAP: f32 = 15;
    const SEGMENT_LENGTH: f32 = 20;
    const TOTAL_SEGMENT_LEN: f32 = SEGMENT_LENGTH + SEGMENT_GAP;
    const ANIMATION_SPEED = 20;

    const ARROW_ANGLE: f32 = std.math.pi / 4.0;
    const ARROW_H = std.math.sqrt((SEGMENT_LENGTH / 2 * SEGMENT_LENGTH / 2) + (WIDTH / 2 * WIDTH / 2));
    const ARROW_ANGLE_A: f32 = std.math.atan(WIDTH / SEGMENT_LENGTH);
    const ARROW_ANGLE_A_ADJ: f32 = std.math.pi / 4.0 - ARROW_ANGLE_A;
    const ARROW_ANGLE_C: f32 = std.math.pi / 2.0 - ARROW_ANGLE_A_ADJ;
    const ARROW_DELTA: f32 = @sin(ARROW_ANGLE_C) * ARROW_H;
    const ARROW_DELTA_PERP: f32 = @cos(ARROW_ANGLE_C) * ARROW_H;

    pub fn to_screen_quads(
        self: *UiDashedLine,
        context: *GlobalContext,
    ) void {
        self.accumulator += ANIMATION_SPEED * context.dt;
        const animation_offset = @rem(self.accumulator, SEGMENT_LENGTH + SEGMENT_GAP);

        const delta = self.end.sub(self.start);
        const delta_len = delta.len();
        const delta_normalized = delta.mul_f32(1.0 / delta_len);
        const actual_len = delta_len - animation_offset;
        if (actual_len <= 0.0)
            return;

        const c = delta_normalized.cross(.{ .y = 1 });
        const d = delta_normalized.dot(.{ .y = 1 });
        const rotation = if (c < 0.0) -std.math.acos(d) else std.math.acos(d);
        const num_segments: u32 =
            @intFromFloat(@floor(actual_len / TOTAL_SEGMENT_LEN));
        const first_segment_len = animation_offset - SEGMENT_GAP;
        var last_segment_len =
            actual_len - @as(f32, @floatFromInt(num_segments)) * TOTAL_SEGMENT_LEN - ARROW_DELTA;
        var segment_positon = self.start
            .add(delta_normalized.mul_f32(SEGMENT_LENGTH / 2 + animation_offset));
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

        if (0.0 < first_segment_len) {
            const first_segment_positon = self.start
                .add(delta_normalized
                .mul_f32(first_segment_len / 2.0));
            const position = context.camera.transform(first_segment_positon.extend(0.0));
            const size: Vec2 = .{ .x = WIDTH, .y = first_segment_len };
            context.screen_quads.add_quad(.{
                .color = COLOR,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .rotation = rotation,
                .size = size.mul_f32(position.z),
                .options = .{ .no_alpha_blend = true },
            });
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
    const BUTTON_TEXT_SIZE: f32 = 50.0;
    const BUTTON_TEXT_OFFSET: Vec2 = .{ .x = 0.0, .y = 10.0 };
    var panel = UiPanel.init(
        position,
        context.assets.button,
        null,
    );
    const panel_hovered = panel.hovered(context);
    if (panel_hovered)
        panel.texture_id = context.assets.button_hover;
    panel.to_screen_quad(context);
    UiText.to_screen_quads(
        context,
        position.add(BUTTON_TEXT_OFFSET),
        BUTTON_TEXT_SIZE,
        text,
        .{},
        .{},
    );
    if (panel_hovered and context.player_input.lmb == .Pressed) {
        on_press(args);
    }
}

pub fn main_menu(game: *Game, context: *GlobalContext) void {
    {
        const S = struct {
            var a: f32 = 0;
        };
        S.a += context.dt;

        const s = @sin(S.a);
        const text =
            Text.init(
            &context.font,
            "THE  POO L  OF  DESTI NY",
            80.0,
            CAMERA_MAIN_MENU.add(.{ .x = 10.0 + s * 2.0, .y = -170.0 - s * 3.0 }).extend(0.0),
            s * 0.02,
            .{ .x = 400.0, .y = 0.0 },
            .{ .dont_clip = true, .center = true },
        );

        text.to_screen_quads_world_space(
            context.alloc(),
            &context.camera,
            &context.screen_quads,
        );
    }

    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.game.restart(args.context);
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
                args.context.state.rules = true;
                args.context.state_change_animation.set(CAMERA_RULES, .{
                    .rules = true,
                    .debug = args.context.state.debug,
                });
            }
        };
        add_button(
            context,
            CAMERA_MAIN_MENU.add(.{ .y = 88.0 }),
            "Rules",
            S.on_press,
            .{ .context = context },
        );
    }
    {
        _ = UiText.to_screen_quads(
            context,
            CAMERA_MAIN_MENU.add(.{ .x = 5.0, .y = 168.0 }),
            50.0,
            "Volume",
            .{},
            .{},
        );
    }
    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.context.adjust_volume(0.05);
            }
        };
        add_button(
            context,
            CAMERA_MAIN_MENU.add(.{ .x = 180.0, .y = 160.0 }),
            "+",
            S.on_press,
            .{ .context = context },
        );
    }
    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.context.adjust_volume(-0.05);
            }
        };
        add_button(
            context,
            CAMERA_MAIN_MENU.add(.{ .x = -180.0, .y = 160.0 }),
            "-",
            S.on_press,
            .{ .context = context },
        );
    }
}

pub fn rules(context: *GlobalContext) void {
    const game_rules =
        \\ This is an unnatural game of pool.
        \\  There are 2 players in the game. Each one starts with 15 balls.
        \\Players take turns and use cues to hit any of their balls. The goal of the game is to
        \\destroy all opponents balls.
        \\  Each ball starts with 10 HP, 5 DAMAGE and 0 ARMOR. These values can by upgraded
        \\during the game. Total player HP     is a sum of HP of all player balls.
        \\When total player HP drops down to 0, player looses. 
        \\  During the turn, special collision rules apply for friendly (turn owners) and opponents balls:
        \\- If a friendly ball collides with another friendly ball: both heal 1 HP
        \\- If a friendly ball collides with an opponent's ball: friendly ball heals by its
        \\DAMAGE value. Opponent's ball loses HP equal to the friendly ball DAMAGE.
        \\- If opponent's ball hits opponent's ball: nothing happens
        \\  If player's ball looses all HP or is pocketed, it is permanently removed from the field.
        \\If player's ball HP was full when it was healed, the heal amount is converted into souls      .
        \\Souls act as a currency in the game. Players can buy upgrades and other cues in the shop.
        \\Each player starts with a default cue.There is one slot for an additional one. 
        \\Additional cues can be used only once.
    ;
    _ = UiText.to_screen_quads(
        context,
        CAMERA_RULES.add(.{ .x = -615, .y = -320.0 }),
        35.0,
        game_rules,
        .{},
        .{ .center = false },
    );
    UiPanel.init(
        CAMERA_RULES.add(.{ .x = -205, .y = -140.0 }),
        context.assets.blood,
        null,
    ).to_screen_quad(context);
    UiPanel.init(
        CAMERA_RULES.add(.{ .x = 435, .y = 170.0 }),
        context.assets.souls,
        null,
    ).to_screen_quad(context);

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
            CAMERA_RULES.add(.{ .y = 320.0 }),
            "Back",
            S.on_press,
            .{ .context = context },
        );
    }
}

pub fn in_game(game: *Game, context: *GlobalContext) void {
    const PANEL_PLAYER_INFO_POSITION: Vec2 = .{ .x = -520.0, .y = 325.0 };
    const PANEL_OPPONENT_INFO_POSITION: Vec2 = .{ .x = 520.0, .y = -310.0 };

    const PANEL_TEXT_SIZE = 60;
    const PANEL_BLOOD_OFFSET = .{ .x = -90.0, .y = -15.0 };
    const PANEL_HP_OFFSET = .{ .x = -40.0 };
    const PANEL_SOULS_OFFSET = .{ .x = 20.0, .y = -10.0 };
    const PANEL_OVERHEAL_OFFSET = .{ .x = 70.0 };
    const PANEL_BAR_OFFSET = .{ .x = -12.0, .y = 20.0 };

    // OPPONENT HP
    UiPanel.init(
        PANEL_OPPONENT_INFO_POSITION.add(PANEL_BLOOD_OFFSET),
        context.assets.blood,
        null,
    ).to_screen_quad(context);
    _ = UiText.to_screen_quads(
        context,
        PANEL_OPPONENT_INFO_POSITION.add(PANEL_HP_OFFSET),
        PANEL_TEXT_SIZE,
        "{d:.0}",
        .{game.opponent.hp},
        .{},
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
        PANEL_TEXT_SIZE,
        "{d:.0}",
        .{game.opponent.hp_overhead},
        .{},
    );
    const ot = if (game.turn_owner == .Opponent)
        context.assets.under_hp_bar_turn
    else
        context.assets.under_hp_bar;
    UiPanel.init(
        PANEL_OPPONENT_INFO_POSITION.add(PANEL_BAR_OFFSET),
        ot,
        null,
    ).to_screen_quad(context);

    // PLAYER HP
    UiPanel.init(
        PANEL_PLAYER_INFO_POSITION.add(PANEL_BLOOD_OFFSET),
        context.assets.blood,
        null,
    ).to_screen_quad(context);
    _ = UiText.to_screen_quads(
        context,
        PANEL_PLAYER_INFO_POSITION.add(PANEL_HP_OFFSET),
        PANEL_TEXT_SIZE,
        "{d:.0}",
        .{game.player.hp},
        .{},
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
        PANEL_TEXT_SIZE,
        "{d:.0}",
        .{game.player.hp_overhead},
        .{},
    );
    const pt = if (game.turn_owner == .Player)
        context.assets.under_hp_bar_turn
    else
        context.assets.under_hp_bar;
    UiPanel.init(
        PANEL_PLAYER_INFO_POSITION.add(PANEL_BAR_OFFSET),
        pt,
        null,
    ).to_screen_quad(context);

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
            "Shop",
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
            "Give Up",
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
        "You Won",
        .{},
        .{},
    );

    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.game.restart(args.context);
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
            "Again",
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
            "Exit",
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
        "You Lost",
        .{},
        .{},
    );

    {
        const S = struct {
            fn on_press(args: anytype) void {
                args.game.restart(args.context);
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
            "Again",
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
            "Give Up",
            S.on_press,
            .{ .context = context },
        );
    }
}

pub fn debug(context: *GlobalContext) void {
    const text_fps = Text.init(
        &context.font,
        std.fmt.allocPrint(
            context.alloc(),
            "FPS: {d:.1}\nFT: {d:.3}s",
            .{ 1.0 / context.dt, context.dt },
        ) catch unreachable,
        32.0,
        .{
            .x = 1280.0 / 2.0,
            .y = 720 / 2.0 + 300.0,
        },
        0.0,
        .{},
        .{ .dont_clip = true },
    );
    text_fps.to_screen_quads(context.alloc(), &context.screen_quads);
}
