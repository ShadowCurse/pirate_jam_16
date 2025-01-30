const std = @import("std");
const Allocator = std.mem.Allocator;

const stygian = @import("stygian_runtime");
const log = stygian.log;

const _runtime = @import("runtime.zig");
const GlobalContext = _runtime.GlobalContext;

const Tracing = stygian.tracing;
const Physics = stygian.physics;
const Color = stygian.color.Color;
const Textures = stygian.textures;

const _math = stygian.math;
const Vec2 = _math.Vec2;

const _objects = @import("objects.zig");
const GravityParticleEffect = _objects.Ball.GravityParticleEffect;
const RingOfLightParticleEffect = _objects.Ball.RingOfLightParticleEffect;

pub const trace = Tracing.Measurements(struct {
    update: Tracing.Counter,
});

balls: [PLAYER_BALLS + OPPONENT_BALLS]Ball,
borders: [6]Border,
pockets: [6]Pocket,

const Self = @This();

pub const PLAYER_BALLS = 15;
pub const OPPONENT_BALLS = 15;

pub const Ball = struct {
    body: Physics.Body,
    collider: Physics.Circle,
    state: State,

    pub const RADIUS = 10;

    pub const State = packed struct(u32) {
        dead: bool = false,
        pocketted: bool = false,
        stationary: bool = true,
        antisocial: bool = false,
        gravity: bool = false,
        runner: bool = false,
        ring_of_light: bool = false,
        ghost: bool = false,
        belongs_to_player: bool = false,
        _: u23 = 0,

        pub fn any(self: State) bool {
            return self.dead or self.pocketted or self.stationary;
        }

        pub fn playable(self: State) bool {
            return !self.dead and !self.pocketted;
        }
    };

    pub fn init(position: Vec2, radius: f32, belongs_to_player: bool) Ball {
        return .{
            .body = .{
                .position = position,
                .restitution = 1.0,
                .friction = 0.7,
                .inv_mass = 1.0,
            },
            .collider = .{
                .radius = radius,
            },
            .state = .{
                .belongs_to_player = belongs_to_player,
            },
        };
    }
};

pub const Border = struct {
    body: Physics.Body,
    collider: Physics.Rectangle,
};

pub const Pocket = struct {
    body: Physics.Body,
    collider: Physics.Circle,
};

pub const Collision = struct {
    collision: Physics.CollisionPoint,
    ball_id: u8,
    entity_2: Type,

    pub const Tag = enum {
        BallRingOfLight,
        Ball,
        Border,
        Pocket,
    };

    pub const Type = union(Tag) {
        BallRingOfLight: u8,
        Ball: u8,
        Border: u8,
        Pocket: u8,
    };
};

pub fn init(self: *Self) void {
    layout_balls(
        self.balls[0..PLAYER_BALLS],
        .{ .x = -200.0 },
        Vec2.NEG_X,
        true,
    );
    layout_balls(
        self.balls[PLAYER_BALLS..],
        .{ .x = 200.0 },
        Vec2.X,
        false,
    );
    self.layout_table();
}

// Layout balls in a triangle with a tip beeing the top of the top ball, the
// direction is pointing into the triangle.
pub fn layout_balls(
    balls: []Ball,
    tip_position: Vec2,
    direction: Vec2,
    belongs_to_player: bool,
) void {
    const GAP = 3.0;
    // rotate direction 30 degrees for balls in one layer
    // -30 to get to the next layer
    const angle = std.math.pi / 6.0;
    const direction_next = direction.rotate(angle);
    const direction_next_layer = direction.rotate(-angle);
    var origin_position: Vec2 = tip_position.add(direction.mul_f32(Ball.RADIUS));
    var index: u8 = 0;
    for (0..5) |layer| {
        for (0..(5 - layer)) |i| {
            const position =
                origin_position
                .add(direction_next.mul_f32(@as(f32, @floatFromInt(i)) * (Ball.RADIUS * 2.0 + GAP)));
            balls[index] = Ball.init(position, Ball.RADIUS, belongs_to_player);
            index += 1;
        }
        origin_position = origin_position.add(direction_next_layer.mul_f32(Ball.RADIUS * 2.0 + GAP));
    }
}

