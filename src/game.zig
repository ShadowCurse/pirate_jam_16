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
    hp: f32 = PLAYER_BALLS * 10,
    hp_overhead: f32 = 0,
    item_inventory: ItemInventory,
    cue_inventory: CueInventory,

    pub fn init(self: *PlayerContext, context: *GlobalContext, owner: Owner) void {
        self.hp = PLAYER_BALLS * 10;
        self.hp_overhead = 0;
        self.item_inventory = ItemInventory.init(owner);
        self.cue_inventory = CueInventory.init(context, owner);
    }

    pub fn reset(self: *PlayerContext, owner: Owner) void {
        self.item_inventory = ItemInventory.init(owner);
        _ = self.item_inventory.add(.BallLight);
        _ = self.item_inventory.add(.BallHeavy);
        _ = self.item_inventory.add(.BallArmored);
        _ = self.item_inventory.add(.BallHealthy);
        _ = self.item_inventory.add(.BallSpiky);
        self.cue_inventory.reset();
        _ = self.cue_inventory.add(.CueKar98K);
        self.hp = PLAYER_BALLS * 10;
        self.hp_overhead = 0;
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
    self.player.init(context, .Player);
    self.opponent.init(context, .Opponent);
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
            context,
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
            context,
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
    if (context.state.rules)
        self.rules(context);
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

pub fn rules(self: *Self, context: *GlobalContext) void {
    _ = self;
    UI.rules(context);
}

pub fn in_game(self: *Self, context: *GlobalContext) void {
    if (self.turn_owner == .Opponent)
        self.ai.update(context, self)
    else
        context.input = context.player_input;

    self.table.to_screen_quad(context);
    if (context.state.debug) {
        self.physics.borders_to_screen_quads(context);
        self.physics.pockets_to_screen_quads(context);
    }

    const entity = if (self.turn_owner == .Player) blk: {
        _ = self.opponent.cue_inventory.update_and_draw(context, null, false);
        self.opponent.cue_inventory.selected().move_storage();
        break :blk &self.player;
    } else blk: {
        _ = self.player.cue_inventory.update_and_draw(context, null, false);
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
            context.audio.play(
                context.assets.sound_item_use,
                0.2,
                0.2,
            );
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
        ball.draw_effect(context);
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

    if (entity.cue_inventory.update_and_draw(
        context,
        selected_item,
        self.selected_ball == null,
    )) {
        context.audio.play(
            context.assets.sound_item_use,
            0.2,
            0.2,
        );
        entity.item_inventory.item_used();
    }

    self.opponent.item_inventory.update(context, self.turn_owner);
    self.opponent.item_inventory.to_screen_quads(context);
    self.player.item_inventory.update(context, self.turn_owner);
    self.player.item_inventory.to_screen_quads(context);

    switch (self.turn_state) {
        .NotTaken => {
            if (self.turn_owner == .Opponent and self.ai.stage == .Wait)
                self.ai.stage = .StartTurn;

            for (&self.balls) |*ball| {
                ball.hit_by_ring_of_light = false;
            }

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

                const selected_cue = entity.cue_inventory.selected();
                selected_cue.move_aiming(
                    context,
                    ball.physics.body.position,
                    hit_vector,
                    strength,
                );

                if (context.input.lmb == .Released) {
                    selected_cue.initial_hit_strength = strength;
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
                        context,
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
            const selected_ball = &self.balls[sb];
            const selected_cue = entity.cue_inventory.selected();

            const ball_position = selected_ball.physics.body.position;
            const cue_position = selected_cue.position;
            const hit_vector = cue_position.sub(ball_position);
            if (selected_cue.move_shoot(
                context,
                ball_position,
                hit_vector,
                context.dt,
            )) |hit_strength| {
                const cue_to_ball = hit_vector.normalize().neg();
                selected_ball.physics.body.velocity = selected_ball.physics.body.velocity
                    .add(cue_to_ball.mul_f32(hit_strength));

                if (selected_cue.silencer) {
                    selected_ball.physics.state.ghost = true;
                }

                if (selected_cue.tag == .CueKar98K) {
                    const ray_start = ball_position;
                    const ray_direction = cue_to_ball;
                    for (&self.balls) |*ball| {
                        if (ball.id == selected_ball.id)
                            continue;
                        if (Physics.ray_circle_intersect(
                            ray_start,
                            ray_direction,
                            ball.physics.collider,
                            ball.physics.body.position,
                        )) {
                            const str_mul =
                                20.0 / (ball_position.sub(ball.physics.body.position).len());
                            ball.physics.body.velocity = ball.physics.body.velocity
                                .add(cue_to_ball.mul_f32(hit_strength * str_mul));
                            ball.hp -= Cue.Ka98KAnimation.DAMAGE;
                        }
                    }
                }
                if (selected_cue.tag == .CueCross) {
                    for (&self.balls) |*ball| {
                        if (ball.id == selected_ball.id)
                            continue;
                        const d =
                            selected_ball.physics.body.position
                            .sub(ball.physics.body.position).len();
                        if (d < Cue.CrossAnimation.RADIUS) {
                            if (ball.owner == self.turn_owner)
                                ball.hp += Cue.CrossAnimation.HEAL
                            else
                                ball.hp -= Cue.CrossAnimation.DAMAGE;
                        }
                    }
                }

                entity.cue_inventory.remove(selected_cue.tag);
                self.turn_state = .Taken;
            }
        },
        .Taken => {
            self.selected_ball = null;

            entity.cue_inventory.selected().move_storage();
            const pr = self.physics.update(context);

            var new_player_hp: f32 = 0;
            var player_overheal: f32 = 0;
            var new_opponent_hp: f32 = 0;
            var opponent_overheal: f32 = 0;
            for (&self.balls, 0..) |*ball, i| {
                if (!ball.physics.state.playable())
                    continue;

                if (ball.physics.state.runner) {
                    const add_hp: f32 =
                        pr.distances[i] *
                        Ball.RunnerParticleEffect.HEAL_PER_UNIT;
                    ball.hp += add_hp;
                }

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

                for (pr.collisions) |c| {
                    if (c.ball_id != ball.id)
                        continue;

                    switch (c.entity_2) {
                        .BallRingOfLight => |ball_2_id| {
                            var ball_2 = &self.balls[ball_2_id];
                            if (ball_2.hit_by_ring_of_light)
                                continue;
                            ball_2.hit_by_ring_of_light = true;
                            if (ball.owner == self.turn_owner) {
                                if (ball_2.owner == self.turn_owner) {
                                    ball.hp += ball_2.heal *
                                        Ball.RingOfLightParticleEffect.STRENGTH_MUL;
                                    ball_2.hp += ball.heal *
                                        Ball.RingOfLightParticleEffect.STRENGTH_MUL;
                                } else {
                                    const min = @min(ball.damage, ball_2.hp);
                                    const d = min * (1.0 - ball_2.armor) *
                                        Ball.RingOfLightParticleEffect.STRENGTH_MUL;
                                    ball.hp += d;
                                    ball_2.hp -= d;
                                }
                            } else {
                                if (ball_2.owner == self.turn_owner) {
                                    const min = @min(ball_2.damage, ball.hp);
                                    const d = min * (1.0 - ball_2.armor) *
                                        Ball.RingOfLightParticleEffect.STRENGTH_MUL;
                                    ball.hp -= d;
                                    ball_2.hp += d;
                                } else {
                                    // nothing happens if 2 oppenents balls collide during players turn
                                    // and vise versa
                                }
                            }
                        },
                        .Ball => |ball_2_id| {
                            const hit_volume = std.math.clamp(
                                ball.physics.body.velocity.len() / 500.0,
                                0.0,
                                1.0,
                            );
                            const rv = (c.collision.position.x + 1280.0 / 2.0) / 1280.0;
                            const lv = 1.0 - rv;
                            context.play_audio(
                                context.assets.sound_ball_hit,
                                lv * hit_volume,
                                rv * hit_volume,
                            );

                            const ball_2 = &self.balls[ball_2_id];
                            if (ball.owner == self.turn_owner) {
                                if (ball_2.owner == self.turn_owner) {
                                    ball.hp += ball_2.heal;
                                    ball_2.hp += ball.heal;
                                } else {
                                    const min = @min(ball.damage, ball_2.hp);
                                    const d = min * (1.0 - ball_2.armor);
                                    ball.hp += d;
                                    ball_2.hp -= d;
                                }
                            } else {
                                if (ball_2.owner == self.turn_owner) {
                                    const min = @min(ball_2.damage, ball.hp);
                                    const d = min * (1.0 - ball_2.armor);
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
                            ball.physics.state.pocketted = true;
                            const pocket = &self.physics.pockets[pocket_id];
                            ball.physics.state.pocketted = true;
                            self.ball_animations.add(ball, pocket.body.position, 1.0);

                            const rv = (pocket.body.position.x + 1280.0 / 2.0) / 1280.0;
                            const lv = 1.0 - rv;
                            context.play_audio(
                                context.assets.sound_ball_pocket,
                                lv * 2.0,
                                rv * 2.0,
                            );
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
            }
            if (self.opponent.hp <= 0) {
                context.state.won = true;
                context.state_change_animation.set(UI.CAMERA_END_GAME, .{
                    .won = true,
                    .debug = context.state.debug,
                });
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

    if (self.shop.update_and_draw(context, self)) |item| {
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
