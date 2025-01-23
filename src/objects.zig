const std = @import("std");
const stygian = @import("stygian_runtime");

const Allocator = std.mem.Allocator;

const log = stygian.log;
const Tracing = stygian.tracing;

const Text = stygian.text;
const Font = stygian.font;
const Memory = stygian.memory;
const Physics = stygian.physics;
const Color = stygian.color.Color;
const Textures = stygian.textures;
const Events = stygian.platform.event;
const ScreenQuads = stygian.screen_quads;
const SoftRenderer = stygian.soft_renderer.renderer;
const CameraController2d = stygian.camera.CameraController2d;

const _objects = stygian.objects;
const Object2d = _objects.Object2d;

const _math = stygian.math;
const Vec2 = _math.Vec2;

const _runtime = @import("runtime.zig");
const InputState = _runtime.InputState;
const GlobalContext = _runtime.GlobalContext;

const _game = @import("game.zig");
const Owner = _game.Owner;

const _animations = @import("animations.zig");
const SmoothStepAnimation = _animations.SmoothStepAnimation;

const _ui = @import("ui.zig");
const UiText = _ui.UiText;
const UiPanel = _ui.UiPanel;
const UiDashedLine = _ui.UiDashedLine;

pub const Ball = struct {
    id: u8,
    texture_id: Textures.Texture.Id,
    color: Color,

    owner: Owner,
    hp: i32 = 10,
    max_hp: i32 = 10,
    damage: i32 = 1,
    heal: i32 = 1,
    armor: f32 = 0.0,
    gravity_level: u8 = 0,
    runner_level: u8 = 0,
    ring_of_light_level: u8 = 0,

    body: Physics.Body,
    collider: Physics.Circle,
    disabled: bool = false,
    stationary: bool = true,

    previous_positions: [PREVIOUS_POSITIONS]Vec2,
    previous_position_index: u32,

    // This is sprite size dependent because I don't scale balls for perf gains.
    pub const RADIUS = 10;
    pub const HP_TEXT_SIZE = 20;
    pub const INFO_PANEL_OFFSET: Vec2 = .{ .y = -100.0 };
    pub const INFO_PANEL_SIZE: Vec2 = .{ .x = 100.0, .y = 150.0 };
    pub const PREVIOUS_POSITIONS = 64;
    pub const UPGRADE_HILIGHT_COLOR = Color.from_parts(255, 0, 0, 64);
    pub const HOVER_HILIGHT_COLOR = Color.from_parts(0, 0, 255, 64);

    pub const trace = Tracing.Measurements(struct {
        update: Tracing.Counter,
        to_object_2d: Tracing.Counter,
        previous_positions_to_object_2d: Tracing.Counter,
    });

    pub fn init(
        id: u8,
        color: Color,
        texture_id: Textures.Texture.Id,
        owner: Owner,
        position: Vec2,
    ) Ball {
        return .{
            .id = id,
            .texture_id = texture_id,
            .color = color,
            .owner = owner,
            .body = .{
                .position = position,
                .velocity = .{},
                .restitution = 1.0,
                .friction = 0.95,
                .inv_mass = 1.0,
            },
            .collider = .{
                .radius = RADIUS,
            },
            .previous_positions = [_]Vec2{position} ** 64,
            .previous_position_index = 0,
            .disabled = false,
        };
    }

    // TODO do only one pass over all combinations
    // TODO maybe add a rotation calculations as well
    // TODO friction application seems not very physics based
    pub fn update(
        self: *Ball,
        table: *const Table,
        balls: []Ball,
        turn_owner: Owner,
        dt: f32,
    ) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        if (self.disabled)
            return;

        for (balls) |*ball| {
            if (self.id == ball.id)
                continue;
            const collision_point =
                Physics.circle_circle_collision(
                self.collider,
                self.body.position,
                ball.collider,
                ball.body.position,
            );
            if (collision_point) |cp| {
                if (self.owner == turn_owner) {
                    if (ball.owner == turn_owner) {
                        self.hp += ball.heal;
                        ball.hp += self.heal;
                    } else {
                        const min = @min(self.damage, ball.hp);
                        const min_f32: f32 = @floatFromInt(min);
                        const d: i32 =
                            @intFromFloat(min_f32 * (1.0 - ball.armor));
                        self.hp += d;
                        ball.hp -= d;
                    }
                } else {
                    if (ball.owner == turn_owner) {
                        const min = @min(ball.damage, self.hp);
                        const min_f32: f32 = @floatFromInt(min);
                        const d: i32 =
                            @intFromFloat(min_f32 * (1.0 - ball.armor));
                        self.hp -= d;
                        ball.hp += d;
                    } else {
                        // nothing happens if 2 oppenents balls collide during players turn
                        // and vise versa
                    }
                }

                if (cp.normal.is_valid()) {
                    Physics.apply_collision_impulse(&self.body, &ball.body, cp);
                    log.info(
                        @src(),
                        "collision of ball: {d} and ball: {d}",
                        .{ self.id, ball.id },
                    );
                } else {
                    log.info(
                        @src(),
                        "invalid normal for collision of ball: {d} and ball: {d}",
                        .{ self.id, ball.id },
                    );
                }
            }
        }
        for (&table.borders, 0..) |*border, i| {
            const collision_point =
                Physics.circle_rectangle_collision(
                self.collider,
                self.body.position,
                border.collider,
                border.body.position,
            );
            if (collision_point) |cp| {
                if (cp.normal.is_valid()) {
                    Physics.apply_collision_impulse_static(&self.body, &border.body, cp);
                    log.info(
                        @src(),
                        "collision of ball: {d} and border: {d}",
                        .{ self.id, i },
                    );
                } else {
                    const ncp =
                        Physics.point_rectangle_closest_collision_point(
                        self.previous_positions[self.previous_position_index],
                        border.collider,
                        border.body.position,
                    );
                    log.assert(
                        @src(),
                        ncp.normal.is_valid(),
                        "prevous position collision produced invalid normal",
                        .{},
                    );
                    Physics.apply_collision_impulse_static(&self.body, &border.body, ncp);
                    log.info(
                        @src(),
                        "invalid normal for collision of ball: {d} and border: {d}",
                        .{ self.id, i },
                    );
                }
            }
        }

        self.previous_positions[self.previous_position_index] = self.body.position;
        self.previous_position_index += 1;
        self.previous_position_index %= PREVIOUS_POSITIONS;
        self.body.position = self.body.position.add(self.body.velocity.mul_f32(dt));
        self.body.velocity = self.body.velocity.mul_f32(self.body.friction);

        if (self.body.velocity.len_squared() < 0.1) {
            self.body.velocity = .{};
            self.stationary = true;
        } else {
            self.stationary = false;
        }

        log.assert(@src(), self.body.position.is_valid(), "Body position is invalid", .{});
        log.assert(@src(), self.body.velocity.is_valid(), "Body velocity is invalid", .{});

        if (self.body.position.x < -Table.WIDTH / 2.0 or Table.WIDTH / 2.0 < self.body.position.x or
            self.body.position.y < -Table.HEIGTH / 2.0 or Table.HEIGTH / 2.0 < self.body.position.y)
        {
            self.body.velocity = .{};
            self.disabled = true;
        }
    }

    pub fn is_hovered(self: Ball, mouse_pos: Vec2) bool {
        return Physics.point_circle_intersect(mouse_pos, self.collider, self.body.position);
    }

    pub fn add_upgrade(self: *Ball, upgrade: Item.Tag) bool {
        switch (upgrade) {
            .BallSpiky => {
                self.damage += 5;
            },
            .BallHealthy => {
                self.hp += 5;
                self.max_hp += 5;
            },
            .BallArmored => {
                self.armor += 0.5;
            },
            .BallLight => {
                self.body.inv_mass += 0.1;
            },
            .BallHeavy => {
                self.body.inv_mass -= 0.1;
            },
            .BallGravity => {
                self.gravity_level += 1;
            },
            .BallRunner => {
                self.runner_level += 1;
            },
            .BallRingOfLight => {
                self.ring_of_light_level += 1;
            },
            else => unreachable,
        }

        return true;
    }

    pub const ToScreenQuadsResult = struct {
        upgrade_applied: bool = false,
        need_refill: bool = false,
    };

    pub fn to_screen_quads(
        self: *Ball,
        context: *GlobalContext,
        show_info: bool,
        selected_upgrade: ?Item.Tag,
    ) ToScreenQuadsResult {
        var result: ToScreenQuadsResult = .{};
        const is_ball_upgrade = if (selected_upgrade) |si| si.is_ball() else false;
        if (is_ball_upgrade) {
            const object: Object2d = .{
                .type = .{ .TextureId = self.texture_id },
                .tint = UPGRADE_HILIGHT_COLOR,
                .transform = .{
                    .position = self.body.position.extend(0.0),
                },
                .size = .{
                    .x = RADIUS * 2.0 * 2.0,
                    .y = RADIUS * 2.0 * 2.0,
                },
                .options = .{ .with_tint = true },
            };
            object.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
        }
        if (self.is_hovered(context.input.mouse_pos_world)) {
            const object: Object2d = .{
                .type = .{ .TextureId = self.texture_id },
                .tint = HOVER_HILIGHT_COLOR,
                .transform = .{
                    .position = self.body.position.extend(0.0),
                },
                .size = .{
                    .x = RADIUS * 2.0 * 1.5,
                    .y = RADIUS * 2.0 * 1.5,
                },
                .options = .{ .with_tint = true },
            };
            object.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
            if (is_ball_upgrade and context.input.lmb) {
                result.upgrade_applied = self.add_upgrade(selected_upgrade.?);
            }
        }
        if (show_info) {
            result.need_refill = self.info_panel_to_screen_quads(context) and context.input.lmb;
        }
        const object: Object2d = .{
            .type = .{ .TextureId = self.texture_id },
            .tint = self.color,
            .transform = .{
                .position = self.body.position.extend(0.0),
            },
            .options = .{ .draw_aabb = true, .no_scale_rotate = true, .with_tint = true },
        };
        object.to_screen_quad(&context.camera, &context.texture_store, &context.screen_quads);

        self.hp_to_screen_quads(context);

        return result;
    }

    pub fn hp_to_screen_quads(
        self: Ball,
        context: *GlobalContext,
    ) void {
        _ = UiText.to_screen_quads(
            context,
            self.body.position.add(.{ .y = HP_TEXT_SIZE / 4.0 }),
            HP_TEXT_SIZE,
            "{d}",
            .{self.hp},
            .{},
        );
    }

    pub fn info_panel_to_screen_quads(self: Ball, context: *GlobalContext) bool {
        const panel_position = self.body.position.add(INFO_PANEL_OFFSET);
        const info_panel = UiPanel.init(
            panel_position,
            INFO_PANEL_SIZE,
            Color.GREY,
        );
        info_panel.to_screen_quad(context);

        {
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .y = -40.0 }),
                HP_TEXT_SIZE,
                "HP: {d}",
                .{self.hp},
                .{},
            );
        }

        {
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .y = -20.0 }),
                HP_TEXT_SIZE,
                "Damage: {d}",
                .{self.damage},
                .{},
            );
        }

        return UiText.to_screen_quads(
            context,
            panel_position.add(.{ .y = 40.0 }),
            25.0,
            "Refill ball HP with {d} overhead HP",
            .{self.max_hp - self.hp},
            .{},
        );
    }

    pub fn previous_positions_to_object_2d(self: Ball, context: *GlobalContext) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        var pp_index = self.previous_position_index;
        var base_color = self.color;
        base_color.format.a = 0;
        for (0..PREVIOUS_POSITIONS) |i| {
            const previous_position = self.previous_positions[pp_index];
            var color = base_color;
            color.format.a = @as(u8, @intCast(i)) * 2;
            const object: Object2d = .{
                .type = .{ .TextureId = self.texture_id },
                .tint = color,
                .transform = .{
                    .position = previous_position.extend(0.0),
                },
                .options = .{ .no_scale_rotate = true, .with_tint = true },
            };

            object.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
            pp_index += 1;
            pp_index %= PREVIOUS_POSITIONS;
        }
    }
};

