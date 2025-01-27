const std = @import("std");

const stygian = @import("stygian_runtime");
const log = stygian.log;

const _math = stygian.math;
const Vec2 = _math.Vec2;

const _runtime = @import("runtime.zig");
const GlobalContext = _runtime.GlobalContext;
const Input = _runtime.Input;

const _objects = @import("objects.zig");
const Cue = _objects.Cue;

const Game = @import("game.zig");
const Owner = Game.Owner;

const _animations = @import("animations.zig");
const SmoothStepAnimation = _animations.SmoothStepAnimation;

// WAITING stage:
// wait for the turn
// THINK stage:
// - choose to buy items or not
// - choose to use items or not
// - choose to heal any balls or not
// - choose which ball to hit
// SHOOT stage:
// - choose where to aim
// - shoot
rng: std.rand.DefaultPrng,
input: Input,
stage: Stage,

tasks: [32]Task,
tasks_n: u32,

const Stage = enum {
    Wait,
    Act,
};

const Task = union(enum) {
    MoveMouse: MoveMouse,
    ClickMouse: ClickMouse,
    SelectBall: SelectBall,
    SelectCue: SelectCue,
    TryBuyItem: TryBuyItem,
    UseItem: UseItem,
    Shoot: Shoot,
};

const Self = @This();

pub fn init(self: *Self) void {
    self.rng = std.rand.DefaultPrng.init(@intCast(std.time.microTimestamp()));
    self.input = .{};
    self.stage = .Wait;
    self.tasks_n = 0;
}

pub fn push_task(self: *Self, task: Task) void {
    log.assert(@src(), self.tasks_n < self.tasks.len, "AI: Trying to overflow task stack", .{});
    log.info(@src(), "AI: adding task to execute: {any}", .{task});
    self.tasks[self.tasks_n] = task;
    self.tasks_n += 1;
}

pub fn update(
    self: *Self,
    context: *GlobalContext,
    game: *Game,
) void {
    switch (self.stage) {
        .Wait => {
            self.push_task(Shoot.init(self));
            self.push_task(SelectBall.init(self));
            self.push_task(SelectCue.init(self));
            self.push_task(UseItem.init(self));
            self.push_task(TryBuyItem.init(self));
            self.stage = .Act;
        },
        .Act => {
            if (self.tasks_n == 0) {
                self.stage = .Wait;
                return;
            }

            const current_task = &self.tasks[self.tasks_n - 1];
            switch (current_task.*) {
                .MoveMouse => |*t| {
                    if (t.finished) {
                        // log.info(@src(), "Finished MoveMouse", .{});
                        self.tasks_n -= 1;
                    }
                    // log.info(@src(), "Executing MoveMouse", .{});
                    t.update(context, game, self);
                },
                .ClickMouse => |*t| {
                    if (t.finished) {
                        // log.info(@src(), "Finished ClickMouse", .{});
                        self.tasks_n -= 1;
                    }
                    // log.info(@src(), "Executing ClickMouse", .{});
                    t.update(context, game, self);
                },
                .SelectBall => |*t| {
                    if (t.finished) {
                        // log.info(@src(), "Finished SelectBall", .{});
                        self.tasks_n -= 1;
                    }
                    // log.info(@src(), "Executing SelectBall", .{});
                    t.update(context, game, self);
                },
                .SelectCue => |*t| {
                    if (t.finished) {
                        // log.info(@src(), "Finished SelectCue", .{});
                        self.tasks_n -= 1;
                    }
                    // log.info(@src(), "Executing SelectCue", .{});
                    t.update(context, game, self);
                },
                .TryBuyItem => |*t| {
                    if (t.finished) {
                        // log.info(@src(), "Finished TryBuyItem", .{});
                        self.tasks_n -= 1;
                    }
                    // log.info(@src(), "Executing TryBuyItem", .{});
                    t.update(context, game, self);
                },
                .UseItem => |*t| {
                    if (t.finished) {
                        // log.info(@src(), "Finished UseItem", .{});
                        self.tasks_n -= 1;
                    }
                    // log.info(@src(), "Executing UseItem", .{});
                    t.update(context, game, self);
                },
                .Shoot => |*t| {
                    if (t.finished) {
                        // log.info(@src(), "Finished Shoot", .{});
                        self.tasks_n -= 1;
                    }
                    // log.info(@src(), "Executing Shoot", .{});
                    t.update(context, game, self);
                },
            }
        },
    }
    context.input = self.input;
}

