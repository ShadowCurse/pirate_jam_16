const stygian = @import("stygian_runtime");
const log = stygian.log;

const Physics = stygian.physics;
const Textures = stygian.textures;
const Color = stygian.color.Color;
const Events = stygian.platform.event;
const ScreenQuads = stygian.screen_quads;
const CameraController2d = stygian.camera.CameraController2d;

const _math = stygian.math;
const Vec2 = _math.Vec2;

const runtime = @import("runtime.zig");
const InputState = runtime.InputState;

const _objects = @import("objects.zig");
const Ball = _objects.Ball;
const Table = _objects.Table;

const _animations = @import("animations.zig");
const BallAnimations = _animations.BallAnimations;

turn_owner: Owner,
turn_taken: bool,

player_hp: i32,
player_hp_overhead: i32,

opponent_hp: i32,
opponent_hp_overhead: i32,

balls: [MAX_BALLS]Ball,
table: Table,
ball_animations: BallAnimations,

selected_ball: ?u32,
mouse_drag: MouseDrag,

const MAX_BALLS = 20;

pub const Owner = enum(u1) {
    Player,
    Opponent,
};

const Self = @This();

pub fn init(
    self: *Self,
    texture_ball: Textures.Texture.Id,
    texture_poll_table: Textures.Texture.Id,
) void {
    self.restart();
    for (&self.balls) |*ball| {
        ball.texture_id = texture_ball;
    }
    self.table = Table.init(texture_poll_table);
    self.selected_ball = null;
    self.mouse_drag = .{};
}

pub fn restart(self: *Self) void {
    self.turn_owner = .Player;
    self.turn_taken = false;

    self.player_hp = 100;
    self.player_hp_overhead = 0;
    self.opponent_hp = 100;
    self.opponent_hp_overhead = 0;

    for (&self.balls, 0..) |*ball, i| {
        const row: f32 = @floatFromInt(@divFloor(i, 4));
        const column: f32 = @floatFromInt(i % 4);
        const position: Vec2 = .{
            .x = -60.0 * 2 + column * 60.0 + 30.0,
            .y = -60.0 * 2 + row * 60.0 + 30.0,
        };
        const id: u8 = @intCast(i);
        const color = if (i < 10) Color.GREEN else Color.RED;
        ball.id = id;
        ball.color = color;

        ball.owner = if (i < 10) .Player else .Opponent;
        ball.hp = 10;
        ball.max_hp = 10;
        ball.damage = 1;
        ball.heal = 1;

        ball.body = .{
            .position = position,
            .velocity = .{},
            .restitution = 1.0,
            .friction = 0.95,
            .inv_mass = 1.0,
        };
        ball.collider = .{
            .radius = 20.0,
        };
        ball.previous_positions = [_]Vec2{position} ** 64;
        ball.previous_position_index = 0;
        ball.disabled = false;
    }
    self.ball_animations = .{};
}