pub const Table = struct {
    texture_id: Textures.Texture.Id,
    borders: [6]Border,
    pockets: [6]Pocket,

    pub const WIDTH = 896;
    pub const HEIGTH = 514;
    pub const BORDER = 66;
    pub const POCKET_GAP = 60;
    pub const POCKET_RADIUS = 60;
    pub const POCKET_CORNER_OFFSET = 30;

    pub const Border = struct {
        body: Physics.Body,
        collider: Physics.Rectangle,
    };

    pub const Pocket = struct {
        body: Physics.Body,
        collider: Physics.Circle,
    };

    pub const trace = Tracing.Measurements(struct {
        to_screen_quad: Tracing.Counter,
        borders_to_screen_quads: Tracing.Counter,
        pockets_to_screen_quads: Tracing.Counter,
    });

    pub fn init(texture_id: Textures.Texture.Id) Table {
        return .{
            .texture_id = texture_id,
            .borders = .{
                // left
                .{
                    .body = .{
                        .position = .{ .x = -WIDTH / 2 + BORDER / 2 },
                    },
                    .collider = .{
                        .size = .{ .x = BORDER, .y = HEIGTH - POCKET_GAP * 3.0 },
                    },
                },
                // right
                .{
                    .body = .{
                        .position = .{ .x = WIDTH / 2 - BORDER / 2 },
                    },
                    .collider = .{
                        .size = .{ .x = BORDER, .y = HEIGTH - POCKET_GAP * 3.0 },
                    },
                },
                // bottom left
                .{
                    .body = .{
                        .position = .{ .x = -WIDTH / 4 + POCKET_GAP / 2, .y = -HEIGTH / 2 + BORDER / 2 },
                    },
                    .collider = .{
                        .size = .{ .x = WIDTH / 2 - POCKET_GAP * 2, .y = BORDER },
                    },
                },
                // bottom right
                .{
                    .body = .{
                        .position = .{ .x = WIDTH / 4 - POCKET_GAP / 2, .y = -HEIGTH / 2 + BORDER / 2 },
                    },
                    .collider = .{
                        .size = .{ .x = WIDTH / 2 - POCKET_GAP * 2, .y = BORDER },
                    },
                },

                // top left
                .{
                    .body = .{
                        .position = .{ .x = -WIDTH / 4 + POCKET_GAP / 2, .y = HEIGTH / 2 - BORDER / 2 },
                    },
                    .collider = .{
                        .size = .{ .x = WIDTH / 2 - POCKET_GAP * 2, .y = BORDER },
                    },
                },
                // top right
                .{
                    .body = .{
                        .position = .{ .x = WIDTH / 4 - POCKET_GAP / 2, .y = HEIGTH / 2 - BORDER / 2 },
                    },
                    .collider = .{
                        .size = .{ .x = WIDTH / 2 - POCKET_GAP * 2, .y = BORDER },
                    },
                },
            },
            .pockets = .{
                // bot left
                .{
                    .body = .{
                        .position = .{
                            .x = -WIDTH / 2 + POCKET_CORNER_OFFSET,
                            .y = -HEIGTH / 2 + POCKET_CORNER_OFFSET,
                        },
                    },
                    .collider = .{
                        .radius = POCKET_RADIUS,
                    },
                },
                // bot middle
                .{
                    .body = .{
                        .position = .{ .y = -HEIGTH / 2 },
                    },
                    .collider = .{
                        .radius = POCKET_RADIUS,
                    },
                },
                // bot right
                .{
                    .body = .{
                        .position = .{
                            .x = WIDTH / 2 - POCKET_CORNER_OFFSET,
                            .y = -HEIGTH / 2 + POCKET_CORNER_OFFSET,
                        },
                    },
                    .collider = .{
                        .radius = POCKET_RADIUS,
                    },
                },
                // top left
                .{
                    .body = .{
                        .position = .{
                            .x = -WIDTH / 2 + POCKET_CORNER_OFFSET,
                            .y = HEIGTH / 2 - POCKET_CORNER_OFFSET,
                        },
                    },
                    .collider = .{
                        .radius = POCKET_RADIUS,
                    },
                },
                // top middle
                .{
                    .body = .{
                        .position = .{ .y = HEIGTH / 2 },
                    },
                    .collider = .{
                        .radius = POCKET_RADIUS,
                    },
                },
                // tob right
                .{
                    .body = .{
                        .position = .{
                            .x = WIDTH / 2 - POCKET_CORNER_OFFSET,
                            .y = HEIGTH / 2 - POCKET_CORNER_OFFSET,
                        },
                    },
                    .collider = .{
                        .radius = POCKET_RADIUS,
                    },
                },
            },
        };
    }

    pub fn to_screen_quad(
        self: Table,
        context: *GlobalContext,
    ) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        const table_object: Object2d = .{
            .type = .{ .TextureId = self.texture_id },
            .transform = .{},
            .size = .{
                .x = @floatFromInt(context.texture_store.get_texture(self.texture_id).width),
                .y = @floatFromInt(context.texture_store.get_texture(self.texture_id).height),
            },
            .options = .{ .no_alpha_blend = true },
        };
        table_object.to_screen_quad(
            &context.camera,
            &context.texture_store,
            &context.screen_quads,
        );

        self.borders_to_screen_quads(context);
        self.pockets_to_screen_quads(context);
    }

    pub fn borders_to_screen_quads(
        self: Table,
        context: *GlobalContext,
    ) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        const border_color = Color.from_parts(255.0, 255.0, 255.0, 64.0);
        for (&self.borders) |*border| {
            const position = context.camera.transform(border.body.position.extend(0.0));
            context.screen_quads.add_quad(.{
                .color = border_color,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .size = border.collider.size.mul_f32(position.z),
                .options = .{ .draw_aabb = true },
            });
        }
    }

    pub fn pockets_to_screen_quads(
        self: Table,
        context: *GlobalContext,
    ) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        const pocket_color = Color.from_parts(64.0, 255.0, 64.0, 64.0);
        for (&self.pockets) |*pocket| {
            const position = context.camera.transform(pocket.body.position.extend(0.0));
            const size: Vec2 = .{
                .x = pocket.collider.radius * 2.0,
                .y = pocket.collider.radius * 2.0,
            };
            context.screen_quads.add_quad(.{
                .color = pocket_color,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .size = size.mul_f32(position.z),
                .options = .{ .draw_aabb = true },
            });
        }
    }
};

