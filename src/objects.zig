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

const runtime = @import("runtime.zig");
const InputState = runtime.InputState;

const _game = @import("game.zig");
const Owner = _game.Owner;

const _animations = @import("animations.zig");
const SmoothStepAnimation = _animations.SmoothStepAnimation;

const _ui = @import("ui.zig");
const UiText = _ui.UiText;
const UiPanel = _ui.UiPanel;

pub const Ball = struct {
    id: u8,
    texture_id: Textures.Texture.Id,
    color: Color,

    owner: Owner,
    hp: i32,
    max_hp: i32,
    damage: i32,
    heal: i32,

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
            .hp = 10,
            .max_hp = 10,
            .damage = 1,
            .heal = 1,
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
                        const d = @min(self.damage, ball.hp);
                        self.hp += d;
                        ball.hp -= d;
                    }
                } else {
                    if (ball.owner == turn_owner) {
                        const d = @min(ball.damage, self.hp);
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

    pub fn to_object_2d(self: Ball) Object2d {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        return .{
            .type = .{ .TextureId = self.texture_id },
            .tint = self.color,
            .transform = .{
                .position = self.body.position.extend(0.0),
            },
            .options = .{ .draw_aabb = true, .no_scale_rotate = true, .with_tint = true },
        };
    }

    pub fn hp_to_screen_quads(
        self: Ball,
        allocator: Allocator,
        font: *const Font,
        camera_controller: *const CameraController2d,
        screen_quads: *ScreenQuads,
    ) void {
        const hp = std.fmt.allocPrint(
            allocator,
            "{d}",
            .{self.hp},
        ) catch unreachable;
        const text = Text.init(
            font,
            hp,
            HP_TEXT_SIZE,
            self.body.position.add(.{ .y = HP_TEXT_SIZE / 4.0 }).extend(0.0),
            0.0,
            .{},
            .{ .dont_clip = true },
        );
        text.to_screen_quads_world_space(allocator, camera_controller, screen_quads);
    }

    pub fn info_panel_to_screen_quads(
        self: Ball,
        allocator: Allocator,
        input_state: *const InputState,
        font: *const Font,
        camera_controller: *const CameraController2d,
        screen_quads: *ScreenQuads,
    ) bool {
        const panel_position = self.body.position.add(INFO_PANEL_OFFSET);
        const info_panel = UiPanel.init(
            panel_position,
            INFO_PANEL_SIZE,
            Color.GREY,
        );
        info_panel.to_screen_quad(camera_controller, screen_quads);

        {
            const hp = std.fmt.allocPrint(
                allocator,
                "HP: {d}",
                .{self.hp},
            ) catch unreachable;
            const text = Text.init(
                font,
                hp,
                HP_TEXT_SIZE,
                panel_position.add(.{ .y = -40.0 }).extend(0.0),
                0.0,
                .{},
                .{ .dont_clip = true },
            );
            text.to_screen_quads_world_space(allocator, camera_controller, screen_quads);
        }

        {
            const hp = std.fmt.allocPrint(
                allocator,
                "Damage: {d}",
                .{self.damage},
            ) catch unreachable;
            const text = Text.init(
                font,
                hp,
                HP_TEXT_SIZE,
                panel_position.add(.{ .y = -20.0 }).extend(0.0),
                0.0,
                .{},
                .{ .dont_clip = true },
            );
            text.to_screen_quads_world_space(allocator, camera_controller, screen_quads);
        }

        const refill = std.fmt.allocPrint(
            allocator,
            "Refill ball HP with {d} overhead HP",
            .{self.max_hp - self.hp},
        ) catch unreachable;
        const refill_text = UiText.init(
            panel_position.add(.{ .y = 40.0 }),
            font,
            refill,
            25.0,
        );
        return refill_text.to_screen_quads_world_space(
            allocator,
            input_state.mouse_pos_world,
            camera_controller,
            screen_quads,
        );
    }

    pub fn previous_positions_to_object_2d(self: Ball) [PREVIOUS_POSITIONS]Object2d {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        var pp_objects: [PREVIOUS_POSITIONS]Object2d = undefined;
        var pp_index = self.previous_position_index;
        var base_color = self.color;
        base_color.format.a = 0;
        for (&pp_objects, 0..) |*o, i| {
            const previous_position = self.previous_positions[pp_index];
            var color = base_color;
            color.format.a = @as(u8, @intCast(i)) * 2;
            o.* = .{
                .type = .{ .TextureId = self.texture_id },
                .tint = color,
                .transform = .{
                    .position = previous_position.extend(0.0),
                },
                .options = .{ .no_scale_rotate = true, .with_tint = true },
            };
            pp_index += 1;
            pp_index %= PREVIOUS_POSITIONS;
        }
        return pp_objects;
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
        camera_controller: *const CameraController2d,
        texture_store: *const Textures.Store,
        screen_quads: *ScreenQuads,
    ) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        const table_object: Object2d = .{
            .type = .{ .TextureId = self.texture_id },
            .transform = .{},
            .size = .{
                .x = @floatFromInt(texture_store.get_texture(self.texture_id).width),
                .y = @floatFromInt(texture_store.get_texture(self.texture_id).height),
            },
            .options = .{ .no_alpha_blend = true },
        };
        table_object.to_screen_quad(camera_controller, texture_store, screen_quads);
    }

    pub fn borders_to_screen_quads(
        self: Table,
        camera_controller: *const CameraController2d,
        screen_quads: *ScreenQuads,
    ) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        const border_color = Color.from_parts(255.0, 255.0, 255.0, 64.0);
        for (&self.borders) |*border| {
            const position = camera_controller.transform(border.body.position.extend(0.0));
            screen_quads.add_quad(.{
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
        camera_controller: *const CameraController2d,
        screen_quads: *ScreenQuads,
    ) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        const pocket_color = Color.from_parts(64.0, 255.0, 64.0, 64.0);
        for (&self.pockets) |*pocket| {
            const position = camera_controller.transform(pocket.body.position.extend(0.0));
            const size: Vec2 = .{
                .x = pocket.collider.radius * 2.0,
                .y = pocket.collider.radius * 2.0,
            };
            screen_quads.add_quad(.{
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
    texture_id: Textures.Texture.Id,
    position: Vec2,
    rotation: f32,
    storage_index: u8,
    storage_position: Vec2,
    state: State,

    const CUE_HEIGHT = 450;
    const STORAGE_POSITION: Vec2 = .{ .x = 650.0 };
    const STORAGE_WIDTH = 120;
    const STORAGE_CUE_WIDTH = 60;
    const AIM_BALL_OFFSET = Ball.RADIUS + 2;

    pub const State = enum {
        Storage,
        Aiming,
        Playing,
    };

    pub fn init(texture_id: Textures.Texture.Id, storage_index: u8) Cue {
        const storage_position = STORAGE_POSITION.add(
            .{ .x = -STORAGE_WIDTH + @as(f32, @floatFromInt(storage_index)) * STORAGE_CUE_WIDTH },
        );
        return .{
            .texture_id = texture_id,
            .position = storage_position,
            .rotation = 0.0,
            .storage_index = storage_index,
            .storage_position = storage_position,
            .state = .Storage,
        };
    }

    pub fn update(
        self: *Cue,
        ball_position: ?*const Vec2,
        hit_vector: ?*const Vec2,
    ) void {
        switch (self.state) {
            .Storage => {
                self.position =
                    self.position.add(self.storage_position.sub(self.position).mul_f32(0.2));
                self.rotation -= self.rotation * 0.2;
            },
            .Aiming => {
                const bp = ball_position.?;
                const hv = hit_vector.?.neg();

                const hv_len = hv.len();
                if (hv_len == 0.0)
                    return;

                const hv_normalized = hv.normalize();
                const cue_postion = bp.add(
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
            },
            .Playing => {},
        }
    }

    pub fn to_screen_quad(
        self: Cue,
        camera_controller: *const CameraController2d,
        texture_store: *const Textures.Store,
        screen_quads: *ScreenQuads,
    ) void {
        const object: Object2d = .{
            .type = .{ .TextureId = self.texture_id },
            .transform = .{
                .position = self.position.extend(0.0),
                .rotation = self.rotation,
            },
            .size = .{
                .x = @floatFromInt(texture_store.get_texture(self.texture_id).width),
                .y = @floatFromInt(texture_store.get_texture(self.texture_id).height),
            },
            .options = .{},
        };
        object.to_screen_quad(camera_controller, texture_store, screen_quads);
    }
};
