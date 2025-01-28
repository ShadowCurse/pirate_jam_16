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
const Particles = stygian.particles;
const Events = stygian.platform.event;
const ScreenQuads = stygian.screen_quads;
const SoftRenderer = stygian.soft_renderer.renderer;
const CameraController2d = stygian.camera.CameraController2d;

const _objects = stygian.objects;
const Object2d = _objects.Object2d;

const _math = stygian.math;
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;
const Vec4 = _math.Vec4;

const _runtime = @import("runtime.zig");
const InputState = _runtime.InputState;
const GlobalContext = _runtime.GlobalContext;

const _game = @import("game.zig");
const Owner = _game.Owner;

const _animations = @import("animations.zig");
const SmoothStepAnimation = _animations.SmoothStepAnimation;

const GamePhysics = @import("physics.zig");

const UI = @import("ui.zig");
const UiText = UI.UiText;
const UiPanel = UI.UiPanel;
const UiDashedLine = UI.UiDashedLine;

pub const Ball = struct {
    id: u8,
    texture_id: Textures.Texture.Id,
    color_v4: Vec4,
    accumulator: f32,

    physics: *GamePhysics.Ball,

    owner: Owner,
    hp: i32 = 10,
    max_hp: i32 = 10,
    damage: i32 = 5,
    heal: i32 = 1,
    armor: f32 = 0.0,
    gravity_level: u8 = 0,
    runner_level: u8 = 0,
    ring_of_light_level: u8 = 0,

    // This is sprite size dependent because I don't scale balls for perf gains.
    pub const RADIUS = 10;
    pub const HP_TEXT_SIZE = 24;
    pub const INFO_PANEL_TEXT_SIZE = 40;
    pub const INFO_PANEL_OFFSET: Vec2 = .{ .y = -100.0 };
    pub const INFO_PANEL_SIZE: Vec2 = .{ .x = 100.0, .y = 150.0 };
    pub const UPGRADE_HILIGHT_COLOR = Color.from_parts(255, 0, 0, 64);
    pub const HOVER_HILIGHT_COLOR = Color.from_parts(0, 0, 255, 64);
    pub const LOW_HP_COLOR_V4: Vec4 = Color.from_parts(12, 15, 21, 64).to_vec4_norm();

    pub const trace = Tracing.Measurements(struct {
        to_object_2d: Tracing.Counter,
        previous_positions_to_object_2d: Tracing.Counter,
    });

    pub fn init(
        id: u8,
        color: Color,
        texture_id: Textures.Texture.Id,
        owner: Owner,
        physics: *GamePhysics.Ball,
    ) Ball {
        return .{
            .id = id,
            .texture_id = texture_id,
            .color_v4 = color.to_vec4_norm(),
            .accumulator = 0.0,
            .owner = owner,
            .physics = physics,
        };
    }

    pub fn is_hovered(self: Ball, mouse_pos: Vec2) bool {
        return Physics.point_circle_intersect(
            mouse_pos,
            self.physics.collider,
            self.physics.body.position,
        );
    }

    pub fn add_upgrade(self: *Ball, upgrade: Item.Tag) bool {
        switch (upgrade) {
            .BallSpiky => {
                self.damage += 5;
            },
            .BallHealthy => {
                self.hp += 5;
                self.max_hp += 5;
            },
            .BallArmored => {
                self.armor += 0.5;
            },
            .BallLight => {
                self.physics.body.inv_mass += 0.1;
            },
            .BallHeavy => {
                self.physics.body.inv_mass -= 0.1;
            },
            .BallGravity => {
                self.gravity_level += 1;
            },
            .BallRunner => {
                self.runner_level += 1;
            },
            .BallRingOfLight => {
                self.ring_of_light_level += 1;
            },
            else => unreachable,
        }

        return true;
    }

    pub const UpdateAndDrawResult = struct {
        hovered: bool = false,
        selected: bool = false,
        upgrade_applied: bool = false,
    };

    pub fn update_and_draw(
        self: *Ball,
        context: *GlobalContext,
        is_selected: bool,
        selected_upgrade: ?Item.Tag,
    ) UpdateAndDrawResult {
        var result: UpdateAndDrawResult = .{};

        const is_ball_upgrade = if (selected_upgrade) |si| si.is_ball() else false;
        const hovered = self.is_hovered(context.input.mouse_pos_world);
        const player_hovered = self.is_hovered(context.player_input.mouse_pos_world);
        result.hovered = hovered or player_hovered;

        result.selected = is_selected;
        if (!hovered and context.input.lmb == .Released)
            result.selected = false;
        if (hovered and context.input.lmb == .Released)
            result.selected = true;

        var color_v4: Vec4 = self.color_v4;
        if (is_ball_upgrade) {
            self.accumulator += context.dt * 1.5;
            color_v4 = color_v4.lerp(
                Color.WHITE.to_vec4_norm(),
                @abs(@sin(self.accumulator) * 0.6),
            );
        }
        if (is_selected or hovered) {
            color_v4 = color_v4.lerp(Color.WHITE.to_vec4_norm(), 0.5);
        }
        if (hovered) {
            if (is_ball_upgrade and context.input.lmb == .Released) {
                log.info(@src(), "ball upgrade", .{});
                result.selected = false;
                result.upgrade_applied = self.add_upgrade(selected_upgrade.?);
            }
        }
        const hp_percent: f32 =
            @as(f32, @floatFromInt(self.hp)) /
            @as(f32, @floatFromInt(self.max_hp));
        const tint = Color.from_vec4_norm(LOW_HP_COLOR_V4.lerp(color_v4, hp_percent));
        const object: Object2d = .{
            .type = .{ .TextureId = self.texture_id },
            .tint = tint,
            .transform = .{
                .position = self.physics.body.position.extend(0.0),
            },
            .options = .{
                // .draw_aabb = true,
                .no_scale_rotate = true,
                .with_tint = true,
            },
        };
        object.to_screen_quad(&context.camera, &context.texture_store, &context.screen_quads);
        return result;
    }

    pub fn draw_info_panel(self: Ball, context: *GlobalContext) void {
        const panel_position = self.physics.body.position.add(INFO_PANEL_OFFSET);
        const info_panel = UiPanel.init(
            panel_position,
            context.assets.button,
            null,
        );
        info_panel.to_screen_quad(context);
        {
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .y = -10.0 }),
                INFO_PANEL_TEXT_SIZE,
                "HP: {d}",
                .{self.hp},
                null,
            );
        }

        {
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .y = 10.0 }),
                INFO_PANEL_TEXT_SIZE,
                "Damage: {d}",
                .{self.damage},
                null,
            );
        }
    }
};