pub const Cue = struct {
    tag: Item.Tag,
    position: Vec2,
    rotation: f32,
    storage_position: Vec2,
    storage_rotation: f32,
    shoot_animation: ?SmoothStepAnimation,

    add_heal: i32 = 0,
    add_damage: i32 = 0,
    hit_count: u8 = 1,
    hit_strength: f32 = 1.0,
    wiggle_ball: bool = false,
    scope: bool = false,
    silencer: bool = false,

    const CUE_HEIGHT = 450;
    const CUE_WIDTH = 60;
    const AIM_BALL_OFFSET = Ball.RADIUS + 2;

    pub const UPGRADE_HILIGHT_COLOR = Color.from_parts(255, 0, 0, 64);
    pub const HOVER_HILIGHT_COLOR = Color.from_parts(0, 0, 255, 64);

    pub fn init(tag: Item.Tag, storage_position: Vec2, storage_rotation: f32) Cue {
        return .{
            .tag = tag,
            .position = storage_position,
            .rotation = storage_rotation,
            .storage_position = storage_position,
            .storage_rotation = storage_rotation,
            .shoot_animation = null,
        };
    }

    pub fn reset_upgrades(self: *Cue) void {
        self.add_heal = 0;
        self.add_damage = 0;
        self.hit_count = 1;
        self.hit_strength = 1.0;
        self.wiggle_ball = false;
        self.scope = false;
        self.silencer = false;
    }

    pub fn hovered(self: Cue, mouse_pos: Vec2) bool {
        const collision_rectangle: Physics.Rectangle = .{
            .size = .{
                .x = CUE_WIDTH,
                .y = CUE_HEIGHT,
            },
        };
        return Physics.point_rectangle_intersect(
            mouse_pos,
            collision_rectangle,
            self.position,
        );
    }

    pub fn add_upgrade(self: *Cue, upgrade: Item.Tag) bool {
        switch (upgrade) {
            .CueHP => {
                self.add_heal += 5;
            },
            .CueDamage => {
                self.add_damage += 5;
            },
            .CueWiggleBall => {
                if (self.wiggle_ball)
                    return false
                else
                    self.wiggle_ball = true;
            },
            .CueScope => {
                if (self.scope)
                    return false
                else
                    self.scope = true;
            },
            .CueSecondBarrel => {
                self.hit_count += 1;
            },
            .CueSilencer => {
                if (self.silencer)
                    return false
                else
                    self.silencer = true;
            },
            .CueRocketBooster => {
                self.hit_strength += 5.0;
            },
            else => unreachable,
        }

        return true;
    }

    pub fn move_storage(self: *Cue) void {
        self.position =
            self.position.add(self.storage_position.sub(self.position).mul_f32(0.2));
        self.rotation += (self.storage_rotation - self.rotation) * 0.2;
    }

    pub fn move_aiming(
        self: *Cue,
        ball_position: Vec2,
        hit_vector: Vec2,
    ) void {
        const hv_len = hit_vector.len();
        if (hv_len == 0.0)
            return;

        const hv_normalized = hit_vector.normalize();
        const cue_postion = ball_position.add(
            hv_normalized
                .mul_f32(AIM_BALL_OFFSET +
                CUE_HEIGHT / 2 +
                hv_len),
        );
        const c = hv_normalized.cross(.{ .y = 1 });
        const d = hv_normalized.dot(.{ .y = 1 });
        const cue_rotation = if (c < 0.0) -std.math.acos(d) else std.math.acos(d);

        self.position =
            self.position.add(cue_postion.sub(self.position).mul_f32(0.2));
        self.rotation += (cue_rotation - self.rotation) * 0.2;
    }

    pub fn move_shoot(
        self: *Cue,
        ball_position: Vec2,
        hit_vector: Vec2,
        dt: f32,
    ) bool {
        if (self.shoot_animation) |*sm| {
            var v3 = self.position.extend(0.0);
            if (sm.update(&v3, dt)) {
                self.shoot_animation = null;
                self.position = v3.xy();
                return true;
            }
            self.position = v3.xy();
        } else {
            const hv_normalized = hit_vector.normalize();
            const end_postion = ball_position.add(
                hv_normalized
                    .mul_f32(AIM_BALL_OFFSET +
                    CUE_HEIGHT / 2),
            );

            self.shoot_animation = .{
                .start_position = self.position.extend(0.0),
                .end_position = end_postion.extend(0.0),
                .duration = 0.2,
                .progress = 0.0,
            };
        }
        return false;
    }

    pub const ToScreenQuadsResult = struct {
        hovered: bool = false,
        upgrade_applied: bool = false,
    };
    pub fn to_screen_quads(
        self: *Cue,
        context: *GlobalContext,
        texture_id: Textures.Texture.Id,
        selected_upgrade: ?Item.Tag,
    ) ToScreenQuadsResult {
        var result: ToScreenQuadsResult = .{};
        const size: Vec2 = .{
            .x = @floatFromInt(context.texture_store.get_texture(texture_id).width),
            .y = @floatFromInt(context.texture_store.get_texture(texture_id).height),
        };

        const is_cue_upgrade = if (selected_upgrade) |si| si.is_cue_upgrade() else false;
        if (is_cue_upgrade) {
            const object: Object2d = .{
                .type = .{ .TextureId = texture_id },
                .tint = UPGRADE_HILIGHT_COLOR,
                .transform = .{
                    .position = self.position.extend(0.0),
                    .rotation = self.rotation,
                },
                .size = size.mul_f32(2.0),
                .options = .{ .with_tint = true },
            };
            object.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
        }

        result.hovered = self.hovered(context.input.mouse_pos_world);
        if (result.hovered) {
            const object: Object2d = .{
                .type = .{ .TextureId = texture_id },
                .tint = HOVER_HILIGHT_COLOR,
                .transform = .{
                    .position = self.position.extend(0.0),
                    .rotation = self.rotation,
                },
                .size = size.mul_f32(1.5),
                .options = .{ .with_tint = true },
            };
            object.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
            if (is_cue_upgrade and context.input.lmb)
                result.upgrade_applied = self.add_upgrade(selected_upgrade.?);
        }

        const object: Object2d = .{
            .type = .{ .TextureId = texture_id },
            .transform = .{
                .position = self.position.extend(0.0),
                .rotation = self.rotation,
            },
            .size = size,
            .options = .{},
        };
        object.to_screen_quad(
            &context.camera,
            &context.texture_store,
            &context.screen_quads,
        );
        return result;
    }
};