const MoveMouse = struct {
    finished: bool = false,
    started: bool = false,
    animation: SmoothStepAnimation,

    const TIME_MIN = 1.0;
    const TIME_MAX = 2.0;

    pub fn init(ai: *Self, to: Vec2) Task {
        const random = ai.rng.random();
        return .{
            .MoveMouse = .{
                .animation = .{
                    .end_position = to.extend(0.0),
                    .duration = TIME_MIN + (TIME_MAX - TIME_MIN) * random.float(f32),
                },
            },
        };
    }

    pub fn update(self: *MoveMouse, context: *GlobalContext, game: *Game, ai: *Self) void {
        _ = game;

        if (self.finished)
            return;

        if (!self.started) {
            self.animation.start_position = ai.input.mouse_pos_world.extend(0.0);
            self.started = true;
        }

        var v3 = ai.input.mouse_pos_world.extend(0.0);
        self.finished = self.animation.update(&v3, context.dt);
        ai.input.mouse_pos_world = v3.xy();
    }
};

const ClickMouse = struct {
    finished: bool = false,
    lmb: Input.KeyState = .None,
    rmb: Input.KeyState = .None,

    pub fn init(lmb: Input.KeyState, rmb: Input.KeyState) Task {
        return .{
            .ClickMouse = .{
                .lmb = lmb,
                .rmb = rmb,
            },
        };
    }

    pub fn update(self: *ClickMouse, context: *GlobalContext, game: *Game, ai: *Self) void {
        _ = context;
        _ = game;
        if (self.finished)
            return;
        ai.input.lmb = self.lmb;
        ai.input.rmb = self.rmb;
        self.finished = true;
    }
};

const SelectBall = struct {
    finished: bool = false,
    timer: f32 = 0.0,
    timer_end: f32 = 0.0,

    const TIME_MIN = 0.2;
    const TIME_MAX = 0.3;

    pub fn init(ai: *Self) Task {
        const random = ai.rng.random();
        return .{
            .SelectBall = .{
                .timer_end = TIME_MIN + (TIME_MAX - TIME_MIN) * random.float(f32),
            },
        };
    }

    pub fn update(self: *SelectBall, context: *GlobalContext, game: *Game, ai: *Self) void {
        if (self.finished)
            return;

        self.timer += context.dt;
        if (self.timer < self.timer_end) {
            return;
        }
        const selected_ball_index = random_ball_index(.Opponent, game, ai);
        log.info(@src(), "AI: selected ball index: {d}", .{selected_ball_index});
        const ball_position = game.balls[selected_ball_index].physics.body.position;
        log.info(
            @src(),
            "AI: selected ball position: {d}:{d}",
            .{ ball_position.x, ball_position.y },
        );
        ai.push_task(ClickMouse.init(.None, .None));
        ai.push_task(ClickMouse.init(.Pressed, .None));
        ai.push_task(MoveMouse.init(ai, ball_position));
        self.finished = true;
    }

    pub fn random_ball_index(owner: Owner, game: *Game, ai: *Self) u32 {
        var balls_alive: u32 = 0;
        for (&game.balls) |*ball| {
            if (ball.physics.state.playable() and ball.owner == owner)
                balls_alive += 1;
        }
        const random = ai.rng.random();
        var r_index: u32 =
            @intFromFloat(random.float(f32) * @as(f32, @floatFromInt(balls_alive)));

        for (&game.balls, 0..) |*ball, i| {
            if (ball.physics.state.playable() and ball.owner == owner) {
                if (r_index == 0) {
                    return @intCast(i);
                }
                r_index -= 1;
            }
        }
        unreachable;
    }
};

