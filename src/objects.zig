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

pub const Ball = struct {
    id: u8,
    texture_id: Textures.Texture.Id,
    collider: Physics.Circle,
    previous_positions: [PREVIOUS_POSITIONS]Vec2,
    previous_position_index: u32,
    velocity: Vec2,
    friction: f32,
    disabled: bool = false,

    pub const PREVIOUS_POSITIONS = 64;

    pub const trace = Tracing.Measurements(struct {
        update: Tracing.Counter,
        to_object_2d: Tracing.Counter,
        previous_positions_to_object_2d: Tracing.Counter,
    });

    pub fn update(self: *Ball, allocator: Allocator, table: *const Table, balls: []const Ball, dt: f32) void {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        if (self.disabled)
            return;

        const collisions =
            allocator.alloc(Physics.CollisionPoint, table.borders.len + balls.len) catch unreachable;
        var collisions_n: u32 = 0;

        for (balls) |*ball| {
            if (self.id == ball.id)
                continue;
            const collision_point =
                Physics.circle_circle_collision(self.collider, ball.collider);
            if (collision_point) |cp| {
                if (cp.normal.is_valid()) {
                    collisions[collisions_n] = cp;
                    collisions_n += 1;
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
                Physics.circle_rectangle_collision(self.collider, border.collider);
            if (collision_point) |cp| {
                if (cp.normal.is_valid()) {
                    collisions[collisions_n] = cp;
                    collisions_n += 1;
                    log.info(
                        @src(),
                        "collision of ball: {d} and border: {d}",
                        .{ self.id, i },
                    );
                } else {
                    var prev_collider = self.collider;
                    prev_collider.position = self.previous_positions[self.previous_position_index];
                    const ncp =
                        Physics.circle_rectangle_closest_collision_point(
                        prev_collider,
                        border.collider,
                    );
                    if (!ncp.normal.is_valid()) @panic("wtf");

                    collisions[collisions_n] = cp;
                    collisions_n += 1;
                    log.info(
                        @src(),
                        "invalid normal for collision of ball: {d} and border: {d}",
                        .{ self.id, i },
                    );
                }
            }
        }

        if (collisions_n != 0) {
            log.info(
                @src(),
                "resolving {d} collisions for ball: {d}",
                .{ collisions_n, self.id },
            );

            var avg_collision_position: Vec2 = .{};
            var avg_collision_normal: Vec2 = .{};
            for (collisions[0..collisions_n]) |*collision| {
                if (!collision.normal.is_valid())
                    continue;
                avg_collision_position = avg_collision_position.add(collision.position);
                avg_collision_normal = avg_collision_normal.add(collision.normal);
            }
            log.assert(@src(), avg_collision_position.is_valid(), "", .{});
            log.assert(@src(), avg_collision_normal.is_valid(), "", .{});

            avg_collision_position = avg_collision_position.mul_f32(1.0 / @as(f32, @floatFromInt(collisions_n)));
            avg_collision_normal = avg_collision_normal.mul_f32(1.0 / @as(f32, @floatFromInt(collisions_n)));

            const proj = avg_collision_normal.mul_f32(-self.velocity.dot(avg_collision_normal));
            self.velocity = self.velocity.add(proj.mul_f32(2.0));
            const new_positon =
                avg_collision_position.add(avg_collision_normal.mul_f32(self.collider.radius));
            self.previous_positions[self.previous_position_index] = self.collider.position;
            self.previous_position_index += 1;
            self.previous_position_index %= PREVIOUS_POSITIONS;
            self.collider.position = new_positon;
        }

        self.previous_positions[self.previous_position_index] = self.collider.position;
        self.previous_position_index += 1;
        self.previous_position_index %= PREVIOUS_POSITIONS;
        self.collider.position = self.collider.position.add(self.velocity.mul_f32(dt));
        self.velocity = self.velocity.mul_f32(self.friction);

        if (self.collider.position.x < -Table.WIDTH / 2.0 or Table.WIDTH / 2.0 < self.collider.position.x or
            self.collider.position.y < -Table.HEIGTH / 2.0 or Table.HEIGTH / 2.0 < self.collider.position.y)
        {
            self.velocity = .{};
            self.disabled = true;
        }
    }

    pub fn is_hovered(self: Ball, mouse_pos: Vec2) bool {
        return Physics.point_circle_intersect(mouse_pos, self.collider);
    }

    pub fn to_object_2d(self: Ball) Object2d {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        return .{
            .type = .{ .TextureId = self.texture_id },
            .transform = .{
                .position = self.collider.position.extend(0.0),
            },
            .size = .{
                .x = 40.0,
                .y = 40.0,
            },
            // .options = .{ .draw_aabb = true, .no_scale_rotate = true },
            .options = .{ .draw_aabb = true },
        };
    }

    pub fn previous_positions_to_object_2d(self: Ball) [PREVIOUS_POSITIONS]Object2d {
        const trace_start = trace.start();
        defer trace.end(@src(), trace_start);

        var pp_objects: [PREVIOUS_POSITIONS]Object2d = undefined;
        var pp_index = self.previous_position_index;
        const id: u32 = @intCast(self.id);
        const base_color = Color.from_parts(
            @intCast((id * 64) % 255),
            @intCast((id * 17) % 255),
            @intCast((id * 33) % 255),
            0,
        );
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
                .size = .{
                    .x = 40.0,
                    .y = 40.0,
                },
                // .options = .{ .with_tint = true, .draw_aabb = true, .no_scale_rotate = true },
                .options = .{ .with_tint = true },
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
        collider: Physics.Rectangle,
    };

    pub const Pocket = struct {
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
                    .collider = .{
                        .position = .{ .x = -WIDTH / 2 + BORDER / 2 },
                        .size = .{ .x = BORDER, .y = HEIGTH - POCKET_GAP * 3.0 },
                    },
                },
                // right
                .{
                    .collider = .{
                        .position = .{ .x = WIDTH / 2 - BORDER / 2 },
                        .size = .{ .x = BORDER, .y = HEIGTH - POCKET_GAP * 3.0 },
                    },
                },
                // bottom left
                .{
                    .collider = .{
                        .position = .{ .x = -WIDTH / 4 + POCKET_GAP / 2, .y = -HEIGTH / 2 + BORDER / 2 },
                        .size = .{ .x = WIDTH / 2 - POCKET_GAP * 2, .y = BORDER },
                    },
                },
                // bottom right
                .{
                    .collider = .{
                        .position = .{ .x = WIDTH / 4 - POCKET_GAP / 2, .y = -HEIGTH / 2 + BORDER / 2 },
                        .size = .{ .x = WIDTH / 2 - POCKET_GAP * 2, .y = BORDER },
                    },
                },

                // top left
                .{
                    .collider = .{
                        .position = .{ .x = -WIDTH / 4 + POCKET_GAP / 2, .y = HEIGTH / 2 - BORDER / 2 },
                        .size = .{ .x = WIDTH / 2 - POCKET_GAP * 2, .y = BORDER },
                    },
                },
                // top right
                .{
                    .collider = .{
                        .position = .{ .x = WIDTH / 4 - POCKET_GAP / 2, .y = HEIGTH / 2 - BORDER / 2 },
                        .size = .{ .x = WIDTH / 2 - POCKET_GAP * 2, .y = BORDER },
                    },
                },
            },
            .pockets = .{
                // bot left
                .{
                    .collider = .{
                        .position = .{
                            .x = -WIDTH / 2 + POCKET_CORNER_OFFSET,
                            .y = -HEIGTH / 2 + POCKET_CORNER_OFFSET,
                        },
                        .radius = POCKET_RADIUS,
                    },
                },
                // bot middle
                .{
                    .collider = .{
                        .position = .{ .y = -HEIGTH / 2 },
                        .radius = POCKET_RADIUS,
                    },
                },
                // bot right
                .{
                    .collider = .{
                        .position = .{
                            .x = WIDTH / 2 - POCKET_CORNER_OFFSET,
                            .y = -HEIGTH / 2 + POCKET_CORNER_OFFSET,
                        },
                        .radius = POCKET_RADIUS,
                    },
                },
                // top left
                .{
                    .collider = .{
                        .position = .{
                            .x = -WIDTH / 2 + POCKET_CORNER_OFFSET,
                            .y = HEIGTH / 2 - POCKET_CORNER_OFFSET,
                        },
                        .radius = POCKET_RADIUS,
                    },
                },
                // top middle
                .{
                    .collider = .{
                        .position = .{ .y = HEIGTH / 2 },
                        .radius = POCKET_RADIUS,
                    },
                },
                // tob right
                .{
                    .collider = .{
                        .position = .{
                            .x = WIDTH / 2 - POCKET_CORNER_OFFSET,
                            .y = HEIGTH / 2 - POCKET_CORNER_OFFSET,
                        },
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
            const position = camera_controller.transform(border.collider.position.extend(0.0));
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
            const position = camera_controller.transform(pocket.collider.position.extend(0.0));
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