pub const Item = struct {
    pub const Tag = enum(u8) {
        Invalid = 0,
        BallSpiky = 1,
        BallHealthy = 2,
        BallArmored = 3,
        BallLight = 4,
        BallHeavy = 5,
        BallGravity = 6,
        BallRunner = 7,
        BallRingOfLight = 8,

        CueHP = 9,
        CueDamage = 10,
        CueWiggleBall = 11,
        CueScope = 12,
        CueSecondBarrel = 13,
        CueSilencer = 14,
        CueRocketBooster = 15,

        CueDefault = 16,
        Cue50CAL = 17,
        CueShotgun = 18,

        pub fn is_ball(self: Tag) bool {
            return self != .Invalid and
                @intFromEnum(self) < @intFromEnum(Tag.CueHP);
        }

        pub fn is_cue_upgrade(self: Tag) bool {
            return self != .Invalid and
                @intFromEnum(Tag.BallRingOfLight) < @intFromEnum(self) and
                @intFromEnum(self) < @intFromEnum(Tag.CueDefault);
        }

        pub fn is_cue(self: Tag) bool {
            return self != .Invalid and
                @intFromEnum(Tag.CueRocketBooster) < @intFromEnum(self);
        }
    };

    pub const Info = struct {
        texture_id: Textures.Texture.Id,
        name: []const u8,
        description: []const u8,
        price: i32,
    };

    pub const NormalDropRate = 0.5;
    pub const RareDropRate = 0.3;
    pub const EpicDropRate = 0.2;

    pub const NormalItems = [_]Tag{
        .BallSpiky,
        .BallHealthy,
        .BallArmored,
        .CueHP,
        .CueDamage,
    };

    pub const RareItems = [_]Tag{
        .BallLight,
        .BallHeavy,
        .BallGravity,
        .BallRunner,
        .CueWiggleBall,
        .CueScope,
        .CueSecondBarrel,
        .CueShotgun,
    };

    pub const EpicItems = [_]Tag{
        .BallRingOfLight,
        .CueSilencer,
        .CueRocketBooster,
        .Cue50CAL,
    };

    pub const Infos = struct {
        infos: [@typeInfo(Tag).Enum.fields.len]Info,

        pub fn get(self: *const Infos, tag: Tag) *const Info {
            log.assert(@src(), @intFromEnum(tag) < @typeInfo(Tag).Enum.fields.len - 1, "", .{});
            return &self.infos[@intFromEnum(tag)];
        }

        pub fn get_mut(self: *Infos, tag: Tag) *Info {
            log.assert(@src(), @intFromEnum(tag) < @typeInfo(Tag).Enum.fields.len - 1, "", .{});
            return &self.infos[@intFromEnum(tag)];
        }
    };
};

