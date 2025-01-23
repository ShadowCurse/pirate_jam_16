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

const UI = @import("ui.zig");

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
        _ = self.cue_inventory.add(.Cue50CAL);
        _ = self.cue_inventory.add(.Cue50CAL);
        self.hp = 100;
        self.hp_overhead = 100;
    }
};

turn_owner: Owner,
turn_state: TurnState,

player: PlayerContext,
opponent: PlayerContext,

texture_ball: Textures.Texture.Id,
ball_animations: BallAnimations,
table: Table,
shop: Shop,

balls: [MAX_BALLS]Ball,

selected_ball: ?u32,
is_aiming: bool,

const MAX_BALLS = 20;

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
    self.texture_ball = context.texture_store.load(
        context.memory,
        "assets/ball_prototype.png",
    );
    self.player.init(.Player);
    self.opponent.init(.Opponent);
    self.table = Table.init(
        context.texture_store.load(context.memory, "assets/table_prototype.png"),
    );
    self.restart();
}

pub fn restart(self: *Self) void {
    self.turn_owner = .Player;
    self.turn_state = .NotTaken;

    self.player.reset(.Player);
    self.opponent.reset(.Opponent);

    self.ball_animations = .{};
    self.shop.reset();

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

    self.selected_ball = null;
    self.is_aiming = false;
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
    UI.in_game(self, context);

    const entity = if (self.turn_owner == .Player) blk: {
        self.opponent.item_inventory.to_screen_quads(context);
        _ = self.opponent.cue_inventory.update_and_draw(context, null);
        break :blk &self.player;
    } else blk: {
        self.player.item_inventory.to_screen_quads(context);
        _ = self.player.cue_inventory.update_and_draw(context, null);
        break :blk &self.opponent;
    };

    self.table.to_screen_quad(context);

    const selected_item = entity.item_inventory.selected();
    for (&self.balls) |*ball| {
        const is_selected = if (self.selected_ball) |sb| blk: {
            if (ball.id == sb) {
                break :blk true;
            }
            break :blk false;
        } else blk: {
            break :blk false;
        };
        const show_info = is_selected and !self.is_aiming and self.turn_state == .NotTaken;

        const r = if (ball.owner != self.turn_owner) blk: {
            break :blk ball.to_screen_quads(context, show_info, null);
        } else blk: {
            const r = ball.to_screen_quads(context, show_info, selected_item);
            if (is_selected) {
                ball.previous_positions_to_object_2d(context);
            }
            break :blk r;
        };
        if (r.upgrade_applied) {
            entity.item_inventory.item_used();
        }
        if (r.need_refill) {
            const to_refill = ball.max_hp - ball.hp;
            if (to_refill <= entity.hp_overhead) {
                ball.hp = ball.max_hp;
                entity.hp += to_refill;
                entity.hp_overhead -= to_refill;
            }
        }
    }

    entity.item_inventory.to_screen_quads(context);
    if (entity.cue_inventory.update_and_draw(context, selected_item))
        entity.item_inventory.item_used();

    switch (self.turn_state) {
        .NotTaken => {
            if (!self.is_aiming) {
                self.is_aiming = self.selected_ball != null and context.input.rmb;
                entity.cue_inventory.selected().move_storage();
                entity.item_inventory.update(context);
            } else {
                if (self.selected_ball) |sb| {
                    const ball = &self.balls[sb];
                    const hit_vector = context.input.mouse_pos_world.sub(ball.body.position);
                    entity.cue_inventory.selected().move_aiming(ball.body.position, hit_vector);

                    if (!context.input.rmb) {
                        // We hit in the opposite direction of the "to_mouse" direction
                        ball.body.velocity = ball.body.velocity.add(hit_vector.neg());
                        self.turn_state = .Shooting;
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
                    ball.is_hovered(context.input.mouse_pos_world) and
                    context.input.lmb)
                {
                    new_ball_selected = true;
                    self.selected_ball = ball.id;
                }
            }
            if (!new_ball_selected and context.input.lmb)
                self.selected_ball = null;
        },
        .Shooting => {
            const sb = self.selected_ball.?;
            const ball_position = self.balls[sb].body.position;
            const hit_vector = context.input.mouse_pos_world.sub(ball_position);
            if (entity.cue_inventory.selected().move_shoot(ball_position, hit_vector, context.dt))
                self.turn_state = .Taken;
        },
        .Taken => {
            entity.cue_inventory.selected().move_storage();

            for (&self.balls) |*ball| {
                if (ball.disabled)
                    continue;
                ball.update(&self.table, &self.balls, self.turn_owner, context.dt);
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
            self.player.hp = new_player_hp;
            self.player.hp_overhead += player_overheal;
            self.opponent.hp = new_opponent_hp;
            self.opponent.hp_overhead += opponent_overheal;

            var disabled_or_stationary: u8 = 0;
            for (&self.balls) |*ball| {
                if (ball.disabled or ball.stationary) {
                    disabled_or_stationary += 1;
                }
            }
            if (self.ball_animations.run(context.dt) and
                disabled_or_stationary == self.balls.len)
            {
                self.turn_owner = if (self.turn_owner == .Player) .Opponent else .Player;
                self.turn_state = .NotTaken;
                self.selected_ball = null;
            }
        },
    }
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