pub const Table = struct {
    texture_id: Textures.Texture.Id,

    pub fn init(texture_id: Textures.Texture.Id) Table {
        return .{
            .texture_id = texture_id,
        };
    }

    pub fn to_screen_quad(
        self: Table,
        context: *GlobalContext,
    ) void {
        const table_object: Object2d = .{
            .type = .{ .TextureId = self.texture_id },
            .transform = .{},
            .size = .{
                .x = @floatFromInt(context.texture_store.get_texture(self.texture_id).width),
                .y = @floatFromInt(context.texture_store.get_texture(self.texture_id).height),
            },
            .options = .{ .no_alpha_blend = true },
        };
        table_object.to_screen_quad(
            &context.camera,
            &context.texture_store,
            &context.screen_quads,
        );
    }
};

pub const Cue = struct {
    tag: Item.Tag,
    position: Vec2,
    rotation: f32,
    storage_position: Vec2,
    storage_rotation: f32,
    shoot_animation: ?SmoothStepAnimation,
    accumulator: f32,

    hit_count: u8 = 1,
    hit_strength: f32 = 1.0,
    wiggle_ball: bool = false,
    scope: bool = false,
    silencer: bool = false,

    pub const CUE_HEIGHT = 512;
    pub const CUE_WIDTH = 10;
    pub const AIM_BALL_OFFSET = Ball.RADIUS + 5;
    pub const MAX_STRENGTH = 150.0;
    pub const STRENGTH_MUL = 4.0;

    pub const UPGRADE_HILIGHT_COLOR = Color.from_parts(255, 0, 0, 64);
    pub const HOVER_HILIGHT_COLOR = Color.from_parts(0, 0, 255, 64);

    pub fn init(tag: Item.Tag, storage_position: Vec2, storage_rotation: f32) Cue {
        return .{
            .tag = tag,
            .position = storage_position,
            .rotation = storage_rotation,
            .storage_position = storage_position,
            .storage_rotation = storage_rotation,
            .shoot_animation = null,
            .accumulator = 0.0,
        };
    }

    pub fn reset_upgrades(self: *Cue) void {
        self.hit_count = 1;
        self.hit_strength = 1.0;
        self.wiggle_ball = false;
        self.scope = false;
        self.silencer = false;
    }

    pub fn hovered(self: Cue, mouse_pos: Vec2) bool {
        const collision_rectangle: Physics.Rectangle = .{
            .size = .{
                .x = CUE_WIDTH,
                .y = CUE_HEIGHT,
            },
        };
        return Physics.point_rectangle_intersect(
            mouse_pos,
            collision_rectangle,
            self.position,
        );
    }

    pub fn add_upgrade(self: *Cue, upgrade: Item.Tag) bool {
        switch (upgrade) {
            .CueWiggleBall => {
                if (self.wiggle_ball)
                    return false
                else
                    self.wiggle_ball = true;
            },
            .CueScope => {
                if (self.scope)
                    return false
                else
                    self.scope = true;
            },
            .CueSecondBarrel => {
                self.hit_count += 1;
            },
            .CueSilencer => {
                if (self.silencer)
                    return false
                else
                    self.silencer = true;
            },
            .CueRocketBooster => {
                self.hit_strength += 5.0;
            },
            else => unreachable,
        }

        return true;
    }

    pub fn move_storage(self: *Cue) void {
        self.position =
            self.position.add(self.storage_position.sub(self.position).mul_f32(0.2));
        self.rotation += (self.storage_rotation - self.rotation) * 0.2;
    }

    pub fn move_aiming(
        self: *Cue,
        ball_position: Vec2,
        hit_vector: Vec2,
        offset: f32,
    ) void {
        const hv_len = hit_vector.len();
        if (hv_len == 0.0)
            return;

        const hv_normalized = hit_vector.normalize();
        const cue_postion = ball_position.add(
            hv_normalized
                .mul_f32(AIM_BALL_OFFSET +
                CUE_HEIGHT / 2 + offset),
        );
        const c = hv_normalized.cross(.{ .y = 1 });
        const d = hv_normalized.dot(.{ .y = 1 });
        const cue_rotation = if (c < 0.0) -std.math.acos(d) else std.math.acos(d);

        self.position =
            self.position.add(cue_postion.sub(self.position).mul_f32(0.2));
        self.rotation += (cue_rotation - self.rotation) * 0.2;
    }

    pub fn move_shoot(
        self: *Cue,
        ball_position: Vec2,
        hit_vector: Vec2,
        dt: f32,
    ) bool {
        if (self.shoot_animation) |*sm| {
            var v3 = self.position.extend(0.0);
            if (sm.update(&v3, dt)) {
                self.shoot_animation = null;
                self.position = v3.xy();
                return true;
            }
            self.position = v3.xy();
        } else {
            const hv_normalized = hit_vector.normalize();
            const end_postion = ball_position.add(
                hv_normalized
                    .mul_f32(AIM_BALL_OFFSET +
                    CUE_HEIGHT / 2),
            );

            self.shoot_animation = .{
                .start_position = self.position.extend(0.0),
                .end_position = end_postion.extend(0.0),
                .duration = 0.2,
                .progress = 0.0,
            };
        }
        return false;
    }

    pub const ToScreenQuadsResult = struct {
        hovered: bool = false,
        upgrade_applied: bool = false,
    };
    pub fn to_screen_quads(
        self: *Cue,
        context: *GlobalContext,
        texture_id: Textures.Texture.Id,
        selected_upgrade: ?Item.Tag,
    ) ToScreenQuadsResult {
        var result: ToScreenQuadsResult = .{};
        const size: Vec2 = .{
            .x = @floatFromInt(context.texture_store.get_texture(texture_id).width),
            .y = @floatFromInt(context.texture_store.get_texture(texture_id).height),
        };

        var color_v4: Vec4 = .{};
        const is_cue_upgrade = if (selected_upgrade) |si| si.is_cue_upgrade() else false;
        if (is_cue_upgrade) {
            self.accumulator += context.dt * 1.5;
            color_v4 = color_v4.lerp(
                Color.WHITE.to_vec4_norm(),
                @abs(@sin(self.accumulator) * 0.6),
            );
        }

        result.hovered = self.hovered(context.input.mouse_pos_world);
        if (result.hovered) {
            color_v4 = color_v4.lerp(Color.WHITE.to_vec4_norm(), 0.5);
            if (is_cue_upgrade and context.input.lmb == .Released)
                result.upgrade_applied = self.add_upgrade(selected_upgrade.?);
        }

        const tint = Color.from_vec4_norm(color_v4);
        const object: Object2d = .{
            .type = .{ .TextureId = texture_id },
            .tint = tint,
            .transform = .{
                .position = self.position.extend(0.0),
                .rotation = self.rotation,
            },
            .size = size,
            .options = .{
                .with_tint = true,
            },
        };
        object.to_screen_quad(
            &context.camera,
            &context.texture_store,
            &context.screen_quads,
        );
        return result;
    }
};