pub const CueInventory = struct {
    cues: [MAX_CUE]Cue,
    cues_n: u8,
    owner: Owner,
    selected_index: u8,

    const MAX_CUE = 3;
    const CUE_STORAGE_POSITION_PLAYER: Vec2 = .{ .x = -544.0 };
    const CUE_STORAGE_ROTATION_PLAYER = 0.0;
    const CUE_STORAGE_POSITION_OPPONENT: Vec2 = .{ .x = 544.0 };
    const CUE_STORAGE_ROTATION_OPPONENT = std.math.pi;
    const CUE_STORAGE_WIDTH = 150;
    const CUE_STORAGE_CUE_WIDTH = 50;

    pub fn init(owner: Owner) CueInventory {
        var self: CueInventory = undefined;
        self.owner = owner;

        const p_r = self.cue_position_rotation(0);
        self.cues[0] =
            Cue.init(.CueDefault, p_r[0], p_r[1]);
        self.cues_n = 1;
        self.selected_index = 0;
        return self;
    }

    pub fn cue_position_rotation(self: CueInventory, index: u32) struct { Vec2, f32 } {
        return if (self.owner == .Player)
            .{
                CUE_STORAGE_POSITION_PLAYER.add(
                    .{
                        .x = -CUE_STORAGE_WIDTH / 2 +
                            CUE_STORAGE_CUE_WIDTH / 2 +
                            @as(f32, @floatFromInt(index)) * CUE_STORAGE_CUE_WIDTH,
                    },
                ),
                CUE_STORAGE_ROTATION_PLAYER,
            }
        else
            .{
                CUE_STORAGE_POSITION_OPPONENT.add(
                    .{
                        .x = -CUE_STORAGE_WIDTH / 2 +
                            CUE_STORAGE_CUE_WIDTH / 2 +
                            @as(f32, @floatFromInt(index)) * CUE_STORAGE_CUE_WIDTH,
                    },
                ),
                CUE_STORAGE_ROTATION_OPPONENT,
            };
    }

    pub fn add(self: *CueInventory, cue: Item.Tag) bool {
        log.assert(
            @src(),
            @intFromEnum(Item.Tag.Cue50CAL) <= @intFromEnum(cue),
            "Trying to add item to the cue inventory",
            .{},
        );
        if (self.cues.len == self.cues_n)
            return false;

        const p_r = self.cue_position_rotation(self.cues_n);
        self.cues[self.cues_n] = Cue.init(cue, p_r[0], p_r[1]);
        self.cues_n += 1;
        return true;
    }

    pub fn remove(self: *CueInventory, cue: Item.Tag) void {
        for (self.cues[0..self.cues_n], 0..) |*it, i| {
            if (it == cue) {
                self.cues[i] = self.cues[self.cues_n - 1];
                self.cues_n -= 1;
            }
        }
    }

    pub fn selected(self: *CueInventory) *Cue {
        return &self.cues[self.selected_index];
    }

    pub fn update_and_draw(
        self: *CueInventory,
        context: *GlobalContext,
        selected_upgrade: ?Item.Tag,
    ) bool {
        var upgrade_applied: bool = false;
        for (self.cues[0..self.cues_n], 0..) |*cue, i| {
            if (cue.tag == .Invalid)
                continue;

            const cue_info = context.item_infos.get(cue.tag);
            const r = cue.to_screen_quads(
                context,
                cue_info.texture_id,
                selected_upgrade,
            );

            if (r.hovered and context.input.lmb)
                self.selected_index = @intCast(i);
            upgrade_applied = upgrade_applied or r.upgrade_applied;
        }
        return upgrade_applied;
    }
};

