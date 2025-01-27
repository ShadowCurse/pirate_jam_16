const std = @import("std");
const Allocator = std.mem.Allocator;

const stygian = @import("stygian_runtime");
const log = stygian.log;

const Font = stygian.font;
const Memory = stygian.memory;
const Physics = stygian.physics;
const Textures = stygian.textures;
const Color = stygian.color.Color;
const Events = stygian.platform.event;
const ScreenQuads = stygian.screen_quads;
const CameraController2d = stygian.camera.CameraController2d;

const _math = stygian.math;
const Vec2 = _math.Vec2;

const _runtime = @import("runtime.zig");
const GlobalContext = _runtime.GlobalContext;

const GamePhysics = @import("physics.zig");

const UI = @import("ui.zig");
const AI = @import("ai.zig");

const _objects = @import("objects.zig");
const Ball = _objects.Ball;
const Table = _objects.Table;
const Cue = _objects.Cue;
const Item = _objects.Item;
const ItemInventory = _objects.ItemInventory;
const CueInventory = _objects.CueInventory;
const Shop = _objects.Shop;

const _animations = @import("animations.zig");
const BallAnimations = _animations.BallAnimations;

const PlayerContext = struct {
    hp: i32 = 100,
    hp_overhead: i32 = 100,
    item_inventory: ItemInventory,
    cue_inventory: CueInventory,

    pub fn init(self: *PlayerContext, owner: Owner) void {
        self.hp = 100;
        self.hp_overhead = 100;
        self.item_inventory = ItemInventory.init(owner);
        self.cue_inventory = CueInventory.init(owner);
    }

    pub fn reset(self: *PlayerContext, owner: Owner) void {
        self.item_inventory = ItemInventory.init(owner);
        self.cue_inventory = CueInventory.init(owner);
        _ = self.cue_inventory.add(.CueKar98K);
        _ = self.cue_inventory.add(.CueCross);
        self.hp = 100;
        self.hp_overhead = 100;
    }
};

turn_owner: Owner,
turn_state: TurnState,

player: PlayerContext,
opponent: PlayerContext,

ai: AI,

texture_ball: Textures.Texture.Id,
ball_animations: BallAnimations,
table: Table,
shop: Shop,

balls: [PLAYER_BALLS + OPPONENT_BALLS]Ball,
physics: GamePhysics,

selected_ball: ?u32,
cue_aim_start_positon: ?Vec2,

pub const PLAYER_BALLS = 15;
pub const OPPONENT_BALLS = 15;

pub const TurnState = enum {
    NotTaken,
    Shooting,
    Taken,
};

pub const Owner = enum(u1) {
    Player,
    Opponent,
};

const Self = @This();

pub fn init(self: *Self, context: *GlobalContext) void {
    self.player.init(.Player);
    self.opponent.init(.Opponent);
    self.table = Table.init(context.assets.table);
    self.restart(context);
}

pub fn restart(self: *Self, context: *GlobalContext) void {
    self.turn_owner = .Player;
    self.turn_state = .NotTaken;

    self.player.reset(.Player);
    self.opponent.reset(.Opponent);
    self.ai.init();

    self.ball_animations = .{};
    self.shop.reset();

    self.physics.init();
    self.init_balls(context);

    self.selected_ball = null;
    self.cue_aim_start_positon = null;
}

pub fn init_balls(self: *Self, context: *GlobalContext) void {
    for (
        self.physics.balls[0..PLAYER_BALLS],
        self.balls[0..PLAYER_BALLS],
        0..,
    ) |*pb, *b, i| {
        b.* = Ball.init(
            @intCast(i),
            Color.from_parts(255, 0, 0, 200),
            context.assets.ball_player,
            .Player,
            pb,
        );
    }

    for (
        self.physics.balls[PLAYER_BALLS..],
        self.balls[PLAYER_BALLS..],
        PLAYER_BALLS..,
    ) |*pb, *b, i| {
        b.* = Ball.init(
            @intCast(i),
            Color.from_parts(71, 182, 210, 200),
            context.assets.ball_opponent,
            .Opponent,
            pb,
        );
    }
}

pub fn update_and_draw(
    self: *Self,
    context: *GlobalContext,
) void {
    if (context.state.main_menu)
        self.main_menu(context);
    if (context.state.settings)
        self.settings(context);
    if (context.state.in_game)
        self.in_game(context);
    if (context.state.in_game_shop)
        self.in_game_shop(context);
    if (context.state.won)
        UI.in_end_game_won(self, context);
    if (context.state.lost)
        UI.in_end_game_lost(self, context);
    if (context.state.debug)
        self.debug(context);
}