pub const Item = struct {
    pub const Tag = enum(u8) {
        Invalid,
        BallSpiky,
        BallHealthy,
        BallArmored,
        BallLight,
        BallHeavy,
        BallAntisocial,
        BallGravity,
        BallRunner,
        BallRingOfLight,

        CueWiggleBall,
        CueScope,
        CueSecondBarrel,
        CueSilencer,
        CueRocketBooster,

        CueDefault,
        CueKar98K,
        CueCross,

        pub fn is_ball(self: Tag) bool {
            return self != .Invalid and
                @intFromEnum(self) < @intFromEnum(Tag.CueWiggleBall);
        }

        pub fn is_cue_upgrade(self: Tag) bool {
            return self != .Invalid and
                @intFromEnum(Tag.BallRingOfLight) < @intFromEnum(self) and
                @intFromEnum(self) < @intFromEnum(Tag.CueDefault);
        }

        pub fn is_cue(self: Tag) bool {
            return self != .Invalid and
                @intFromEnum(Tag.CueRocketBooster) < @intFromEnum(self);
        }
    };

    pub const Info = struct {
        texture_id: Textures.Texture.Id,
        name: []const u8,
        description: []const u8,
        price: i32,
    };

    pub const NormalDropRate = 0.5;
    pub const RareDropRate = 0.3;
    pub const EpicDropRate = 0.2;

    pub const NormalItems = [_]Tag{
        .BallSpiky,
        .BallHealthy,
        .BallArmored,
    };

    pub const RareItems = [_]Tag{
        .BallLight,
        .BallHeavy,
        .BallAntisocial,
        .BallGravity,
        .BallRunner,
        .CueWiggleBall,
        .CueScope,
        .CueSecondBarrel,
    };

    pub const EpicItems = [_]Tag{
        .BallRingOfLight,
        .CueSilencer,
        .CueRocketBooster,
        .CueKar98K,
        .CueCross,
    };

    pub const Infos = struct {
        infos: [@typeInfo(Tag).Enum.fields.len]Info,

        pub fn get(self: *const Infos, tag: Tag) *const Info {
            log.assert(
                @src(),
                @intFromEnum(tag) < @typeInfo(Tag).Enum.fields.len,
                "Trying to get item info for index: {d} out of {d}",
                .{ @intFromEnum(tag), @typeInfo(Tag).Enum.fields.len },
            );
            return &self.infos[@intFromEnum(tag)];
        }

        pub fn get_mut(self: *Infos, tag: Tag) *Info {
            log.assert(
                @src(),
                @intFromEnum(tag) < @typeInfo(Tag).Enum.fields.len,
                "Trying to get item info for index: {d} out of {d}",
                .{ @intFromEnum(tag), @typeInfo(Tag).Enum.fields.len },
            );
            return &self.infos[@intFromEnum(tag)];
        }
    };
};