pub const ItemInventory = struct {
    items: [MAX_ITEMS]Item.Tag,
    items_n: u32,

    owner: Owner,
    selected_index: ?u8,
    hovered_index: ?u8,
    dashed_line: UiDashedLine,

    const MAX_ITEMS = 4;
    const ITEMS_POSITION_PLAYER: Vec2 = .{ .x = -100.0, .y = 310.0 };
    const ITEMS_POSITION_OPPONENT: Vec2 = .{ .x = -100.0, .y = -310.0 };
    const ITEMS_WIDTH = 600;
    const ITEM_WIDTH = 100;
    const ITEM_HEIGHT = 100;
    const ITEM_GAP = 50;

    pub const INFO_PANEL_OFFSET: Vec2 = .{ .y = -180.0 };
    pub const INFO_PANEL_SIZE: Vec2 = .{ .x = 280.0, .y = 300.0 };

    pub fn init(owner: Owner) ItemInventory {
        return .{
            .items = undefined,
            .items_n = 0,
            .owner = owner,
            .selected_index = null,
            .hovered_index = null,
            .dashed_line = undefined,
        };
    }

    pub fn item_position(self: ItemInventory, index: u32) Vec2 {
        return if (self.owner == .Player)
            ITEMS_POSITION_PLAYER.add(
                .{
                    .x = -ITEMS_WIDTH / 2 +
                        ITEM_GAP / 2 +
                        ITEM_WIDTH / 2 +
                        @as(f32, @floatFromInt(index)) * (ITEM_WIDTH + ITEM_GAP),
                },
            )
        else
            ITEMS_POSITION_OPPONENT.add(
                .{
                    .x = -ITEMS_WIDTH / 2 +
                        ITEM_GAP / 2 +
                        ITEM_WIDTH / 2 +
                        @as(f32, @floatFromInt(index)) * (ITEM_WIDTH + ITEM_GAP),
                },
            );
    }

    pub fn add(self: *ItemInventory, item: Item.Tag) bool {
        log.assert(
            @src(),
            @intFromEnum(item) < @intFromEnum(Item.Tag.Cue50CAL),
            "Trying to add cue to the item inventory",
            .{},
        );
        if (self.items.len == self.items_n)
            return false;

        self.items[self.items_n] = item;
        self.items_n += 1;
        return true;
    }

    pub fn remove(self: *ItemInventory, item: Item.Tag) void {
        for (self.items[0..self.items_n]) |*it| {
            if (it == item) {
                it.* = .Invalid;
            }
        }
    }

    pub fn item_hovered(self: ItemInventory, item_index: u8, mouse_pos: Vec2) bool {
        const ip = self.item_position(item_index);
        const collision_rectangle: Physics.Rectangle = .{
            .size = .{
                .x = ITEM_WIDTH,
                .y = ITEM_HEIGHT,
            },
        };
        return Physics.point_rectangle_intersect(
            mouse_pos,
            collision_rectangle,
            ip,
        );
    }

    pub fn selected(self: ItemInventory) ?Item.Tag {
        if (self.selected_index) |si| {
            return self.items[si];
        } else {
            return null;
        }
    }

    pub fn item_used(self: *ItemInventory) void {
        if (self.selected_index) |si| {
            self.items[si] = .Invalid;
        }
    }

    pub fn update(
        self: *ItemInventory,
        context: *GlobalContext,
    ) void {
        self.dashed_line.end = context.input.mouse_pos_world;
        var hover_anything: bool = false;
        for (self.items[0..self.items_n], 0..) |item, i| {
            if (item == .Invalid)
                continue;

            if (self.item_hovered(@intCast(i), context.input.mouse_pos_world)) {
                hover_anything = true;
                self.hovered_index = @intCast(i);
                if (!context.state.in_game_shop and context.input.lmb) {
                    self.selected_index = @intCast(i);
                    self.dashed_line.start = self.item_position(@intCast(i));
                }
            }
        }
        if (!hover_anything) {
            self.hovered_index = null;
            if (context.input.lmb)
                self.selected_index = null;
        }
    }

    pub fn to_screen_quads(
        self: ItemInventory,
        context: *GlobalContext,
    ) void {
        for (self.items[0..self.items_n], 0..) |item, i| {
            if (item == .Invalid)
                continue;

            const item_info = context.item_infos.infos[@intFromEnum(item)];
            const ip = self.item_position(@intCast(i));

            var object: Object2d = .{
                .type = .{ .TextureId = item_info.texture_id },
                .transform = .{
                    .position = ip.extend(0.0),
                },
                .options = .{ .no_scale_rotate = true },
            };
            if (self.hovered_index) |hi| {
                if (hi == i) {
                    object.tint = Color.BLUE;
                    object.options.with_tint = true;
                    add_info_panel(context, ip, item_info);
                }
            }
            if (self.selected_index) |si| {
                if (si == i) {
                    object.tint = Color.GREEN;
                    object.options.with_tint = true;
                }
                self.dashed_line.to_screen_quads(context);
            }
            object.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
        }
    }

    fn add_info_panel(
        context: *GlobalContext,
        ip: Vec2,
        item_info: Item.Info,
    ) void {
        const panel_position = if (!context.state.in_game_shop)
            ip.add(INFO_PANEL_OFFSET)
        else
            ip.add(INFO_PANEL_OFFSET.neg());
        const info_panel = UiPanel.init(
            panel_position,
            INFO_PANEL_SIZE,
            Color.GREY,
        );
        info_panel.to_screen_quad(context);

        _ = UiText.to_screen_quads(
            context,
            panel_position.add(.{ .y = -40.0 }),
            32.0,
            "{s}",
            .{item_info.name},
            .{},
        );
        _ = UiText.to_screen_quads(
            context,
            panel_position.add(.{ .y = -20.0 }),
            32.0,
            "{s}",
            .{item_info.description},
            .{},
        );
    }
};