pub fn layout_table(self: *Self) void {
    const WIDTH = 998;
    const HEIGTH = 545;
    const BORDER = 36;
    const POCKET_GAP = 52;
    const POCKET_CENTER_GAP = 42;
    const POCKET_RADIUS = 35;
    const POCKET_CORNER_OFFSET = 15;

    self.borders = .{
        // left
        .{
            .body = .{
                .position = .{ .x = -WIDTH / 2 + BORDER / 2 },
            },
            .collider = .{
                .size = .{ .x = BORDER, .y = HEIGTH - POCKET_GAP * 2.0 },
            },
        },
        // right
        .{
            .body = .{
                .position = .{ .x = WIDTH / 2 - BORDER / 2 },
            },
            .collider = .{
                .size = .{ .x = BORDER, .y = HEIGTH - POCKET_GAP * 2.0 },
            },
        },
        // bottom left
        .{
            .body = .{
                .position = .{
                    .x = (-POCKET_CENTER_GAP / 2 - WIDTH / 2 + POCKET_GAP) / 2,
                    .y = -HEIGTH / 2 + BORDER / 2,
                },
            },
            .collider = .{
                .size = .{
                    .x = WIDTH / 2 - POCKET_GAP - POCKET_CENTER_GAP / 2,
                    .y = BORDER,
                },
            },
        },
        // bottom right
        .{
            .body = .{
                .position = .{
                    .x = (POCKET_CENTER_GAP / 2 + WIDTH / 2 - POCKET_GAP) / 2,
                    .y = -HEIGTH / 2 + BORDER / 2,
                },
            },
            .collider = .{
                .size = .{
                    .x = WIDTH / 2 - POCKET_GAP - POCKET_CENTER_GAP / 2,
                    .y = BORDER,
                },
            },
        },

        // top left
        .{
            .body = .{
                .position = .{
                    .x = (-POCKET_CENTER_GAP / 2 - WIDTH / 2 + POCKET_GAP) / 2,
                    .y = HEIGTH / 2 - BORDER / 2,
                },
            },
            .collider = .{
                .size = .{
                    .x = WIDTH / 2 - POCKET_GAP - POCKET_CENTER_GAP / 2,
                    .y = BORDER,
                },
            },
        },
        // top right
        .{
            .body = .{
                .position = .{
                    .x = (POCKET_CENTER_GAP / 2 + WIDTH / 2 - POCKET_GAP) / 2,
                    .y = HEIGTH / 2 - BORDER / 2,
                },
            },
            .collider = .{
                .size = .{
                    .x = WIDTH / 2 - POCKET_GAP - POCKET_CENTER_GAP / 2,
                    .y = BORDER,
                },
            },
        },
    };
    self.pockets = .{
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
    };
}