pub const CueInventory = struct {
    cues: [MAX_CUE]Cue,
    cues_n: u8,
    owner: Owner,
    selected_index: u8,

    particles_effect: ParticleEffect,
    selected_cue_particles: Particles,

    const ParticleEffect = struct {
        position: Vec2 = .{},
        accumulator: f32 = 0.0,

        const HORIZONTAL_NUM = 20;
        const VERTICAL_NUM = 100;
        const TOTAL_NUM = HORIZONTAL_NUM * 2 + VERTICAL_NUM * 2;

        const HORIZONTAL_SPACING: f32 = @as(f32, AREA_WIDTH) / @as(f32, HORIZONTAL_NUM);
        const VERTICAL_SPACING: f32 = @as(f32, AREA_HEIGHT) / @as(f32, VERTICAL_NUM);
        const WAVE_AMP = 2.0;
        const WAVE_SPEED = 10.0;
        const LERP_SPEED = 0.3;
        const AREA_HEIGHT = 520;
        const AREA_WIDTH = 40;

        const COLOR_1: Vec4 = .{ .x = 80.0, .y = 0.0, .z = 0.0, .w = 128.0 };
        const COLOR_2: Vec4 = .{ .x = 180.0, .y = 32.0, .z = 16.0, .w = 255.0 };

        fn update(
            effect: *anyopaque,
            particle_index: u32,
            particle: *Particles.Particle,
            rng: *std.rand.DefaultPrng,
            dt: f32,
        ) void {
            _ = rng;
            _ = dt;
            const self: *const ParticleEffect = @alignCast(@ptrCast(effect));

            var position: Vec3 = undefined;
            var s: f32 = undefined;
            // TOP
            if (particle_index < HORIZONTAL_NUM) {
                const pi = @as(f32, @floatFromInt(particle_index));

                const top_left = self.position
                    .add(.{ .x = -AREA_WIDTH / 2, .y = -AREA_HEIGHT / 2 });
                s = @sin(self.accumulator + pi * 5.0);

                const particle_position = top_left
                    .add(.{
                    .x = HORIZONTAL_SPACING / 2.0 + HORIZONTAL_SPACING *
                        pi,
                    .y = s * WAVE_AMP,
                }).extend(0.0);
                position = particle_position;
            } else
            // BOT
            if (particle_index < HORIZONTAL_NUM * 2) {
                const pi = @as(f32, @floatFromInt(particle_index - HORIZONTAL_NUM));

                const bot_left = self.position
                    .add(.{ .x = -AREA_WIDTH / 2, .y = AREA_HEIGHT / 2 });
                s = @sin(-self.accumulator + pi * 5.0);

                const particle_position = bot_left
                    .add(.{
                    .x = HORIZONTAL_SPACING / 2.0 + HORIZONTAL_SPACING *
                        pi,
                    .y = s * WAVE_AMP,
                }).extend(0.0);
                position = particle_position;
            } else
            // LEFT
            if (particle_index < HORIZONTAL_NUM * 2 + VERTICAL_NUM) {
                const pi = @as(f32, @floatFromInt(particle_index - HORIZONTAL_NUM * 2));

                const top_left = self.position
                    .add(.{ .x = -AREA_WIDTH / 2, .y = -AREA_HEIGHT / 2 });
                s = @sin(-self.accumulator + pi * 5.0);

                const particle_position = top_left
                    .add(.{
                    .x = s * WAVE_AMP,
                    .y = VERTICAL_SPACING / 2.0 + VERTICAL_SPACING *
                        pi,
                }).extend(0.0);
                position = particle_position;
            } else
            // RIGHT
            {
                const pi = @as(f32, @floatFromInt(particle_index -
                    (HORIZONTAL_NUM * 2 +
                    VERTICAL_NUM)));

                const top_right = self.position
                    .add(.{ .x = AREA_WIDTH / 2, .y = -AREA_HEIGHT / 2 });
                s = @sin(self.accumulator + pi * 5.0);
                const particle_position = top_right
                    .add(.{
                    .x = s * WAVE_AMP,
                    .y = VERTICAL_SPACING / 2.0 + VERTICAL_SPACING *
                        pi,
                }).extend(0.0);
                position = particle_position;
            }

            particle.object.transform.position =
                particle.object.transform.position
                .lerp(position, LERP_SPEED);

            const color = COLOR_1.lerp(COLOR_2, (s + 1.0) / 2.0);
            particle.object.type = .{ .Color = Color.from_vec4_unchecked(color) };
        }
    };

    const MAX_CUE = 2;
    const CUE_STORAGE_POSITION_PLAYER: Vec2 = .{ .x = -564.0 };
    const CUE_STORAGE_ROTATION_PLAYER = 0.0;
    const CUE_STORAGE_POSITION_OPPONENT: Vec2 = .{ .x = 564.0 };
    const CUE_STORAGE_ROTATION_OPPONENT = std.math.pi;
    const CUE_STORAGE_WIDTH = 120;
    const CUE_STORAGE_HEIGHT = 500;
    const CUE_STORAGE_CUE_WIDTH = 60;

    pub fn init(context: *GlobalContext, owner: Owner) CueInventory {
        var self: CueInventory = undefined;
        self.owner = owner;
        self.reset();

        self.particles_effect = .{};
        self.selected_cue_particles = Particles.init(
            context.memory,
            ParticleEffect.TOTAL_NUM,
            .{ .Color = Color.BLUE },
            .{},
            .{ .x = 5.0, .y = 5.0 },
            0.0,
            3.0,
            true,
        );

        return self;
    }

    pub fn reset(self: *CueInventory) void {
        const p_r = self.cue_position_rotation(0);
        self.cues[0] =
            Cue.init(.CueDefault, p_r[0], p_r[1]);
        self.cues[1] =
            Cue.init(.Invalid, p_r[0], p_r[1]);
        self.cues_n = 1;
        self.selected_index = 0;
    }

    pub fn cue_position_rotation(self: CueInventory, index: u32) struct { Vec2, f32 } {
        return if (self.owner == .Player)
            .{
                CUE_STORAGE_POSITION_PLAYER.add(
                    .{
                        .x = -CUE_STORAGE_WIDTH / 2 +
                            CUE_STORAGE_CUE_WIDTH / 2 +
                            @as(f32, @floatFromInt(index)) * CUE_STORAGE_CUE_WIDTH,
                    },
                ),
                CUE_STORAGE_ROTATION_PLAYER,
            }
        else
            .{
                CUE_STORAGE_POSITION_OPPONENT.add(
                    .{
                        .x = -CUE_STORAGE_WIDTH / 2 +
                            CUE_STORAGE_CUE_WIDTH / 2 +
                            @as(f32, @floatFromInt(index)) * CUE_STORAGE_CUE_WIDTH,
                    },
                ),
                CUE_STORAGE_ROTATION_OPPONENT,
            };
    }

    pub fn add(self: *CueInventory, cue: Item.Tag) bool {
        log.assert(
            @src(),
            @intFromEnum(Item.Tag.CueKar98K) <= @intFromEnum(cue),
            "Trying to add item to the cue inventory",
            .{},
        );
        if (self.cues.len == self.cues_n)
            return false;

        const p_r = self.cue_position_rotation(self.cues_n);
        self.cues[self.cues_n] = Cue.init(cue, p_r[0], p_r[1]);
        self.cues_n += 1;
        return true;
    }

    pub fn remove(self: *CueInventory, cue: Item.Tag) void {
        for (self.cues[0..self.cues_n], 0..) |*it, i| {
            if (it == cue) {
                self.cues[i] = self.cues[self.cues_n - 1];
                self.cues_n -= 1;
            }
        }
    }

    pub fn selected(self: *CueInventory) *Cue {
        return &self.cues[self.selected_index];
    }

    pub fn update_and_draw(
        self: *CueInventory,
        context: *GlobalContext,
        selected_upgrade: ?Item.Tag,
        can_select: bool,
    ) bool {
        for (&self.cues, 0..) |*cue, i| {
            if (i != self.selected_index)
                cue.move_storage();
        }

        const panel = UiPanel.init(
            if (self.owner == .Player)
                CUE_STORAGE_POSITION_PLAYER
            else
                CUE_STORAGE_POSITION_OPPONENT,
            context.assets.cue_background,
            null,
        );
        panel.to_screen_quad(context);

        self.particles_effect.accumulator += context.dt * ParticleEffect.WAVE_SPEED;
        self.particles_effect.position = self.cue_position_rotation(self.selected_index)[0];
        self.selected_cue_particles.update(&self.particles_effect, &ParticleEffect.update, 0.0);
        self.selected_cue_particles.to_screen_quad(
            &context.camera,
            &context.texture_store,
            &context.screen_quads,
        );

        var upgrade_applied: bool = false;
        for (self.cues[0..self.cues_n], 0..) |*cue, i| {
            if (cue.tag == .Invalid)
                continue;

            const cue_info = context.item_infos.get(cue.tag);
            const r = cue.to_screen_quads(
                context,
                cue_info.texture_id,
                selected_upgrade,
            );

            if (can_select and r.hovered and context.input.lmb == .Pressed)
                self.selected_index = @intCast(i);
            upgrade_applied = upgrade_applied or r.upgrade_applied;
        }
        return upgrade_applied;
    }
};