pub fn update(
    self: *Self,
    events: []const Events.Event,
    input_state: *const InputState,
    dt: f32,
) void {
    if (!self.turn_taken) {
        if (self.mouse_drag.update(events, dt)) |v| {
            if (self.selected_ball) |sb| {
                const ball = &self.balls[sb];
                ball.body.velocity = ball.body.velocity.add(v);
                self.turn_taken = true;
            }
        }
        var new_ball_selected: bool = false;
        for (&self.balls) |*ball| {
            if (ball.disabled)
                continue;

            if (ball.owner == self.turn_owner and
                ball.is_hovered(input_state.mouse_pos_world) and
                input_state.lmb)
            {
                new_ball_selected = true;
                self.selected_ball = ball.id;
            }
        }
        if (!new_ball_selected and input_state.lmb)
            self.selected_ball = null;
    }

    for (&self.balls) |*ball| {
        if (ball.disabled)
            continue;
        ball.update(&self.table, &self.balls, self.turn_owner, dt);
    }

    var new_player_hp: i32 = 0;
    var player_overheal: i32 = 0;
    var new_opponent_hp: i32 = 0;
    var opponent_overheal: i32 = 0;
    for (&self.balls) |*ball| {
        if (ball.disabled)
            continue;

        switch (ball.owner) {
            .Player => {
                if (ball.max_hp < ball.hp) {
                    const ball_overheal = ball.hp - ball.max_hp;
                    ball.hp = ball.max_hp;
                    player_overheal += ball_overheal;
                }
                new_player_hp += ball.hp;
            },
            .Opponent => {
                if (ball.max_hp < ball.hp) {
                    const ball_overheal = ball.hp - ball.max_hp;
                    ball.hp = ball.max_hp;
                    opponent_overheal += ball_overheal;
                }
                new_opponent_hp += ball.hp;
            },
        }

        for (&self.table.pockets) |*pocket| {
            const collision_point =
                Physics.circle_circle_collision(
                ball.collider,
                ball.body.position,
                pocket.collider,
                pocket.body.position,
            );
            if (collision_point) |_| {
                if (self.selected_ball == ball.id)
                    self.selected_ball = null;
                ball.disabled = true;
                self.ball_animations.add(ball, pocket.body.position, 1.0);
            }
        }
    }
    self.player_hp = new_player_hp;
    self.player_hp_overhead += player_overheal;
    self.opponent_hp = new_opponent_hp;
    self.opponent_hp_overhead += opponent_overheal;

    var disabled_or_stationary: u8 = 0;
    for (&self.balls) |*ball| {
        if (ball.disabled or ball.stationary) {
            disabled_or_stationary += 1;
        }
    }
    if (self.turn_taken and disabled_or_stationary == self.balls.len) {
        self.turn_owner = if (self.turn_owner == .Player) .Opponent else .Player;
        self.turn_taken = false;
        self.selected_ball = null;
    }

    self.ball_animations.update(&self.balls, dt);
}

pub fn draw(
    self: *Self,
    camera_controller: *const CameraController2d,
    texture_store: *const Textures.Store,
    screen_quads: *ScreenQuads,
) void {
    self.table.to_screen_quad(
        camera_controller,
        texture_store,
        screen_quads,
    );
    self.table.borders_to_screen_quads(
        camera_controller,
        screen_quads,
    );
    self.table.pockets_to_screen_quads(
        camera_controller,
        screen_quads,
    );

    for (&self.balls) |*ball| {
        const bo = ball.to_object_2d();
        bo.to_screen_quad(
            camera_controller,
            texture_store,
            screen_quads,
        );
        if (self.selected_ball) |sb| {
            if (ball.id == sb) {
                const pbo = ball.previous_positions_to_object_2d();
                for (&pbo) |pb| {
                    pb.to_screen_quad(
                        camera_controller,
                        texture_store,
                        screen_quads,
                    );
                }
            }
        }
    }
}

const MouseDrag = struct {
    active: bool = false,
    sensitivity: f32 = 100.0,
    v: Vec2 = .{},

    pub fn update(
        self: *MouseDrag,
        events: []const Events.Event,
        dt: f32,
    ) ?Vec2 {
        for (events) |event| {
            switch (event) {
                .Mouse => |mouse| {
                    switch (mouse) {
                        .Button => |button| {
                            if (button.key == .RMB) {
                                if (button.type == .Pressed) {
                                    self.active = true;
                                } else {
                                    if (self.active) {
                                        const v = self.v;
                                        self.v = .{};
                                        self.active = false;
                                        return v;
                                    }
                                }
                            }
                        },
                        .Motion => |motion| {
                            if (self.active) {
                                self.v = self.v.sub(.{
                                    .x = @as(f32, @floatFromInt(motion.x)) *
                                        self.sensitivity * dt,
                                    .y = @as(f32, @floatFromInt(motion.y)) *
                                        self.sensitivity * dt,
                                });
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
        return null;
    }
};
