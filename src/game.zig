const std = @import("std");
const Allocator = std.mem.Allocator;

const stygian = @import("stygian_runtime");
const log = stygian.log;

const Font = stygian.font;
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
const Cue = _objects.Cue;

const _animations = @import("animations.zig");
const BallAnimations = _animations.BallAnimations;

turn_owner: Owner,
turn_taken: bool,

player_hp: i32,
player_hp_overhead: i32,

opponent_hp: i32,
opponent_hp_overhead: i32,

texture_ball: Textures.Texture.Id,
balls: [MAX_BALLS]Ball,
ball_animations: BallAnimations,
table: Table,
cue: Cue,

selected_ball: ?u32,
is_aiming: bool,

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
    texture_cue: Textures.Texture.Id,
) void {
    self.texture_ball = texture_ball;
    self.restart();
    self.table = Table.init(texture_poll_table);
    self.cue = Cue.init(texture_cue, 1);
}

pub fn restart(self: *Self) void {
    self.turn_owner = .Player;
    self.turn_taken = false;
    self.selected_ball = null;
    self.is_aiming = false;

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
        const color: Color = if (i < 10) Color.GREEN else Color.RED;
        const owner: Owner = if (i < 10) .Player else .Opponent;
        ball.* = Ball.init(id, color, self.texture_ball, owner, position);
    }
    self.ball_animations = .{};
}

pub fn update(
    self: *Self,
    input_state: *const InputState,
    dt: f32,
) void {
    if (!self.turn_taken) {
        if (!self.is_aiming) {
            self.is_aiming = self.selected_ball != null and input_state.rmb;
        } else {
            if (self.selected_ball) |sb| {
                const ball = &self.balls[sb];
                const hit_vector = input_state.mouse_pos_world.sub(ball.body.position);
                self.cue.move_aiming(ball.body.position, hit_vector);

                if (!input_state.rmb) {
                    // We hit in the opposite direction of the "to_mouse" direction
                    ball.body.velocity = ball.body.velocity.add(hit_vector.neg());
                    self.turn_taken = true;
                    self.is_aiming = false;
                }
            } else {
                self.is_aiming = false;
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
    } else {
        self.cue.move_storage();

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
        if (disabled_or_stationary == self.balls.len) {
            self.turn_owner = if (self.turn_owner == .Player) .Opponent else .Player;
            self.turn_taken = false;
            self.selected_ball = null;
        }

        self.ball_animations.update(&self.balls, dt);
    }
}

pub fn draw(
    self: *Self,
    allocator: Allocator,
    input_state: *const InputState,
    camera_controller: *const CameraController2d,
    font: *const Font,
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
    self.cue.to_screen_quad(camera_controller, texture_store, screen_quads);

    for (&self.balls) |*ball| {
        const bo = ball.to_object_2d();
        bo.to_screen_quad(
            camera_controller,
            texture_store,
            screen_quads,
        );
        ball.hp_to_screen_quads(
            allocator,
            font,
            camera_controller,
            screen_quads,
        );
        if (self.selected_ball) |sb| {
            if (ball.id == sb) {
                if (!self.is_aiming)
                    _ = ball.info_panel_to_screen_quads(
                        allocator,
                        input_state,
                        font,
                        camera_controller,
                        screen_quads,
                    );
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