pub const ItemInventory = struct {
    items: [MAX_ITEMS]Item.Tag,

    owner: Owner,
    selected_index: ?u8,
    hovered_index: ?u8,
    dashed_line: UiDashedLine,

    const MAX_ITEMS = 5;
    const ITEMS_POSITION_PLAYER: Vec2 = .{ .y = 315.0 };
    const ITEMS_POSITION_OPPONENT: Vec2 = .{ .y = -315.0 };
    const ITEMS_WIDTH = 321;
    const ITEMS_LEFT_GAP = 10;
    const ITEM_WIDTH = 53;
    const ITEM_HEIGHT = 53;
    const ITEM_GAP = 9;

    pub const INFO_PANEL_OFFSET: Vec2 = .{ .y = -180.0 };
    pub const INFO_PANEL_SIZE: Vec2 = .{ .x = 280.0, .y = 300.0 };

    pub fn init(owner: Owner) ItemInventory {
        return .{
            .items = .{.Invalid} ** MAX_ITEMS,
            .owner = owner,
            .selected_index = null,
            .hovered_index = null,
            .dashed_line = undefined,
        };
    }

    pub fn item_position(self: ItemInventory, index: u32) Vec2 {
        return if (self.owner == .Player)
            ITEMS_POSITION_PLAYER.add(
                .{
                    .x = -ITEMS_WIDTH / 2 +
                        ITEMS_LEFT_GAP +
                        ITEM_WIDTH / 2 +
                        @as(f32, @floatFromInt(index)) * (ITEM_WIDTH + ITEM_GAP),
                },
            )
        else
            ITEMS_POSITION_OPPONENT.add(
                .{
                    .x = -ITEMS_WIDTH / 2 +
                        ITEMS_LEFT_GAP +
                        ITEM_WIDTH / 2 +
                        @as(f32, @floatFromInt(index)) * (ITEM_WIDTH + ITEM_GAP),
                },
            );
    }

    pub fn add(self: *ItemInventory, item: Item.Tag) bool {
        log.assert(
            @src(),
            @intFromEnum(item) < @intFromEnum(Item.Tag.CueKar98K),
            "Trying to add cue to the item inventory",
            .{},
        );
        for (&self.items) |*it| {
            if (it.* == .Invalid) {
                it.* = item;
                return true;
            }
        }
        return false;
    }

    pub fn remove(self: *ItemInventory, item: Item.Tag) void {
        for (&self.items) |*it| {
            if (it.* == item) {
                it.* = .Invalid;
            }
        }
    }

    pub fn item_hovered(self: ItemInventory, item_index: u8, mouse_pos: Vec2) bool {
        const ip = self.item_position(item_index);
        const collision_rectangle: Physics.Rectangle = .{
            .size = .{
                .x = ITEM_WIDTH,
                .y = ITEM_HEIGHT,
            },
        };
        return Physics.point_rectangle_intersect(
            mouse_pos,
            collision_rectangle,
            ip,
        );
    }

    pub fn selected(self: ItemInventory) ?Item.Tag {
        if (self.selected_index) |si| {
            return self.items[si];
        } else {
            return null;
        }
    }

    pub fn selected_position(self: ItemInventory) ?Vec2 {
        if (self.selected_index) |si| {
            return self.item_position(si);
        } else {
            return null;
        }
    }

    pub fn item_used(self: *ItemInventory) void {
        if (self.selected_index) |si| {
            self.items[si] = .Invalid;
        }
    }

    pub fn update(
        self: *ItemInventory,
        context: *GlobalContext,
        turn_owner: Owner,
    ) void {
        self.dashed_line.end = context.input.mouse_pos_world;
        var hover_anything: bool = false;
        for (self.items, 0..) |item, i| {
            if (item == .Invalid)
                continue;

            // only player can hover to show info panel
            const hovered_player =
                self.item_hovered(@intCast(i), context.player_input.mouse_pos_world);
            if (hovered_player) {
                self.hovered_index = @intCast(i);
            }

            // only turn owner can select
            const hovered_input = self.item_hovered(@intCast(i), context.input.mouse_pos_world);
            if (self.owner == turn_owner and
                hovered_input and
                context.input.lmb == .Pressed)
            {
                if (turn_owner == .Player and context.state.in_game_shop)
                    continue;

                log.info(@src(), "{any}: Selected item index: {d}", .{ self.owner, i });
                self.selected_index = @intCast(i);
                self.dashed_line.start = self.item_position(@intCast(i));
            }

            hover_anything = hover_anything or hovered_player or hovered_input;
        }
        if (!hover_anything) {
            self.hovered_index = null;
            if (context.input.lmb == .Released) {
                self.selected_index = null;
            }
        }
    }

    pub fn to_screen_quads(
        self: *ItemInventory,
        context: *GlobalContext,
    ) void {
        const bot_panel = UiPanel.init(
            if (self.owner == .Player)
                ITEMS_POSITION_PLAYER
            else
                ITEMS_POSITION_OPPONENT,
            context.assets.items_background,
            null,
        );
        bot_panel.to_screen_quad(context);

        for (self.items, 0..) |item, i| {
            if (item == .Invalid)
                continue;

            const item_info = context.item_infos.infos[@intFromEnum(item)];
            const ip = self.item_position(@intCast(i));

            var object: Object2d = .{
                .type = .{ .TextureId = item_info.texture_id },
                .transform = .{
                    .position = ip.extend(0.0),
                },
                .options = .{ .no_scale_rotate = true },
            };
            if (self.hovered_index) |hi| {
                if (hi == i) {
                    object.tint = Color.BLUE;
                    object.options.with_tint = true;
                    add_info_panel(context, self.owner, ip, item_info);
                }
            }
            if (self.selected_index) |si| {
                if (si == i) {
                    object.tint = Color.GREEN;
                    object.options.with_tint = true;
                }
                self.dashed_line.to_screen_quads(context);
            }
            object.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
        }
    }

    fn add_info_panel(
        context: *GlobalContext,
        owner: Owner,
        ip: Vec2,
        item_info: Item.Info,
    ) void {
        const panel_position = if (!context.state.in_game_shop and owner == .Player)
            ip.add(INFO_PANEL_OFFSET)
        else
            ip.add(INFO_PANEL_OFFSET.neg());
        const info_panel = UiPanel.init(
            panel_position,
            context.assets.button,
            null,
        );
        info_panel.to_screen_quad(context);

        _ = UiText.to_screen_quads(
            context,
            panel_position.add(.{ .y = -40.0 }),
            32.0,
            "{s}",
            .{item_info.name},
            null,
        );
        _ = UiText.to_screen_quads(
            context,
            panel_position.add(.{ .y = -20.0 }),
            32.0,
            "{s}",
            .{item_info.description},
            null,
        );
    }
};