pub const UpdateResult = struct {
    collisions: []Collision,
    distances: []f32,
};
pub fn update(self: *Self, context: *GlobalContext) UpdateResult {
    const trace_start = trace.start();
    defer trace.end(@src(), trace_start);

    const ITERATIONS = 4;

    const dt = context.dt / ITERATIONS;
    var collisions = std.ArrayList(Collision).init(context.alloc());
    var distances = context.alloc().alloc(f32, self.balls.len) catch unreachable;
    @memset(distances, 0);
    var prev_collisions_n: usize = 0;
    for (0..ITERATIONS) |_| {
        for (&self.balls, 0..) |*ball, i| {
            if (!ball.state.playable())
                continue;
            ball.body.acceleration = ball.body.velocity.mul_f32(ball.body.friction).neg();
            const ball_new_position = ball.body.acceleration.mul_f32(0.5 * dt * dt)
                .add(ball.body.velocity.mul_f32(dt))
                .add(ball.body.position);
            distances[i] += ball_new_position.sub(ball.body.position).len();
            ball.body.position = ball_new_position;
            ball.body.velocity = ball.body.velocity.add(ball.body.acceleration.mul_f32(dt));

            if (ball.body.velocity.len_squared() < 0.1) {
                ball.body.velocity = .{};
                ball.state.stationary = true;
            } else {
                ball.state.stationary = false;
            }
        }

        for (self.balls[0 .. self.balls.len - 1], 0..) |*ball_1, i| {
            if (!ball_1.state.playable())
                continue;
            for (self.balls[i + 1 .. self.balls.len], i + 1..) |*ball_2, j| {
                if (!ball_2.state.playable())
                    continue;

                const to_ball_2 = ball_2.body.position.sub(ball_1.body.position);
                const to_ball_2_len_sq = to_ball_2.len_squared();
                if (ball_1.state.gravity) {
                    const RANGE = GravityParticleEffect.RADIUS * GravityParticleEffect.RADIUS;
                    const FORCE = GravityParticleEffect.FORCE;
                    if (to_ball_2_len_sq < RANGE) {
                        ball_2.body.velocity =
                            ball_2.body.velocity
                            .add(to_ball_2.mul_f32(1.0 / to_ball_2_len_sq *
                            (RANGE - to_ball_2_len_sq) / RANGE * FORCE));
                    }
                }
                if (ball_1.state.ring_of_light) {
                    const RANGE = RingOfLightParticleEffect.RADIUS *
                        RingOfLightParticleEffect.RADIUS;
                    if (to_ball_2_len_sq < RANGE) {
                        collisions.append(.{
                            .collision = undefined,
                            .ball_id = @intCast(i),
                            .entity_2 = .{ .BallRingOfLight = @intCast(j) },
                        }) catch unreachable;
                    }
                }
                const collision_point =
                    Physics.circle_circle_collision(
                    ball_1.collider,
                    ball_1.body.position,
                    ball_2.collider,
                    ball_2.body.position,
                );
                if (collision_point) |cp| {
                    if (ball_1.state.ghost) {
                        if (ball_1.state.belongs_to_player == ball_2.state.belongs_to_player)
                            continue
                        else
                            ball_1.state.ghost = false;
                    }

                    collisions.append(.{
                        .collision = cp,
                        .ball_id = @intCast(i),
                        .entity_2 = .{ .Ball = @intCast(j) },
                    }) catch unreachable;
                }
            }
        }
        for (&self.balls, 0..) |*ball, i| {
            for (&self.borders, 0..) |*border, j| {
                const collision_point =
                    Physics.circle_rectangle_collision(
                    ball.collider,
                    ball.body.position,
                    border.collider,
                    border.body.position,
                );
                if (collision_point) |cp| {
                    collisions.append(.{
                        .collision = cp,
                        .ball_id = @intCast(i),
                        .entity_2 = .{ .Border = @intCast(j) },
                    }) catch unreachable;
                }
            }
            for (&self.pockets, 0..) |*pocket, j| {
                const collision_point =
                    Physics.circle_circle_collision(
                    ball.collider,
                    ball.body.position,
                    pocket.collider,
                    pocket.body.position,
                );
                if (collision_point) |cp| {
                    collisions.append(.{
                        .collision = cp,
                        .ball_id = @intCast(i),
                        .entity_2 = .{ .Pocket = @intCast(j) },
                    }) catch unreachable;
                }
            }
        }

        for (collisions.items[prev_collisions_n..]) |*collision| {
            const ball = &self.balls[collision.ball_id];
            switch (collision.entity_2) {
                .BallRingOfLight => {},
                .Ball => |ball_2_id| {
                    const ball_2 = &self.balls[ball_2_id];
                    Physics.apply_collision_impulse(
                        &ball.body,
                        &ball_2.body,
                        collision.collision,
                    );
                    if (ball.state.antisocial) {
                        ball.body.velocity = ball.body.velocity.mul_f32(1.2);
                    }
                },
                .Border => |border_id| {
                    const border = &self.borders[border_id];
                    Physics.apply_collision_impulse_static(
                        &ball.body,
                        &border.body,
                        collision.collision,
                    );
                },
                .Pocket => |_| {},
            }
        }
        prev_collisions_n = collisions.items.len;
    }
    return .{
        .collisions = collisions.items,
        .distances = distances,
    };
}

pub fn borders_to_screen_quads(
    self: Self,
    context: *GlobalContext,
) void {
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
    self: Self,
    context: *GlobalContext,
) void {
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