pub const Shop = struct {
    rng: std.rand.DefaultPrng,
    items: [MAX_ITEMS]Item.Tag,
    reroll_cost: i32 = 10,

    selected_item: ?u8 = null,

    pub const CAMERA_IN_GAME_SHOP: Vec2 = .{ .y = 617 };
    const ITEM_PANEL_SIZE: Vec2 = .{ .x = 350.0, .y = 500.0 };
    const ITEM_PANEL_GAP = 30;
    const ITEM_PANEL_DIFF = ITEM_PANEL_SIZE.x + ITEM_PANEL_GAP;

    const ITEM_0_POSITION: Vec2 = CAMERA_IN_GAME_SHOP.add(.{ .x = -400 });
    const ITEM_1_POSITION: Vec2 = CAMERA_IN_GAME_SHOP;
    const ITEM_2_POSITION: Vec2 = CAMERA_IN_GAME_SHOP.add(.{ .x = 400 });

    const TEXT_SIZE_NAME = 40;
    const TEXT_SIZE_DESCRIPTION = 28;
    const TEXT_SIZE_PRICE = 28;

    const UI_BACKGROUND_COLOR = Color.GREY;
    const UI_BACKGROUND_COLOR_PLAYING = Color.GREEN;

    const MAX_ITEMS = 3;
    const REROLL_COST_INC = 1.2;

    pub fn reset(self: *Shop) void {
        self.rng = std.rand.DefaultPrng.init(@intCast(std.time.microTimestamp()));
        self.reroll();
        self.reroll_cost = 10;
        self.selected_item = null;
    }

    pub fn reroll(self: *Shop) void {
        const random = self.rng.random();
        for (&self.items) |*item| {
            const rarity = random.float(f32);
            if (rarity < Item.NormalDropRate) {
                const item_f32 = random.float(f32);
                const item_index: u32 = @intFromFloat(item_f32 * Item.NormalItems.len - 1);
                log.assert(@src(), item_index < Item.NormalItems.len - 1, "", .{});
                item.* = Item.NormalItems[item_index];
            } else if (rarity < Item.RareDropRate) {
                const item_f32 = random.float(f32);
                const item_index: u32 = @intFromFloat(item_f32 * Item.RareItems.len - 1);
                log.assert(@src(), item_index < Item.RareItems.len - 1, "", .{});
                item.* = Item.RareItems[item_index];
            } else {
                const item_f32 = random.float(f32);
                const item_index: u32 = @intFromFloat(item_f32 * Item.EpicItems.len - 1);
                log.assert(@src(), item_index < Item.EpicItems.len - 1, "", .{});
                item.* = Item.EpicItems[item_index];
            }

            log.assert(
                @src(),
                @intFromEnum(item.*) < @typeInfo(Item.Tag).Enum.fields.len,
                "",
                .{},
            );
            log.info(@src(), "reroll item: {any}", .{item.*});
        }
    }

    pub fn remove_selected_item(self: *Shop) void {
        log.assert(
            @src(),
            self.selected_item != null,
            "Trying to remove selected item from a shop, but there is not selected item",
            .{},
        );
        self.items[self.selected_item.?] = .Invalid;
    }

    pub fn draw_item(
        self: Shop,
        context: *GlobalContext,
        index: u8,
    ) bool {
        const item = self.items[index];
        if (item == .Invalid)
            return false;

        const position = CAMERA_IN_GAME_SHOP.add(.{
            .x = -ITEM_PANEL_DIFF / 2.0 * (MAX_ITEMS - 1) +
                @as(f32, @floatFromInt(index)) * ITEM_PANEL_DIFF,
        });

        const collision_rectangle: Physics.Rectangle = .{
            .size = ITEM_PANEL_SIZE,
        };
        const is_hovered = Physics.point_rectangle_intersect(
            context.input.mouse_pos_world,
            collision_rectangle,
            position,
        );

        const color = if (is_hovered) UI_BACKGROUND_COLOR_PLAYING else UI_BACKGROUND_COLOR;
        const item_panel = UiPanel.init(
            position,
            ITEM_PANEL_SIZE,
            color,
        );
        item_panel.to_screen_quad(context);
        const item_info = context.item_infos.get(item);
        const object: Object2d = .{
            .type = .{ .TextureId = item_info.texture_id },
            .transform = .{
                .position = position.extend(0.0),
            },
            .options = .{ .no_scale_rotate = true },
        };
        object.to_screen_quad(
            &context.camera,
            &context.texture_store,
            &context.screen_quads,
        );

        _ = UiText.to_screen_quads(
            context,
            position.add(.{ .y = -200.0 }),
            TEXT_SIZE_NAME,
            "{s}",
            .{item_info.name},
            .{},
        );
        _ = UiText.to_screen_quads(
            context,
            position.add(.{ .y = 0 }),
            TEXT_SIZE_DESCRIPTION,
            "{s}",
            .{item_info.description},
            .{},
        );
        _ = UiText.to_screen_quads(
            context,
            position.add(.{ .y = 200 }),
            TEXT_SIZE_PRICE,
            "{d}",
            .{item_info.price},
            .{},
        );

        return is_hovered;
    }

    pub fn update_and_draw(self: *Shop, context: *GlobalContext) ?Item.Tag {
        var item_clicked: ?Item.Tag = null;
        for (0..self.items.len) |i| {
            const hovered = self.draw_item(
                context,
                @intCast(i),
            );
            if (hovered and context.input.lmb) {
                item_clicked = self.items[i];
                self.selected_item = @intCast(i);
            }
        }

        const want_reroll = UiText.to_screen_quads(
            context,
            CAMERA_IN_GAME_SHOP.add(.{ .y = 300 }),
            32.0,
            "REROLL",
            .{},
            .{ .hilight = true },
        );
        if (want_reroll and context.input.lmb)
            self.reroll();

        return item_clicked;
    }
};