const SelectCue = struct {
    finished: bool = false,
    timer: f32 = 0.0,
    timer_end: f32 = 0.0,

    const TIME_MIN = 1.2;
    const TIME_MAX = 2.3;

    pub fn init(ai: *Self) Task {
        const random = ai.rng.random();
        return .{
            .SelectCue = .{
                .timer_end = TIME_MIN + (TIME_MAX - TIME_MIN) * random.float(f32),
            },
        };
    }

    pub fn update(self: *SelectCue, context: *GlobalContext, game: *Game, ai: *Self) void {
        if (self.finished)
            return;

        self.timer += context.dt;
        if (self.timer < self.timer_end) {
            return;
        }
        const selected_cue_index = random_cue_index(game, ai);
        log.info(@src(), "AI: selected cue index: {d}", .{selected_cue_index});
        const cue_position =
            game.opponent.cue_inventory.cue_position_rotation(selected_cue_index)[0];
        log.info(
            @src(),
            "AI: selected cue position: {d}:{d}",
            .{ cue_position.x, cue_position.y },
        );
        ai.push_task(ClickMouse.init(.None, .None));
        ai.push_task(ClickMouse.init(.Pressed, .None));
        ai.push_task(MoveMouse.init(ai, cue_position));
        self.finished = true;
    }

    pub fn random_cue_index(game: *Game, ai: *Self) u32 {
        var cues_alive: u32 = 0;
        for (&game.opponent.cue_inventory.cues) |*cue| {
            if (cue.tag != .Invalid)
                cues_alive += 1;
        }
        const random = ai.rng.random();
        var r_index: u32 =
            @intFromFloat(random.float(f32) * @as(f32, @floatFromInt(cues_alive)));

        for (&game.opponent.cue_inventory.cues, 0..) |*cue, i| {
            if (cue.tag != .Invalid) {
                if (r_index == 0) {
                    return @intCast(i);
                }
                r_index -= 1;
            }
        }
        unreachable;
    }
};

const TryBuyItem = struct {
    finished: bool = false,
    timer: f32 = 0.0,
    timer_end: f32 = 0.0,

    const TIME_MIN = 0.2;
    const TIME_MAX = 0.3;

    pub fn init(ai: *Self) Task {
        const random = ai.rng.random();
        return .{
            .TryBuyItem = .{
                .timer_end = TIME_MIN + (TIME_MAX - TIME_MIN) * random.float(f32),
            },
        };
    }

    pub fn update(self: *TryBuyItem, context: *GlobalContext, game: *Game, ai: *Self) void {
        _ = ai;

        if (self.finished)
            return;

        self.timer += context.dt;
        if (self.timer < self.timer_end) {
            return;
        }

        const item = game.shop.random_item();
        const item_info = context.item_infos.get(item);
        if (item_info.price <= game.opponent.hp_overhead) {
            if (item.is_cue()) {
                if (game.opponent.cue_inventory.add(item)) {
                    game.opponent.hp_overhead -= item_info.price;
                } else {
                    log.info(@src(), "AI: Cannot add item to the cue inventory: Full", .{});
                }
            } else {
                if (game.opponent.item_inventory.add(item)) {
                    game.opponent.hp_overhead -= item_info.price;
                } else {
                    log.info(@src(), "AI: Cannot add item to the item inventory: Full", .{});
                }
            }
        }
        self.finished = true;
    }
};