pub fn main_menu(self: *Self, context: *GlobalContext) void {
    UI.main_menu(self, context);
}

pub fn settings(self: *Self, context: *GlobalContext) void {
    _ = self;
    UI.settings(context);
}

pub fn in_game(self: *Self, context: *GlobalContext) void {
    if (self.turn_state == .NotTaken and self.turn_owner == .Opponent)
        self.ai.update(context, self)
    else
        context.input = context.player_input;

    self.table.to_screen_quad(context);
    if (context.state.debug) {
        self.physics.borders_to_screen_quads(context);
        self.physics.pockets_to_screen_quads(context);
    }

    const entity = if (self.turn_owner == .Player) blk: {
        _ = self.opponent.cue_inventory.update_and_draw(context, null);
        self.opponent.cue_inventory.selected().move_storage();
        break :blk &self.player;
    } else blk: {
        _ = self.player.cue_inventory.update_and_draw(context, null);
        self.player.cue_inventory.selected().move_storage();
        break :blk &self.opponent;
    };

    const selected_item = entity.item_inventory.selected();
    var new_ball_selected: bool = false;
    var new_ball_hovered: ?u32 = null;
    for (&self.balls) |*ball| {
        if (!ball.physics.state.playable())
            continue;

        const is_selected = if (self.selected_ball) |sb| blk: {
            if (ball.id == sb) {
                break :blk true;
            }
            break :blk false;
        } else blk: {
            break :blk false;
        };
        const r = if (ball.owner != self.turn_owner) blk: {
            break :blk ball.update_and_draw(context, is_selected, null);
        } else blk: {
            const r = ball.update_and_draw(context, is_selected, selected_item);
            break :blk r;
        };
        if (r.upgrade_applied) {
            entity.item_inventory.item_used();
        }
        if (!r.upgrade_applied and r.selected and
            ball.owner == self.turn_owner)
        {
            new_ball_selected = true;
            self.selected_ball = ball.id;
        }
        if (r.hovered) {
            new_ball_hovered = ball.id;
            ball.draw_info_panel(context);
        }
    }
    if (!new_ball_selected and self.cue_aim_start_positon == null) {
        self.selected_ball = null;
    }

    // need to do this separatelly to draw info panel on top of
    // other things
    if (new_ball_hovered) |hb| {
        const ball = &self.balls[hb];
        _ = ball.draw_info_panel(context);
    }

    if (entity.cue_inventory.update_and_draw(context, selected_item))
        entity.item_inventory.item_used();

    self.opponent.item_inventory.update(context, self.turn_owner);
    self.opponent.item_inventory.to_screen_quads(context);
    self.player.item_inventory.update(context, self.turn_owner);
    self.player.item_inventory.to_screen_quads(context);

    switch (self.turn_state) {
        .NotTaken => {
            if (self.cue_aim_start_positon) |casp| {
                const sb = self.selected_ball.?;
                const ball = &self.balls[sb];

                const hit_vector = casp.sub(
                    ball.physics.body.position,
                );
                const ball_to_start = hit_vector.normalize();
                const start_to_mouse = context.input.mouse_pos_world.sub(casp);
                const strength = @max(
                    0.0,
                    @min(Cue.MAX_STRENGTH, start_to_mouse.dot(ball_to_start)),
                );

                entity.cue_inventory.selected().move_aiming(
                    ball.physics.body.position,
                    hit_vector,
                    strength,
                );

                if (context.input.lmb == .Released) {
                    ball.physics.body.velocity = ball.physics.body.velocity
                        .add(ball_to_start.neg().mul_f32(strength * Cue.STRENGTH_MUL));
                    self.turn_state = .Shooting;
                    self.cue_aim_start_positon = null;
                }
            } else {
                if (self.selected_ball) |sb| {
                    const ball = &self.balls[sb];
                    const hit_vector = context.input.mouse_pos_world.sub(
                        ball.physics.body.position,
                    );
                    entity.cue_inventory.selected().move_aiming(
                        ball.physics.body.position,
                        hit_vector,
                        0.0,
                    );
                    if (context.input.lmb == .Pressed) {
                        self.cue_aim_start_positon = context.input.mouse_pos_world;
                    }
                } else {
                    entity.cue_inventory.selected().move_storage();
                }
            }
        },
        .Shooting => {
            const sb = self.selected_ball.?;
            const ball_position = self.balls[sb].physics.body.position;
            const hit_vector = context.input.mouse_pos_world.sub(ball_position);
            if (entity.cue_inventory.selected().move_shoot(ball_position, hit_vector, context.dt))
                self.turn_state = .Taken;
        },
        .Taken => {
            self.selected_ball = null;

            entity.cue_inventory.selected().move_storage();
            const collisions = self.physics.update(context);

            var new_player_hp: i32 = 0;
            var player_overheal: i32 = 0;
            var new_opponent_hp: i32 = 0;
            var opponent_overheal: i32 = 0;
            for (&self.balls) |*ball| {
                if (!ball.physics.state.playable())
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
                if (ball.hp <= 0) {
                    ball.physics.state.dead = true;
                }

                for (collisions) |c| {
                    if (c.ball_id != ball.id)
                        continue;

                    switch (c.entity_2) {
                        .Ball => |ball_2_id| {
                            const ball_2 = &self.balls[ball_2_id];
                            if (ball.owner == self.turn_owner) {
                                if (ball_2.owner == self.turn_owner) {
                                    ball.hp += ball_2.heal;
                                    ball_2.hp += ball.heal;
                                } else {
                                    const min = @min(ball.damage, ball_2.hp);
                                    const min_f32: f32 = @floatFromInt(min);
                                    const d: i32 =
                                        @intFromFloat(min_f32 * (1.0 - ball_2.armor));
                                    ball.hp += d;
                                    ball_2.hp -= d;
                                }
                            } else {
                                if (ball_2.owner == self.turn_owner) {
                                    const min = @min(ball_2.damage, ball.hp);
                                    const min_f32: f32 = @floatFromInt(min);
                                    const d: i32 =
                                        @intFromFloat(min_f32 * (1.0 - ball_2.armor));
                                    ball.hp -= d;
                                    ball_2.hp += d;
                                } else {
                                    // nothing happens if 2 oppenents balls collide during players turn
                                    // and vise versa
                                }
                            }
                        },
                        .Border => |_| {},
                        .Pocket => |pocket_id| {
                            const pocket = &self.physics.pockets[pocket_id];
                            ball.physics.state.pocketted = true;
                            self.ball_animations.add(ball, pocket.body.position, 1.0);
                        },
                    }
                }
            }
            self.player.hp = new_player_hp;
            self.player.hp_overhead += player_overheal;
            self.opponent.hp = new_opponent_hp;
            self.opponent.hp_overhead += opponent_overheal;

            if (self.player.hp <= 0) {
                context.state.lost = true;
                context.state_change_animation.set(UI.CAMERA_END_GAME, .{
                    .lost = true,
                    .debug = context.state.debug,
                });
                return;
            }
            if (self.opponent.hp <= 0) {
                context.state.won = true;
                context.state_change_animation.set(UI.CAMERA_END_GAME, .{
                    .won = true,
                    .debug = context.state.debug,
                });
                return;
            }

            var finished_balls: u8 = 0;
            for (&self.balls) |*ball| {
                if (ball.physics.state.any()) {
                    finished_balls += 1;
                }
            }
            if (self.ball_animations.run(context.dt) and
                finished_balls == self.balls.len)
            {
                self.turn_owner = if (self.turn_owner == .Player) .Opponent else .Player;
                self.turn_state = .NotTaken;
                self.selected_ball = null;
            }
        },
    }

    UI.in_game(self, context);
}

pub fn in_game_shop(self: *Self, context: *GlobalContext) void {
    const item_inventory = &self.player.item_inventory;
    const cue_inventory = &self.player.cue_inventory;

    if (self.shop.update_and_draw(context)) |item| {
        const item_info = context.item_infos.get(item);
        if (item_info.price <= self.player.hp_overhead) {
            if (item.is_cue()) {
                if (cue_inventory.add(item)) {
                    self.shop.remove_selected_item();
                    self.player.hp_overhead -= item_info.price;
                } else {
                    log.info(@src(), "Cannot add item to the cue inventory: Full", .{});
                }
            } else {
                if (item_inventory.add(item)) {
                    self.shop.remove_selected_item();
                    self.player.hp_overhead -= item_info.price;
                } else {
                    log.info(@src(), "Cannot add item to the item inventory: Full", .{});
                }
            }
        } else {
            log.info(@src(), "Cannot add item to the inventory: Need more money", .{});
        }
    }
}

pub fn debug(self: *Self, context: *GlobalContext) void {
    _ = self;
    UI.debug(context);
}
