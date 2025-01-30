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

const Game = @import("game.zig");
const Owner = Game.Owner;

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
    hp: f32 = 10,
    max_hp: f32 = 10,
    damage: f32 = 5,
    heal: f32 = 1,
    armor: f32 = 0.0,

    hit_by_ring_of_light: bool = false,
    particles_gravity: Particles,
    particles_runner: Particles,
    particles_ring_of_light: Particles,

    pub const GravityParticleEffect = struct {
        pub const NUM = 100;
        pub const RADIUS = 50.0;
        pub const FORCE = 100.0;
        const COLOR: Color = Color.from_parts(41, 39, 117, 255);

        fn update(
            _ball: *anyopaque,
            particle_index: u32,
            particle: *Particles.Particle,
            rng: *std.rand.DefaultPrng,
            dt: f32,
        ) void {
            _ = rng;
            _ = dt;
            const ball: *const Ball = @alignCast(@ptrCast(_ball));
            const angle = std.math.pi * 2.0 / @as(f32, NUM) *
                @as(f32, @floatFromInt(particle_index));
            const c = @cos(angle);
            const s = @sin(angle);
            const additional_offset: Vec3 = .{ .x = c, .y = s, .z = 0.0 };
            particle.object.transform.position =
                ball.physics.body.position.extend(0.0)
                .add(additional_offset.mul_f32(GravityParticleEffect.RADIUS));
            particle.object.options = .{ .no_scale_rotate = true, .no_alpha_blend = true };
        }
    };

    pub const RunnerParticleEffect = struct {
        pub const HEAL_PER_UNIT = 0.02;
        const NUM = 100;
        const RADIUS = 8.0;
        const GAP: f32 = (RunnerParticleEffect.RADIUS * 2.0) / @as(f32, NUM);
        const LERP_BASE = 0.2;
        const LERP_SPEED = 0.2;
        const MAX_COLOR_VELOCITY = 100.0;
        const COLOR: Color = Color.from_parts(76, 158, 0, 255);

        fn update(
            _ball: *anyopaque,
            particle_index: u32,
            particle: *Particles.Particle,
            rng: *std.rand.DefaultPrng,
            dt: f32,
        ) void {
            _ = rng;
            _ = dt;
            const ball: *const Ball = @alignCast(@ptrCast(_ball));
            const neg_vel = ball.physics.body.velocity.neg();
            const neg_vel_len = neg_vel.len();
            const pi = @as(f32, @floatFromInt(particle_index));
            if (0.1 < neg_vel_len) {
                const neg_vel_norm = neg_vel.mul_f32(1.0 / neg_vel_len);
                // left perp
                const orth_norm = neg_vel_norm.perp();
                const p_x = RunnerParticleEffect.RADIUS - GAP / 2.0 - GAP * pi;
                const lerp_mul = @abs(p_x) / RunnerParticleEffect.RADIUS;
                const position_trail: Vec3 =
                    ball.physics.body.position
                    .add(orth_norm.mul_f32(p_x))
                    .extend(0.0);

                const angle = std.math.pi * 2.0 / @as(f32, NUM) * pi;
                const c = @cos(angle);
                const s = @sin(angle);
                const offset: Vec2 = .{ .x = c, .y = s };
                const position_stand: Vec3 =
                    ball.physics.body.position
                    .add(offset.mul_f32(RunnerParticleEffect.RADIUS))
                    .extend(0.0);

                const m = @max(
                    0.0,
                    @min(
                        1.0,
                        (MAX_COLOR_VELOCITY - neg_vel_len) / MAX_COLOR_VELOCITY,
                    ),
                );
                const position = position_stand.lerp(position_trail, 1.0 - m);

                particle.object.transform.position =
                    (particle.object.transform.position
                    .lerp(position, LERP_BASE + LERP_SPEED * lerp_mul));
            } else {
                const angle = std.math.pi * 2.0 / @as(f32, NUM) * pi;
                const c = @cos(angle);
                const s = @sin(angle);
                const offset: Vec2 = .{ .x = c, .y = s };
                const position: Vec3 =
                    ball.physics.body.position
                    .add(offset.mul_f32(RunnerParticleEffect.RADIUS))
                    .extend(0.0);

                particle.object.transform.position =
                    (particle.object.transform.position
                    .lerp(position, LERP_BASE));
            }

            particle.object.options = .{ .no_scale_rotate = true };
        }
    };

    pub const RingOfLightParticleEffect = struct {
        pub const NUM = 100;
        pub const RADIUS = 30.0;
        pub const STRENGTH_MUL = 0.2;
        const COLOR: Color = Color.from_parts(255, 225, 71, 255);

        fn update(
            _ball: *anyopaque,
            particle_index: u32,
            particle: *Particles.Particle,
            rng: *std.rand.DefaultPrng,
            dt: f32,
        ) void {
            _ = rng;
            _ = dt;
            const ball: *const Ball = @alignCast(@ptrCast(_ball));
            const angle = std.math.pi * 2.0 / @as(f32, NUM) *
                @as(f32, @floatFromInt(particle_index));
            const c = @cos(angle);
            const s = @sin(angle);
            const additional_offset: Vec3 = .{ .x = c, .y = s, .z = 0.0 };
            particle.object.transform.position =
                ball.physics.body.position.extend(0.0)
                .add(additional_offset.mul_f32(RingOfLightParticleEffect.RADIUS));
            particle.object.options = .{ .no_scale_rotate = true, .no_alpha_blend = true };
        }
    };

    // This is sprite size dependent because I don't scale balls for perf gains.
    pub const RADIUS = 10;
    pub const HP_TEXT_SIZE = 24;
    pub const UPGRADE_HILIGHT_COLOR = Color.from_parts(255, 0, 0, 64);
    pub const HOVER_HILIGHT_COLOR = Color.from_parts(0, 0, 255, 64);
    pub const LOW_HP_COLOR_V4: Vec4 = Color.from_parts(12, 15, 21, 64).to_vec4_norm();

    pub const trace = Tracing.Measurements(struct {
        to_object_2d: Tracing.Counter,
        previous_positions_to_object_2d: Tracing.Counter,
    });

    pub fn init(
        context: *GlobalContext,
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

            .particles_gravity = Particles.init(
                context.memory,
                GravityParticleEffect.NUM,
                .{ .Color = GravityParticleEffect.COLOR },
                physics.body.position.extend(0.0),
                .{ .x = 4.0, .y = 4.0 },
                0.0,
                3.0,
                true,
            ),
            .particles_runner = Particles.init(
                context.memory,
                RunnerParticleEffect.NUM,
                .{ .Color = RunnerParticleEffect.COLOR },
                physics.body.position.extend(0.0),
                .{ .x = 3.0, .y = 3.0 },
                0.0,
                3.0,
                true,
            ),
            .particles_ring_of_light = Particles.init(
                context.memory,
                RingOfLightParticleEffect.NUM,
                .{ .Color = RingOfLightParticleEffect.COLOR },
                physics.body.position.extend(0.0),
                .{ .x = 4.0, .y = 4.0 },
                0.0,
                3.0,
                true,
            ),
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
                if (self.armor == 0.9)
                    return false;
                self.armor = @min(0.9, self.armor + 0.05);
            },
            .BallLight => {
                self.physics.body.inv_mass += 0.1;
            },
            .BallHeavy => {
                self.physics.body.inv_mass -= 0.1;
            },
            .BallAntisocial => {
                if (self.physics.state.antisocial)
                    return false;
                self.physics.state.antisocial = true;
            },
            .BallGravity => {
                if (self.physics.state.gravity)
                    return false;
                self.physics.state.gravity = true;
            },
            .BallRunner => {
                if (self.physics.state.runner)
                    return false;
                self.physics.state.runner = true;
            },
            .BallRingOfLight => {
                if (self.physics.state.ring_of_light)
                    return false;
                self.physics.state.ring_of_light = true;
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
        const hp_percent: f32 = self.hp / self.max_hp;
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

    pub fn draw_effect(self: *Ball, context: *GlobalContext) void {
        if (self.physics.state.gravity) {
            self.particles_gravity.update(self, &GravityParticleEffect.update, 0.0);
            self.particles_gravity.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
        }
        if (self.physics.state.runner) {
            self.particles_runner.update(self, &RunnerParticleEffect.update, 0.0);
            self.particles_runner.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
        }
        if (self.physics.state.ring_of_light) {
            self.particles_ring_of_light.update(self, &RingOfLightParticleEffect.update, 0.0);
            self.particles_ring_of_light.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
        }
    }

    pub fn draw_info_panel(self: Ball, context: *GlobalContext) void {
        const INFO_PANEL_TEXT_SIZE = 35;
        const INFO_PANEL_OFFSET: Vec2 = .{ .y = -180.0 };

        const panel_position = self.physics.body.position.add(INFO_PANEL_OFFSET);
        const info_panel = UiPanel.init(
            panel_position,
            context.assets.ball_info_panel,
            null,
        );
        info_panel.to_screen_quad(context);

        {
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .x = -110.0, .y = -100.0 }),
                INFO_PANEL_TEXT_SIZE,
                "HP: {d:.0}",
                .{self.hp},
                .{ .center = false },
            );
        }

        {
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .x = -110.0, .y = -70.0 }),
                INFO_PANEL_TEXT_SIZE,
                "Damage: {d:.0}",
                .{self.damage},
                .{ .center = false },
            );
        }

        {
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .x = -110.0, .y = -40.0 }),
                INFO_PANEL_TEXT_SIZE,
                "Armor: {d:.0}",
                .{self.armor},
                .{ .center = false },
            );
        }

        {
            const s = if (self.physics.state.antisocial) "yes" else "no";
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .x = -110.0, .y = -10.0 }),
                INFO_PANEL_TEXT_SIZE,
                "Bouncy: {s}",
                .{s},
                .{ .center = false },
            );
        }

        {
            const s = if (self.physics.state.gravity) "yes" else "no";
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .x = -110.0, .y = 20.0 }),
                INFO_PANEL_TEXT_SIZE,
                "Gravity: {s}",
                .{s},
                .{ .center = false },
            );
        }

        {
            const s = if (self.physics.state.runner) "yes" else "no";
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .x = -110.0, .y = 50.0 }),
                INFO_PANEL_TEXT_SIZE,
                "Runner: {s}",
                .{s},
                .{ .center = false },
            );
        }

        {
            const s = if (self.physics.state.ring_of_light) "yes" else "no";
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .x = -110.0, .y = 80.0 }),
                INFO_PANEL_TEXT_SIZE,
                "Ring of light: {s}",
                .{s},
                .{ .center = false },
            );
        }

        {
            const s = if (self.physics.state.ghost) "yes" else "no";
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .x = -110.0, .y = 110.0 }),
                INFO_PANEL_TEXT_SIZE,
                "Ghost: {s}",
                .{s},
                .{ .center = false },
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
    kar98k_animation: ?Ka98KAnimation,
    cross_animation: CrossAnimation,
    accumulator: f32,

    initial_hit_strength: f32 = 0.0,

    dashed_line: UI.UiDashedLineStatic = undefined,
    scope: bool = false,
    silencer: bool = false,
    rocket_booster: bool = false,

    pub const Ka98KAnimation = struct {
        duration: f32 = 0.0,
        progress: f32 = 0.0,
        position: Vec3 = .{},
        rotation: f32 = 0.0,

        pub const DURATION = 0.2;
        pub const P_1 = 500.0;
        pub const T_1 = DURATION * DURATION / 4.0 * P_1;
        pub const P_2 = 250.0;
        pub const T_2 = DURATION * DURATION / 4.0 * P_2;
        pub const P_3 = 125.0;
        pub const T_3 = DURATION * DURATION / 4.0 * P_3;
        pub const WIDTH = 5.0;
        pub const HEIGHT = 1000.0;
        pub const DAMAGE = 5.0;

        pub fn update(self: *Ka98KAnimation, context: *GlobalContext) bool {
            const x = self.progress - self.duration / 2.0;
            const x_sq = x * x;
            const width_mul_1 = -(P_1 * x_sq) + T_1;
            const width_mul_2 = -(P_2 * x_sq) + T_2;
            const width_mul_3 = -(P_3 * x_sq) + T_3;
            const transparency_1: u8 = @intFromFloat(width_mul_1 / T_1 * 255.0 * 0.3);
            const transparency_2: u8 = @intFromFloat(width_mul_2 / T_2 * 255.0 * 0.5);
            const transparency_3: u8 = @intFromFloat(width_mul_3 / T_3 * 255.0);
            {
                const color = Color.from_parts(255, 0, 0, transparency_1);
                const trail: Object2d = .{
                    .type = .{ .Color = color },
                    .transform = .{
                        .position = self.position,
                        .rotation = self.rotation,
                    },
                    .size = .{
                        .x = WIDTH * width_mul_1,
                        .y = HEIGHT,
                    },
                    .options = .{},
                };
                trail.to_screen_quad(
                    &context.camera,
                    &context.texture_store,
                    &context.screen_quads,
                );
            }
            {
                const color = Color.from_parts(252, 116, 0, transparency_2);
                const trail: Object2d = .{
                    .type = .{ .Color = color },
                    .transform = .{
                        .position = self.position,
                        .rotation = self.rotation,
                    },
                    .size = .{
                        .x = WIDTH * width_mul_2,
                        .y = HEIGHT,
                    },
                    .options = .{},
                };
                trail.to_screen_quad(
                    &context.camera,
                    &context.texture_store,
                    &context.screen_quads,
                );
            }
            {
                const color = Color.from_parts(252, 168, 0, transparency_3);
                const trail: Object2d = .{
                    .type = .{ .Color = color },
                    .transform = .{
                        .position = self.position,
                        .rotation = self.rotation,
                    },
                    .size = .{
                        .x = WIDTH * width_mul_3,
                        .y = HEIGHT,
                    },
                    .options = .{},
                };
                trail.to_screen_quad(
                    &context.camera,
                    &context.texture_store,
                    &context.screen_quads,
                );
            }

            self.progress += context.dt;
            return self.duration <= self.progress;
        }
    };

    pub const CrossAnimation = struct {
        duration: f32 = 0.0,
        progress: f32 = 0.0,
        particles: Particles,
        position: Vec2 = .{},

        pub const DAMAGE = 5;
        pub const HEAL = 15;
        pub const NUM_ANIM = 300;
        pub const NUM_STATIC = 100;
        pub const NUM = NUM_ANIM + NUM_STATIC;
        pub const RAYS = 20;
        pub const RAY_LAYERS = NUM / RAYS;
        pub const RADIUS = 60.0;
        pub const DURATION = 1.0;
        pub const P = 500.0;
        pub const T = DURATION * DURATION / 4.0 * P;
        const COLOR_ANIM: Color = Color.from_parts(249, 228, 0, 255);
        const COLOR_STATIC: Color = Color.from_parts(255, 175, 0, 255);

        pub fn init(context: *GlobalContext) CrossAnimation {
            return .{
                .particles = Particles.init(
                    context.memory,
                    NUM,
                    .{ .Color = Color.BLUE },
                    .{},
                    .{ .x = 5.0, .y = 5.0 },
                    0.0,
                    3.0,
                    true,
                ),
            };
        }

        pub fn start(self: *CrossAnimation, position: Vec2) void {
            self.progress = 0.0;
            self.duration = DURATION;
            self.position = position;
            for (self.particles.active_particles) |*ap| {
                ap.object.transform.position = position.extend(0.0);
            }
        }

        pub fn finished(self: CrossAnimation) bool {
            return self.duration <= self.progress;
        }

        pub fn update(self: *CrossAnimation, context: *GlobalContext) bool {
            self.particles.update(self, &CrossAnimation.particles_update, 0.0);
            self.particles.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
            self.progress += context.dt;
            return self.duration <= self.progress;
        }

        fn particles_update(
            _self: *anyopaque,
            particle_index: u32,
            particle: *Particles.Particle,
            rng: *std.rand.DefaultPrng,
            dt: f32,
        ) void {
            _ = rng;
            _ = dt;
            const self: *const CrossAnimation = @alignCast(@ptrCast(_self));
            if (particle_index < NUM_ANIM) {
                const ray_index = particle_index % RAYS;
                const ray_layer_index: f32 = @floatFromInt(@divFloor(particle_index, RAYS));
                const ri: f32 = @floatFromInt(ray_index);
                const p = self.progress / self.duration;
                const pp = p * (RAY_LAYERS - ray_layer_index) / RAY_LAYERS;

                const angle = std.math.pi * 2.0 / @as(f32, RAYS) *
                    ri +
                    std.math.pi / 16.0 * @sin(pp * ray_layer_index);
                const c = @cos(angle);
                const s = @sin(angle);
                const offset: Vec2 = .{ .x = c, .y = s };
                particle.object.transform.position =
                    self.position
                    .add(offset.mul_f32(p * RADIUS + ray_layer_index * 2.0))
                    .extend(0.0);

                const x = self.progress - self.duration / 2.0;
                const x_sq = x * x;
                const m = -(P * x_sq) + T;
                const transparency: u8 = @intFromFloat(m / T * 255.0 * 0.5);
                var color = COLOR_ANIM;
                color.format.a = transparency;
                particle.object.type = .{ .Color = color };
            } else {
                const pi: f32 = @floatFromInt(particle_index - NUM_ANIM);
                const angle = std.math.pi * 2.0 / @as(f32, NUM_STATIC) * pi;
                const c = @cos(angle);
                const s = @sin(angle);
                const offset: Vec2 = .{ .x = c, .y = s };
                particle.object.transform.position =
                    self.position
                    .add(offset.mul_f32(RADIUS))
                    .extend(0.0);

                const x = self.progress - self.duration / 2.0;
                const x_sq = x * x;
                const m = -(P * x_sq) + T;
                const transparency: u8 = @intFromFloat(m / T * 255.0);
                var color = COLOR_STATIC;
                color.format.a = transparency;
                particle.object.type = .{ .Color = color };
            }
        }
    };

    pub const CUE_HEIGHT = 512.0;
    pub const CUE_WIDTH = 10.0;
    pub const KAR98K_CUE_HEIGHT = 448.0;
    pub const KAR98K_CUE_WIDTH = 20.0;

    pub const AIM_BALL_OFFSET = Ball.RADIUS + 5;

    pub const SILENCER_LENGTH = 100.0;
    pub const ROCKET_BOOSTER_BONUS_STRENGTH = 500.0;

    pub const MAX_STRENGTH = 150.0;
    pub const DEFAULT_STRENGTH_MUL = 4.0;
    pub const KAR98K_STRENGTH = 1000.0;
    pub const CROSS_STRENGTH_MUL = 3.0;

    pub const UPGRADE_HILIGHT_COLOR = Color.from_parts(255, 0, 0, 64);
    pub const HOVER_HILIGHT_COLOR = Color.from_parts(0, 0, 255, 64);

    pub fn init(
        context: *GlobalContext,
        tag: Item.Tag,
        storage_position: Vec2,
        storage_rotation: f32,
    ) Cue {
        return .{
            .tag = tag,
            .position = storage_position,
            .rotation = storage_rotation,
            .storage_position = storage_position,
            .storage_rotation = storage_rotation,
            .shoot_animation = null,
            .kar98k_animation = null,
            .cross_animation = CrossAnimation.init(context),
            .accumulator = 0.0,
        };
    }

    pub fn reset(
        self: *Cue,
        tag: Item.Tag,
        storage_position: Vec2,
        storage_rotation: f32,
    ) void {
        self.tag = tag;
        self.position = storage_position;
        self.rotation = storage_rotation;
        self.storage_position = storage_position;
        self.storage_rotation = storage_rotation;
        self.shoot_animation = null;
        self.kar98k_animation = null;
        self.accumulator = 0.0;
        self.scope = false;
        self.silencer = false;
        self.rocket_booster = false;
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
            .CueScope => {
                if (self.scope)
                    return false
                else
                    self.scope = true;
            },
            .CueSilencer => {
                if (self.silencer)
                    return false
                else
                    self.silencer = true;
            },
            .CueRocketBooster => {
                if (self.rocket_booster)
                    return false
                else
                    self.rocket_booster = true;
            },
            else => {
                log.err(@src(), "Trying to add unsupported ugrdate to cue: {any}", .{upgrade});
                return false;
            },
        }

        return true;
    }

    pub fn play_hit_sound(self: Cue, context: *GlobalContext, strength: f32) void {
        const c = @cos(-self.rotation);
        const s = @sin(-self.rotation);
        const along_the_cue: Vec2 = .{ .x = s, .y = -c };
        const silencer_offset: f32 = if (self.silencer) SILENCER_LENGTH else 0.0;
        const end_postion = self.position.add(
            along_the_cue
                .mul_f32(AIM_BALL_OFFSET + silencer_offset +
                CUE_HEIGHT / 2),
        );

        const hit_volume = std.math.clamp(
            strength / 800.0,
            0.0,
            1.0,
        );
        const right_volume = (end_postion.x + 1280.0 / 2.0) / 1280.0;
        const left_volume = 1.0 - right_volume;
        switch (self.tag) {
            .CueDefault => context.play_audio(
                context.assets.sound_cue_hit,
                left_volume * hit_volume,
                right_volume * hit_volume,
            ),
            .CueKar98K => context.play_audio(
                context.assets.sound_kar98k_fire,
                left_volume * hit_volume * 0.15,
                right_volume * hit_volume * 0.15,
            ),
            .CueCross => context.play_audio(
                context.assets.sound_cross_hit,
                left_volume,
                right_volume,
            ),
            else => unreachable,
        }
    }

    pub fn move_storage(self: *Cue) void {
        self.position =
            self.position.add(self.storage_position.sub(self.position).mul_f32(0.2));
        self.rotation += (self.storage_rotation - self.rotation) * 0.2;
    }

    pub fn move_aiming(
        self: *Cue,
        context: *GlobalContext,
        ball_position: Vec2,
        hit_vector: Vec2,
        offset: f32,
    ) void {
        const hv_len = hit_vector.len();
        if (hv_len == 0.0)
            return;

        const hv_normalized = hit_vector.normalize();

        const use_offset = if (self.tag == .CueKar98K) 0 else offset;
        const silencer_offset: f32 = if (self.silencer) SILENCER_LENGTH else 0.0;
        const cue_postion =
            ball_position.add(
            hv_normalized
                .mul_f32(AIM_BALL_OFFSET + silencer_offset +
                CUE_HEIGHT / 2 + use_offset),
        );
        const cross = hv_normalized.cross(.{ .y = 1 });
        const d = hv_normalized.dot(.{ .y = 1 });
        const cue_rotation = if (cross < 0.0) -std.math.acos(d) else std.math.acos(d);

        self.position =
            self.position.add(cue_postion.sub(self.position).mul_f32(0.2));
        self.rotation += (cue_rotation - self.rotation) * 0.2;

        if (self.scope) {
            const rect = Physics.Rectangle{
                .size = .{ .x = 927, .y = 473 },
            };

            const c = @cos(-self.rotation);
            const s = @sin(-self.rotation);
            const along_the_cue: Vec2 = .{ .x = s, .y = -c };
            const m: f32 = if (self.tag == .CueKar98K)
                KAR98K_CUE_HEIGHT / 2.0
            else
                CUE_HEIGHT / 2.0;

            const p = self.position.add(along_the_cue.mul_f32(m));
            if (Physics.ray_rectangle_intersection(
                p,
                along_the_cue,
                rect,
                .{},
            )) |intersection| {
                self.dashed_line.start = p;
                self.dashed_line.end = intersection;
                self.dashed_line.to_screen_quads(context);
            }
        }
    }

    pub fn move_shoot(
        self: *Cue,
        context: *GlobalContext,
        ball_position: Vec2,
        hit_vector: Vec2,
        dt: f32,
    ) ?f32 {
        const booster_bonus_strength: f32 =
            if (self.rocket_booster)
            ROCKET_BOOSTER_BONUS_STRENGTH
        else
            0.0;
        switch (self.tag) {
            .CueDefault => {
                if (self.shoot_animation) |*sm| {
                    var v3 = self.position.extend(0.0);
                    if (sm.update(&v3, dt)) {
                        self.shoot_animation = null;
                        self.position = v3.xy();
                        const strength = self.initial_hit_strength *
                            DEFAULT_STRENGTH_MUL +
                            booster_bonus_strength;
                        self.play_hit_sound(context, strength);
                        return strength;
                    }
                    self.position = v3.xy();
                } else {
                    const hv_normalized = hit_vector.normalize();
                    const silencer_offset: f32 = if (self.silencer) SILENCER_LENGTH else 0.0;
                    const end_postion = ball_position.add(
                        hv_normalized
                            .mul_f32(AIM_BALL_OFFSET + silencer_offset +
                            CUE_HEIGHT / 2),
                    );

                    self.shoot_animation = .{
                        .start_position = self.position.extend(0.0),
                        .end_position = end_postion.extend(0.0),
                        .duration = 0.2,
                        .progress = 0.0,
                    };
                }
            },
            .CueKar98K => {
                if (self.kar98k_animation) |*ka| {
                    if (ka.update(context)) {
                        log.info(@src(), "kar98k_animation finished", .{});
                        self.kar98k_animation = null;
                        const strength = KAR98K_STRENGTH +
                            booster_bonus_strength;
                        self.play_hit_sound(context, strength);
                        return strength;
                    }
                } else {
                    const hv_neg_normalized = hit_vector.neg().normalize();
                    const beam_position = ball_position.add(
                        hv_neg_normalized
                            .mul_f32(Ka98KAnimation.HEIGHT / 2),
                    );
                    self.kar98k_animation = .{
                        .duration = Ka98KAnimation.DURATION,
                        .progress = 0.0,
                        .position = beam_position.extend(0.0),
                        .rotation = self.rotation,
                    };
                }
            },
            .CueCross => {
                if (self.shoot_animation) |*sm| {
                    var v3 = self.position.extend(0.0);
                    if (sm.update(&v3, dt)) {
                        log.info(@src(), "Cross creating cross animation", .{});
                        self.shoot_animation = null;
                        self.position = v3.xy();
                        self.play_hit_sound(context, 0.0);
                        self.cross_animation.start(ball_position);
                        return null;
                    }
                    self.position = v3.xy();
                } else {
                    if (!self.cross_animation.finished()) {
                        if (self.cross_animation.update(context)) {
                            log.info(@src(), "Cross finished cross animation", .{});
                            return self.initial_hit_strength *
                                CROSS_STRENGTH_MUL +
                                booster_bonus_strength;
                        }
                    } else {
                        log.info(@src(), "Cross creating shoot animation", .{});
                        const hv_normalized = hit_vector.normalize();
                        const silencer_offset: f32 = if (self.silencer) SILENCER_LENGTH else 0.0;
                        const end_postion = ball_position.add(
                            hv_normalized
                                .mul_f32(AIM_BALL_OFFSET + silencer_offset +
                                CUE_HEIGHT / 2),
                        );

                        self.shoot_animation = .{
                            .start_position = self.position.extend(0.0),
                            .end_position = end_postion.extend(0.0),
                            .duration = 0.2,
                            .progress = 0.0,
                        };
                    }
                }
            },
            else => unreachable,
        }
        return null;
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
        {
            const object: Object2d = .{
                .type = .{ .TextureId = texture_id },
                .tint = tint,
                .transform = .{
                    .position = self.position.extend(0.0),
                    .rotation = self.rotation,
                },
                .size = .{
                    .x = @floatFromInt(context.texture_store.get_texture(texture_id).width),
                    .y = @floatFromInt(context.texture_store.get_texture(texture_id).height),
                },
                .options = .{
                    .with_tint = true,
                },
            };
            object.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
        }

        if (self.scope) {
            const tid = context.assets.scope;
            const object: Object2d = .{
                .type = .{ .TextureId = tid },
                .tint = tint,
                .transform = .{
                    .position = self.position.extend(0.0),
                    .rotation = self.rotation,
                },
                .size = .{
                    .x = @floatFromInt(context.texture_store.get_texture(tid).width),
                    .y = @floatFromInt(context.texture_store.get_texture(tid).height),
                },
                .options = .{
                    .with_tint = true,
                },
            };
            object.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
        }

        if (self.silencer) {
            const tid = context.assets.silencer;
            const c = @cos(-self.rotation);
            const s = @sin(-self.rotation);
            const offset: Vec2 = .{ .x = s, .y = -c };
            const m: f32 = if (self.tag == .CueKar98K)
                KAR98K_CUE_HEIGHT / 2.0
            else
                CUE_HEIGHT / 2.0;

            const object: Object2d = .{
                .type = .{ .TextureId = tid },
                .tint = tint,
                .transform = .{
                    .position = self.position
                        .add(offset.mul_f32(m + SILENCER_LENGTH / 2.0))
                        .extend(0.0),
                    .rotation = self.rotation,
                },
                .size = .{
                    .x = @floatFromInt(context.texture_store.get_texture(tid).width),
                    .y = @floatFromInt(context.texture_store.get_texture(tid).height),
                },
                .options = .{
                    .with_tint = true,
                },
            };
            object.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
        }

        if (self.rocket_booster) {
            const tid = context.assets.rocket_booster;
            const c = @cos(-self.rotation);
            const s = @sin(-self.rotation);
            const offset: Vec2 = .{ .x = -s, .y = c };
            const m: f32 = if (self.tag == .CueKar98K)
                KAR98K_CUE_HEIGHT / 2.0
            else
                CUE_HEIGHT / 2.0;

            const object: Object2d = .{
                .type = .{ .TextureId = tid },
                .tint = tint,
                .transform = .{
                    .position = self.position.add(offset.mul_f32(m)).extend(0.0),
                    .rotation = self.rotation,
                },
                .size = .{
                    .x = @floatFromInt(context.texture_store.get_texture(tid).width),
                    .y = @floatFromInt(context.texture_store.get_texture(tid).height),
                },
                .options = .{
                    .with_tint = true,
                },
            };
            object.to_screen_quad(
                &context.camera,
                &context.texture_store,
                &context.screen_quads,
            );
        }

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

        CueScope,
        CueSilencer,
        CueRocketBooster,

        CueDefault,
        CueKar98K,
        CueCross,

        pub fn is_ball(self: Tag) bool {
            return self != .Invalid and
                @intFromEnum(self) < @intFromEnum(Tag.CueScope);
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
        price: f32,
    };

    pub const NormalDropRate = 0.5;
    pub const RareDropRate = 0.3;
    pub const EpicDropRate = 0.2;

    pub const NormalItems = [_]Tag{
        // .BallSpiky,
        // .BallHealthy,
        // .BallArmored,

        .BallSpiky,
        .BallHealthy,
        .BallArmored,
        .BallLight,
        .BallHeavy,
        .BallAntisocial,
        .BallGravity,
        .BallRunner,
        .BallRingOfLight,

        .CueScope,
        .CueSilencer,
        .CueRocketBooster,

        .CueKar98K,
        .CueCross,
    };

    pub const RareItems = [_]Tag{
        .BallLight,
        .BallHeavy,
        .BallAntisocial,
        .BallGravity,
        .BallRunner,
        .CueScope,
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

        const HORIZONTAL_NUM = 40;
        const VERTICAL_NUM = 520;
        const TOTAL_NUM = HORIZONTAL_NUM * 2 + VERTICAL_NUM * 2;

        const HORIZONTAL_SPACING: f32 = @as(f32, AREA_WIDTH) / @as(f32, HORIZONTAL_NUM);
        const VERTICAL_SPACING: f32 = @as(f32, AREA_HEIGHT) / @as(f32, VERTICAL_NUM);
        const WAVE_AMP = 2.0;
        const WAVE_SPEED = 10.0;
        const WAVE_LEN = 0.2;
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
                s = @sin(self.accumulator + pi * WAVE_LEN);

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
                s = @sin(-self.accumulator + pi * WAVE_LEN);

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
                s = @sin(-self.accumulator + pi * WAVE_LEN);

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
                s = @sin(self.accumulator + pi * WAVE_LEN);
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
            particle.object.options = .{ .no_scale_rotate = true, .no_alpha_blend = true };
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

        const p_r = self.cue_position_rotation(0);
        self.cues[0] = Cue.init(context, .CueDefault, p_r[0], p_r[1]);
        self.cues[1] = Cue.init(context, .Invalid, p_r[0], p_r[1]);
        self.cues_n = 1;
        self.selected_index = 0;

        self.particles_effect = .{};
        self.selected_cue_particles = Particles.init(
            context.memory,
            ParticleEffect.TOTAL_NUM,
            .{ .Color = Color.BLUE },
            .{},
            .{ .x = 2.0, .y = 2.0 },
            0.0,
            3.0,
            true,
        );

        return self;
    }

    pub fn reset(self: *CueInventory) void {
        const p_r = self.cue_position_rotation(0);
        self.cues[0].reset(.CueDefault, p_r[0], p_r[1]);
        self.cues[1].reset(.Invalid, p_r[0], p_r[1]);
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
        self.cues[self.cues_n].reset(cue, p_r[0], p_r[1]);
        self.cues_n += 1;
        return true;
    }

    pub fn remove(self: *CueInventory, cue: Item.Tag) void {
        if (cue == .CueDefault)
            return;
        self.cues[1].reset(.Invalid, .{}, 0.0);
        self.cues_n -= 1;
        self.selected_index = 0;
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

        self.draw_info_panel(context);

        return upgrade_applied;
    }

    pub fn draw_info_panel(self: *CueInventory, context: *GlobalContext) void {
        const INFO_PANEL_PLAYER_POSITION: Vec2 = .{ .x = -370.0 };
        const INFO_PANEL_OPPONENT_POSITION: Vec2 = .{ .x = 370.0 };
        const INFO_PANEL_TEXT_SIZE = 35;

        var hovered_cue_index: ?usize = null;
        for (&self.cues, 0..) |*cue, i| {
            if (!cue.hovered(context.input.mouse_pos_world) and
                !cue.hovered(context.player_input.mouse_pos_world))
            {
                continue;
            } else {
                hovered_cue_index = i;
                break;
            }
        }
        if (hovered_cue_index == null)
            return;

        const hovered_cue = self.cues[hovered_cue_index.?];

        const panel_position = if (self.owner == .Player)
            INFO_PANEL_PLAYER_POSITION
        else
            INFO_PANEL_OPPONENT_POSITION;

        const info_panel = UiPanel.init(
            panel_position,
            context.assets.cue_info_panel,
            null,
        );
        info_panel.to_screen_quad(context);

        {
            const s = if (hovered_cue.scope) "yes" else "no";
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .x = -110.0, .y = -20.0 }),
                INFO_PANEL_TEXT_SIZE,
                "Scope: {s}",
                .{s},
                .{ .center = false },
            );
        }

        {
            const s = if (hovered_cue.silencer) "yes" else "no";
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .x = -110.0, .y = 10.0 }),
                INFO_PANEL_TEXT_SIZE,
                "Silencer: {s}",
                .{s},
                .{ .center = false },
            );
        }

        {
            const s = if (hovered_cue.rocket_booster) "yes" else "no";
            _ = UiText.to_screen_quads(
                context,
                panel_position.add(.{ .x = -110.0, .y = 40.0 }),
                INFO_PANEL_TEXT_SIZE,
                "Rocket booster: {s}",
                .{s},
                .{ .center = false },
            );
        }
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

    pub const INFO_PANEL_OFFSET: Vec2 = .{ .y = -300.0 };
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
                    object.tint = Color.from_parts(250, 250, 250, 32);
                    object.options.with_tint = true;
                    info_panel(context, self.owner, ip, item);
                }
            }
            if (self.selected_index) |si| {
                if (si == i) {
                    object.tint = Color.from_parts(186, 149, 17, 128);
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

    fn info_panel(
        context: *GlobalContext,
        owner: Owner,
        ip: Vec2,
        item: Item.Tag,
    ) void {
        const panel_position = if (!context.state.in_game_shop and owner == .Player)
            ip.add(INFO_PANEL_OFFSET)
        else
            ip.add(INFO_PANEL_OFFSET.neg());

        _ = Shop.draw_item(context, item, panel_position, false);
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
    const TEXT_SIZE_DESCRIPTION = 35;
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
            const item_index = random.uintLessThan(u32, Item.NormalItems.len);
            log.assert(@src(), item_index < Item.NormalItems.len, "", .{});
            return Item.NormalItems[item_index];
        } else if (rarity < Item.RareDropRate) {
            const item_index = random.uintLessThan(u32, Item.RareItems.len);
            log.assert(@src(), item_index < Item.RareItems.len, "", .{});
            return Item.RareItems[item_index];
        } else {
            const item_index = random.uintLessThan(u32, Item.EpicItems.len);
            log.assert(@src(), item_index < Item.EpicItems.len, "", .{});
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

    pub fn item_position(
        index: u8,
    ) Vec2 {
        return CAMERA_IN_GAME_SHOP.add(.{
            .x = -ITEM_PANEL_DIFF / 2.0 * (MAX_ITEMS - 1) +
                @as(f32, @floatFromInt(index)) * ITEM_PANEL_DIFF,
            .y = 20.0,
        });
    }

    pub fn draw_item(
        context: *GlobalContext,
        item: Item.Tag,
        position: Vec2,
        show_price: bool,
    ) bool {
        if (item == .Invalid)
            return false;

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
        const item_offset: Vec2 = if (item.is_cue()) .{} else .{ .y = -100.0 };
        const object: Object2d = .{
            .type = .{ .TextureId = item_info.texture_id },
            .transform = .{
                .position = position.add(item_offset).extend(0.0),
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
            .{},
        );
        _ = UiText.to_screen_quads(
            context,
            position.add(.{ .y = -30.0 }),
            TEXT_SIZE_DESCRIPTION,
            "{s}",
            .{item_info.description},
            .{},
        );
        if (show_price) {
            _ = UiText.to_screen_quads(
                context,
                position.add(.{ .x = -10.0, .y = 220 }),
                TEXT_SIZE_PRICE,
                "Cost: {d}",
                .{item_info.price},
                .{},
            );
            UiPanel.init(
                position.add(.{ .x = 90.0, .y = 205 }),
                context.assets.souls,
                null,
            ).to_screen_quad(context);
        }

        return is_hovered;
    }

    pub fn update_and_draw(self: *Shop, context: *GlobalContext, game: *Game) ?Item.Tag {
        var item_clicked: ?Item.Tag = null;
        for (0..self.items.len) |i| {
            const ip = item_position(@intCast(i));
            const item = self.items[i];
            const hovered = draw_item(
                context,
                item,
                ip,
                true,
            );
            if (hovered and context.input.lmb == .Pressed) {
                item_clicked = self.items[i];
                self.selected_item = @intCast(i);
            }
        }

        const BUTTON_TEXT_OFFSET: Vec2 = .{ .x = -10.0, .y = 13.0 };
        var panel = UiPanel.init(
            REROLL_BUTTON_POSITION,
            context.assets.button_reroll,
            null,
        );
        const panel_hovered = panel.hovered(context);
        if (panel_hovered)
            panel.texture_id = context.assets.button_reroll_hover;
        panel.to_screen_quad(context);
        UiText.to_screen_quads(
            context,
            REROLL_BUTTON_POSITION.add(BUTTON_TEXT_OFFSET),
            50.0,
            "Reroll: 5",
            .{},
            .{},
        );
        UiPanel.init(
            REROLL_BUTTON_POSITION.add(.{ .x = 77.0, .y = 3.0 }),
            context.assets.souls,
            null,
        ).to_screen_quad(context);

        if (panel_hovered and context.player_input.lmb == .Pressed) {
            if (5 < game.player.hp_overhead) {
                game.player.hp_overhead -= 5;
                self.reroll();
            }
        }
        return item_clicked;
    }
};
