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

const runtime = @import("runtime.zig");
const InputState = runtime.InputState;

const _objects = @import("objects.zig");
const Ball = _objects.Ball;
const Table = _objects.Table;
const Cue = _objects.Cue;
const Item = _objects.Item;
const ItemInventory = _objects.ItemInventory;
const CueInventory = _objects.CueInventory;

const _animations = @import("animations.zig");
const BallAnimations = _animations.BallAnimations;

turn_owner: Owner,
turn_state: TurnState,

player_hp: i32,
player_hp_overhead: i32,

opponent_hp: i32,
opponent_hp_overhead: i32,

item_infos: Item.Infos,
item_inventory: ItemInventory,
cue_inventory: CueInventory,

texture_ball: Textures.Texture.Id,
balls: [MAX_BALLS]Ball,
ball_animations: BallAnimations,
table: Table,

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

pub fn init(
    self: *Self,
    memory: *Memory,
    texture_store: *Textures.Store,
) void {
    self.texture_ball = texture_store.load(memory, "assets/ball_prototype.png");
    self.table = Table.init(texture_store.load(memory, "assets/table_prototype.png"));

    inline for (&self.item_infos.infos, 0..) |*info, i| {
        info.* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = std.fmt.comptimePrint("item info: {d}", .{i}),
            .description = std.fmt.comptimePrint("item description: {d}", .{i}),
        };
    }
    self.item_infos.get_mut(.CueDefault).texture_id =
        texture_store.load(memory, "assets/cue_prototype.png");

    self.restart();
}

pub fn restart(self: *Self) void {
    self.item_inventory = ItemInventory.init();
    self.cue_inventory = CueInventory.init();
    _ = self.item_inventory.add(.BallSpiky);
    _ = self.item_inventory.add(.CueHP);
    _ = self.item_inventory.add(.BallSpiky);
    _ = self.item_inventory.add(.BallSpiky);
    _ = self.cue_inventory.add(.Cue50CAL);
    _ = self.cue_inventory.add(.Cue50CAL);
    self.turn_owner = .Player;
    self.turn_state = .NotTaken;
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

pub fn update_and_draw(
    self: *Self,
    allocator: Allocator,
    input_state: *const InputState,
    camera_controller: *const CameraController2d,
    font: *const Font,
    texture_store: *const Textures.Store,
    screen_quads: *ScreenQuads,
    dt: f32,
) void {
    self.table.to_screen_quad(
        camera_controller,
        texture_store,
        screen_quads,
    );

    const selected_item = self.item_inventory.selected();
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
            break :blk ball.to_screen_quads(
                show_info,
                null,
                allocator,
                input_state,
                font,
                camera_controller,
                texture_store,
                screen_quads,
            );
        } else blk: {
            const r = ball.to_screen_quads(
                show_info,
                selected_item,
                allocator,
                input_state,
                font,
                camera_controller,
                texture_store,
                screen_quads,
            );
            if (is_selected) {
                const pbo = ball.previous_positions_to_object_2d();
                for (&pbo) |pb| {
                    pb.to_screen_quad(
                        camera_controller,
                        texture_store,
                        screen_quads,
                    );
                }
            }
            break :blk r;
        };
        if (r.upgrade_applied) {
            self.item_inventory.item_used();
        }
        if (r.need_refill) {
            const to_refill = ball.max_hp - ball.hp;
            const hp_overhead = if (self.turn_owner == .Player)
                &self.player_hp_overhead
            else
                &self.opponent_hp_overhead;
            const hp = if (self.turn_owner == .Player)
                &self.player_hp
            else
                &self.opponent_hp;
            if (to_refill <= hp_overhead.*) {
                ball.hp = ball.max_hp;
                hp.* += to_refill;
                hp_overhead.* -= to_refill;
            }
        }
    }

    self.item_inventory.to_screen_quads(
        allocator,
        font,
        &self.item_infos,
        camera_controller,
        texture_store,
        screen_quads,
    );

    const is_cue_upgrade = if (selected_item) |si| si.is_cue_upgrade() else false;
    self.cue_inventory.to_screen_quads(
        is_cue_upgrade,
        &self.item_infos,
        camera_controller,
        texture_store,
        screen_quads,
    );

    switch (self.turn_state) {
        .NotTaken => {
            if (!self.is_aiming) {
                self.is_aiming = self.selected_ball != null and input_state.rmb;
                self.cue_inventory.selected().move_storage();
                self.item_inventory.update(input_state);
            } else {
                if (self.selected_ball) |sb| {
                    const ball = &self.balls[sb];
                    const hit_vector = input_state.mouse_pos_world.sub(ball.body.position);
                    self.cue_inventory.selected().move_aiming(ball.body.position, hit_vector);

                    if (!input_state.rmb) {
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
                    ball.is_hovered(input_state.mouse_pos_world) and
                    input_state.lmb)
                {
                    new_ball_selected = true;
                    self.selected_ball = ball.id;
                }
            }
            if (!new_ball_selected and input_state.lmb)
                self.selected_ball = null;
        },
        .Shooting => {
            const sb = self.selected_ball.?;
            const ball_position = self.balls[sb].body.position;
            const hit_vector = input_state.mouse_pos_world.sub(ball_position);
            if (self.cue_inventory.selected().move_shoot(ball_position, hit_vector, dt))
                self.turn_state = .Taken;
        },
        .Taken => {
            self.cue_inventory.selected().move_storage();

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
            if (self.ball_animations.run(&self.balls, dt) and
                disabled_or_stationary == self.balls.len)
            {
                self.turn_owner = if (self.turn_owner == .Player) .Opponent else .Player;
                self.turn_state = .NotTaken;
                self.selected_ball = null;
            }
        },
    }
}