pub const Shop = struct {
    rng: std.rand.DefaultPrng,
    items: [MAX_ITEMS]Item.Tag,
    reroll_cost: i32 = 10,

    selected_item: ?u8 = null,

    pub const CAMERA_IN_GAME_SHOP: Vec2 = .{ .y = 617 };
    const ITEM_PANEL_SIZE: Vec2 = .{ .x = 400.0, .y = 500.0 };
    const ITEM_PANEL_GAP = 30;
    const ITEM_PANEL_DIFF = ITEM_PANEL_SIZE.x + ITEM_PANEL_GAP;
    const REROLL_BUTTON_POSITION: Vec2 = CAMERA_IN_GAME_SHOP.add(.{ .y = 335.0 });

    const TEXT_SIZE_NAME = 60;
    const TEXT_SIZE_DESCRIPTION = 50;
    const TEXT_SIZE_PRICE = 60;

    const ITEM_HILIGHT_TINT = Color.from_parts(128, 10, 10, 128);

    const MAX_ITEMS = 3;
    const REROLL_COST_INC = 1.2;

    pub fn reset(self: *Shop) void {
        self.rng = std.rand.DefaultPrng.init(@intCast(std.time.microTimestamp()));
        self.reroll();
        self.reroll_cost = 10;
        self.selected_item = null;
    }

    pub fn reroll(self: *Shop) void {
        for (&self.items) |*item| {
            item.* = self.random_item();
            log.assert(
                @src(),
                @intFromEnum(item.*) < @typeInfo(Item.Tag).Enum.fields.len,
                "",
                .{},
            );
            log.info(@src(), "reroll item: {any}", .{item.*});
        }
    }

    pub fn random_item(self: *Shop) Item.Tag {
        const random = self.rng.random();
        const rarity = random.float(f32);
        if (rarity < Item.NormalDropRate) {
            const item_f32 = random.float(f32);
            const item_index: u32 = @intFromFloat(item_f32 * Item.NormalItems.len - 1);
            log.assert(@src(), item_index < Item.NormalItems.len - 1, "", .{});
            return Item.NormalItems[item_index];
        } else if (rarity < Item.RareDropRate) {
            const item_f32 = random.float(f32);
            const item_index: u32 = @intFromFloat(item_f32 * Item.RareItems.len - 1);
            log.assert(@src(), item_index < Item.RareItems.len - 1, "", .{});
            return Item.RareItems[item_index];
        } else {
            const item_f32 = random.float(f32);
            const item_index: u32 = @intFromFloat(item_f32 * Item.EpicItems.len - 1);
            log.assert(@src(), item_index < Item.EpicItems.len - 1, "", .{});
            return Item.EpicItems[item_index];
        }
    }

    pub fn remove_selected_item(self: *Shop) void {
        log.assert(
            @src(),
            self.selected_item != null,
            "Trying to remove selected item from a shop, but there is not selected item",
            .{},
        );
        self.items[self.selected_item.?] = .Invalid;
    }

    pub fn draw_item(
        self: Shop,
        context: *GlobalContext,
        index: u8,
    ) bool {
        const item = self.items[index];
        if (item == .Invalid)
            return false;

        const position = CAMERA_IN_GAME_SHOP.add(.{
            .x = -ITEM_PANEL_DIFF / 2.0 * (MAX_ITEMS - 1) +
                @as(f32, @floatFromInt(index)) * ITEM_PANEL_DIFF,
            .y = 20.0,
        });

        const collision_rectangle: Physics.Rectangle = .{
            .size = ITEM_PANEL_SIZE,
        };
        const is_hovered = Physics.point_rectangle_intersect(
            context.input.mouse_pos_world,
            collision_rectangle,
            position,
        );

        const color: ?Color = if (is_hovered) ITEM_HILIGHT_TINT else null;
        const item_panel = UiPanel.init(
            position,
            context.assets.shop_panel,
            color,
        );
        item_panel.to_screen_quad(context);
        const item_info = context.item_infos.get(item);
        const object: Object2d = .{
            .type = .{ .TextureId = item_info.texture_id },
            .transform = .{
                .position = position.extend(0.0),
            },
            .options = .{ .no_scale_rotate = true },
        };
        object.to_screen_quad(
            &context.camera,
            &context.texture_store,
            &context.screen_quads,
        );

        _ = UiText.to_screen_quads(
            context,
            position.add(.{ .y = -220.0 }),
            TEXT_SIZE_NAME,
            "{s}",
            .{item_info.name},
            null,
        );
        _ = UiText.to_screen_quads(
            context,
            position.add(.{ .y = 0 }),
            TEXT_SIZE_DESCRIPTION,
            "{s}",
            .{item_info.description},
            null,
        );
        _ = UiText.to_screen_quads(
            context,
            position.add(.{ .x = -10.0, .y = 220 }),
            TEXT_SIZE_PRICE,
            "Cost: {d}",
            .{item_info.price},
            null,
        );
        UiPanel.init(
            position.add(.{ .x = 90.0, .y = 205 }),
            context.assets.souls,
            null,
        ).to_screen_quad(context);

        return is_hovered;
    }

    pub fn update_and_draw(self: *Shop, context: *GlobalContext) ?Item.Tag {
        var item_clicked: ?Item.Tag = null;
        for (0..self.items.len) |i| {
            const hovered = self.draw_item(
                context,
                @intCast(i),
            );
            if (hovered and context.input.lmb == .Pressed) {
                item_clicked = self.items[i];
                self.selected_item = @intCast(i);
            }
        }

        const S = struct {
            fn on_press(s: anytype) void {
                s.reroll();
            }
        };
        UI.add_button(
            context,
            REROLL_BUTTON_POSITION,
            "Reroll",
            S.on_press,
            self,
        );
        return item_clicked;
    }
};