const UseItem = struct {
    finished: bool = false,
    tried_to_select: bool = false,
    timer: f32 = 0.0,
    timer_end: f32 = 0.0,

    const TIME_MIN = 0.5;
    const TIME_MAX = 1.0;

    pub fn init(ai: *Self) Task {
        const random = ai.rng.random();
        return .{
            .UseItem = .{
                .timer_end = TIME_MIN + (TIME_MAX - TIME_MIN) * random.float(f32),
            },
        };
    }

    pub fn update(self: *UseItem, context: *GlobalContext, game: *Game, ai: *Self) void {
        if (self.finished)
            return;

        self.timer += context.dt;
        if (self.timer < self.timer_end) {
            if (!self.tried_to_select) {
                self.tried_to_select = true;
                try_to_select_item(context, game, ai);
            }
            return;
        }

        if (game.opponent.item_inventory.selected_position()) |_| {
            const target_position = upgrade_target_position(game, ai);
            ai.push_task(ClickMouse.init(.None, .None));
            ai.push_task(ClickMouse.init(.Pressed, .None));
            ai.push_task(MoveMouse.init(ai, target_position));
        } else {
            log.info(@src(), "AI: no inventory item was selected", .{});
        }
        self.finished = true;
    }

    pub fn try_to_select_item(context: *GlobalContext, game: *Game, ai: *Self) void {
        _ = context;
        if (random_item_index(game, ai)) |rii| {
            log.info(@src(), "AI: randomly selected item index: {d}", .{rii});
            const rii_position = game.opponent.item_inventory.item_position(rii);
            ai.push_task(ClickMouse.init(.None, .None));
            ai.push_task(ClickMouse.init(.Pressed, .None));
            ai.push_task(MoveMouse.init(ai, rii_position));
        }
    }

    pub fn random_item_index(game: *Game, ai: *Self) ?u32 {
        var items_alive: u32 = 0;
        for (game.opponent.item_inventory.items) |item| {
            if (item != .Invalid)
                items_alive += 1;
        }
        if (items_alive == 0)
            return null;

        const random = ai.rng.random();
        var r_index: u32 =
            @intFromFloat(random.float(f32) * @as(f32, @floatFromInt(items_alive)));

        for (game.opponent.item_inventory.items, 0..) |item, i| {
            if (item != .Invalid) {
                if (r_index == 0) {
                    return @intCast(i);
                }
                r_index -= 1;
            }
        }
        unreachable;
    }

    pub fn upgrade_target_position(game: *Game, ai: *Self) Vec2 {
        const random = ai.rng.random();
        const selected = game.opponent.item_inventory.selected().?;
        if (selected.is_ball()) {
            while (true) {
                for (game.balls[Game.PLAYER_BALLS..]) |*ball| {
                    if (ball.physics.state.playable()) {
                        const r = random.float(f32);
                        if (r < 0.2) {
                            return ball.physics.body.position;
                        }
                    }
                }
            }
        } else {
            while (true) {
                for (&game.opponent.cue_inventory.cues) |*cue| {
                    if (cue.tag != .Invalid) {
                        const r = random.float(f32);
                        if (r < 0.2) {
                            return cue.position;
                        }
                    }
                }
            }
        }
    }
};

const Shoot = struct {
    finished: bool = false,
    target_ball_position: ?Vec2 = null,
    timer: f32 = 0.0,
    timer_end: f32 = 0.0,

    const TIME_MIN = 0.5;
    const TIME_MAX = 1.5;
    const OFFSET_AIM = 120.0;

    pub fn init(ai: *Self) Task {
        const random = ai.rng.random();
        return .{
            .Shoot = .{
                .timer_end = TIME_MIN + (TIME_MAX - TIME_MIN) * random.float(f32),
            },
        };
    }

    pub fn update(self: *Shoot, context: *GlobalContext, game: *Game, ai: *Self) void {
        if (self.finished)
            return;

        self.timer += context.dt;
        if (self.timer < self.timer_end) {
            if (self.target_ball_position == null) {
                self.select_target(game, ai);
                self.move_cue(OFFSET_AIM, game, ai);
            } else {
                const random = ai.rng.random();
                if (random.float(f32) < 0.05) {
                    self.select_target(game, ai);
                    self.move_cue(OFFSET_AIM, game, ai);
                }
            }
            return;
        }

        ai.push_task(ClickMouse.init(.None, .None));
        ai.push_task(ClickMouse.init(.Released, .None));
        const random = ai.rng.random();
        const offset = OFFSET_AIM + Cue.MAX_STRENGTH * random.float(f32);
        self.move_cue(offset, game, ai);
        ai.push_task(ClickMouse.init(.Pressed, .None));

        self.finished = true;
    }

    pub fn move_cue(self: *Shoot, offset: f32, game: *Game, ai: *Self) void {
        const selected_ball = &game.balls[game.selected_ball.?];
        const from_target = selected_ball.physics.body.position
            .sub(self.target_ball_position.?).normalize();

        ai.push_task(
            MoveMouse.init(
                ai,
                selected_ball.physics.body.position
                    .add(from_target.mul_f32(offset)),
            ),
        );
    }

    pub fn select_target(self: *Shoot, game: *Game, ai: *Self) void {
        const player_ball_index = SelectBall.random_ball_index(.Player, game, ai);
        self.target_ball_position = game.balls[player_ball_index].physics.body.position;
        log.info(@src(), "AI: selected player ball target index: {d}", .{player_ball_index});
    }
};
