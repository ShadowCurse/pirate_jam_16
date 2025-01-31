const std = @import("std");
const stygian = @import("stygian_runtime");

const Allocator = std.mem.Allocator;

const log = stygian.log;
// This configures log level for the runtime
pub const log_options = log.Options{
    .level = .Info,
};

const Tracing = stygian.tracing;
pub const tracing_options = Tracing.Options{
    .max_measurements = 256,
    .enabled = true,
};

const sdl = stygian.bindings.sdl;

const Color = stygian.color.Color;
const ScreenQuads = stygian.screen_quads;

const Object2d = stygian.objects.Object2d;

const _audio = stygian.audio;
const Audio = _audio.Audio;
const SoundtrackId = _audio.SoundtrackId;

const Font = stygian.font;
const Memory = stygian.memory;
const Textures = stygian.textures;
const Start = stygian.platform.start;
const Events = stygian.platform.event;
const SoftRenderer = stygian.soft_renderer.renderer;
const CameraController2d = stygian.camera.CameraController2d;

const _math = stygian.math;
const Vec2 = _math.Vec2;

const _animations = @import("animations.zig");
const StateChangeAnimation = _animations.StateChangeAnimation;

const _objects = @import("objects.zig");
const Item = _objects.Item;

const UI = @import("ui.zig");
const Game = @import("game.zig");
const GamePhysics = @import("physics.zig");

pub const State = packed struct(u8) {
    main_menu: bool = true,
    rules: bool = false,
    in_game: bool = false,
    in_game_shop: bool = false,
    won: bool = false,
    lost: bool = false,
    debug: bool = false,
    _: u1 = 0,
};

pub const Input = struct {
    lmb: KeyState = .None,
    rmb: KeyState = .None,
    space: KeyState = .None,
    mouse_pos: Vec2 = .{},
    mouse_pos_world: Vec2 = .{},

    pub const KeyState = enum {
        None,
        Pressed,
        Released,
    };

    pub fn update(
        self: *Input,
        events: []const Events.Event,
        window_width: u32,
        window_height: u32,
        mouse_x: u32,
        mouse_y: u32,
        camera: *const CameraController2d,
    ) void {
        _ = window_height;

        const screen_scale = 1280.0 / @as(f32, @floatFromInt(window_width));
        self.mouse_pos = (Vec2{
            .x = @floatFromInt(mouse_x),
            .y = @floatFromInt(mouse_y),
        }).mul_f32(screen_scale);
        self.mouse_pos_world = self.mouse_pos
            .add(camera.position.xy());

        self.lmb = .None;
        self.rmb = .None;
        self.space = .None;

        for (events) |event| {
            switch (event) {
                .Mouse => |mouse| {
                    switch (mouse) {
                        .Button => |button| {
                            if (button.key == .LMB)
                                self.lmb = if (button.type == .Pressed) .Pressed else .Released;
                            if (button.key == .RMB)
                                self.rmb = if (button.type == .Pressed) .Pressed else .Released;
                        },
                        else => {},
                    }
                },
                .Keyboard => |key| {
                    switch (key.key) {
                        .SPACE => self.space = if (key.type == .Pressed) .Pressed else .Released,
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
};

pub const Assets = struct {
    player_hand: Textures.Texture.Id,
    opponent_hand: Textures.Texture.Id,

    ball_player: Textures.Texture.Id,
    ball_opponent: Textures.Texture.Id,
    ball_info_panel: Textures.Texture.Id,
    cue_info_panel: Textures.Texture.Id,
    table: Textures.Texture.Id,
    button: Textures.Texture.Id,
    button_hover: Textures.Texture.Id,
    button_reroll: Textures.Texture.Id,
    button_reroll_hover: Textures.Texture.Id,
    under_hp_bar: Textures.Texture.Id,
    under_hp_bar_turn: Textures.Texture.Id,
    blood: Textures.Texture.Id,
    souls: Textures.Texture.Id,

    cue_background: Textures.Texture.Id,
    shop_panel: Textures.Texture.Id,
    items_background: Textures.Texture.Id,

    ball_spiky: Textures.Texture.Id,
    ball_healthy: Textures.Texture.Id,
    ball_armored: Textures.Texture.Id,
    ball_light: Textures.Texture.Id,
    ball_heavy: Textures.Texture.Id,
    ball_antisocial: Textures.Texture.Id,
    ball_gravity: Textures.Texture.Id,
    ball_runner: Textures.Texture.Id,
    ball_ring_of_light: Textures.Texture.Id,

    scope_icon: Textures.Texture.Id,
    silencer_icon: Textures.Texture.Id,
    rocket_booster_icon: Textures.Texture.Id,
    scope: Textures.Texture.Id,
    silencer: Textures.Texture.Id,
    rocket_booster: Textures.Texture.Id,

    cue_default: Textures.Texture.Id,
    cue_kar98k: Textures.Texture.Id,
    cue_cross: Textures.Texture.Id,

    sound_background: SoundtrackId,
    sound_item_use: SoundtrackId,
    sound_ball_hit: SoundtrackId,
    sound_ball_pocket: SoundtrackId,
    sound_cue_hit: SoundtrackId,
    sound_kar98k_fire: SoundtrackId,
    sound_cross_hit: SoundtrackId,
};

pub const GlobalContext = struct {
    memory: *Memory,
    screen_quads: ScreenQuads,
    texture_store: Textures.Store,
    audio: Audio,
    global_audio_volume: f32,
    font: Font,
    assets: Assets,
    state: State,
    state_change_animation: StateChangeAnimation,
    input: Input,
    player_input: Input,
    camera: CameraController2d,
    item_infos: Item.Infos,
    dt: f32,

    pub fn init(
        self: *GlobalContext,
        memory: *Memory,
        window_width: u32,
        window_height: u32,
    ) void {
        self.memory = memory;
        self.screen_quads = ScreenQuads.init(memory, 8192) catch unreachable;
        self.texture_store.init(memory) catch unreachable;
        self.audio.init(memory, 1.0) catch unreachable;
        self.global_audio_volume = 0.3;
        self.font = Font.init(memory, &self.texture_store, "assets/NewRocker-Regular.ttf", 64);

        self.assets.player_hand =
            self.texture_store.load(self.memory, "assets/player_hand.png");
        self.assets.opponent_hand =
            self.texture_store.load(self.memory, "assets/opponent_hand.png");

        self.assets.ball_player = self.texture_store.load(
            self.memory,
            "assets/ball_prototype.png",
        );
        self.assets.ball_opponent = self.assets.ball_player;
        self.assets.ball_info_panel =
            self.texture_store.load(memory, "assets/ball_info_panel.png");
        self.assets.cue_info_panel =
            self.texture_store.load(memory, "assets/cue_info_panel.png");

        self.assets.table = self.texture_store.load(memory, "assets/table.png");
        self.assets.cue_default = self.texture_store.load(memory, "assets/cue_default.png");
        self.assets.cue_kar98k = self.texture_store.load(memory, "assets/cue_kar98k.png");
        self.assets.cue_cross = self.texture_store.load(memory, "assets/cue_cross.png");

        self.assets.button = self.texture_store.load(memory, "assets/button.png");
        self.assets.button_hover = self.texture_store.load(memory, "assets/button_hover.png");
        self.assets.button_reroll = self.texture_store.load(memory, "assets/button_reroll.png");
        self.assets.button_reroll_hover =
            self.texture_store.load(memory, "assets/button_reroll_hover.png");

        self.assets.under_hp_bar = self.texture_store.load(memory, "assets/under_hp_bar.png");
        self.assets.under_hp_bar_turn =
            self.texture_store.load(memory, "assets/under_hp_bar_turn.png");
        self.assets.blood = self.texture_store.load(memory, "assets/blood.png");
        self.assets.souls = self.texture_store.load(memory, "assets/souls.png");

        self.assets.cue_background = self.texture_store.load(memory, "assets/cue_background.png");
        self.assets.shop_panel = self.texture_store.load(memory, "assets/shop_panel.png");
        self.assets.items_background =
            self.texture_store.load(memory, "assets/items_background.png");

        self.assets.ball_spiky = self.texture_store.load(memory, "assets/ball_spiky.png");
        self.assets.ball_healthy = self.texture_store.load(memory, "assets/ball_healthy.png");
        self.assets.ball_armored = self.texture_store.load(memory, "assets/ball_armored.png");
        self.assets.ball_light = self.texture_store.load(memory, "assets/ball_light.png");
        self.assets.ball_heavy = self.texture_store.load(memory, "assets/ball_heavy.png");
        // self.assets.ball_antisocial = self.texture_store.load(memory, "assets/ball_bouncy.png");
        // self.assets.ball_gravity = self.texture_store.load(memory, "assets/ball_gravity.png");
        // self.assets.ball_runner = self.texture_store.load(memory, "assets/ball_runner.png");
        // self.assets.ball_ring_of_light =
        //     self.texture_store.load(memory, "assets/ball_ring_of_light.png");

        self.assets.scope_icon = self.texture_store.load(memory, "assets/scope_icon.png");
        self.assets.silencer_icon =
            self.texture_store.load(memory, "assets/silencer_icon.png");
        self.assets.rocket_booster_icon =
            self.texture_store.load(memory, "assets/rocket_booster_icon.png");
        self.assets.scope = self.texture_store.load(memory, "assets/scope_prototype.png");
        self.assets.silencer = self.texture_store.load(memory, "assets/silencer_prototype.png");
        self.assets.rocket_booster =
            self.texture_store.load(memory, "assets/rocket_booster_prototype.png");

        self.assets.sound_background = self.audio.load_wav(memory, "assets/background.wav");
        self.assets.sound_item_use = self.audio.load_wav(memory, "assets/item_use.wav");
        self.assets.sound_ball_hit = self.audio.load_wav(memory, "assets/ball_hit.wav");
        self.assets.sound_ball_pocket = self.audio.load_wav(memory, "assets/ball_pocket.wav");
        self.assets.sound_cue_hit = self.audio.load_wav(memory, "assets/cue_hit.wav");
        self.assets.sound_kar98k_fire = self.audio.load_wav(memory, "assets/kar98k_fire.wav");
        self.assets.sound_cross_hit = self.audio.load_wav(memory, "assets/cross_hit.wav");

        self.state = .{};
        self.state_change_animation = .{
            .camera = &self.camera,
            .state = &self.state,
        };

        self.input = .{};
        self.player_input = .{};

        self.camera = CameraController2d.init(window_width, window_height);
        self.camera.position = self.camera.position
            .add(UI.CAMERA_MAIN_MENU.extend(0.0));

        inline for (&self.item_infos.infos, 0..) |*info, i| {
            info.* = .{
                .texture_id = Textures.Texture.ID_DEBUG,
                .name = std.fmt.comptimePrint("item info: {d}", .{i}),
                .description = std.fmt.comptimePrint("item description: {d}", .{i}),
                .price = 5,
            };
        }
        self.item_infos.get_mut(.BallSpiky).* = .{
            .texture_id = self.assets.ball_spiky,
            .name = "Spiky ball",
            .description =
            \\Increases the ball
            \\damage by 5
            ,
            .price = 15,
        };
        self.item_infos.get_mut(.BallHealthy).* = .{
            .texture_id = self.assets.ball_healthy,
            .name = "Healthy ball",
            .description =
            \\Increases the ball
            \\HP by 5
            ,
            .price = 10,
        };
        self.item_infos.get_mut(.BallArmored).* = .{
            .texture_id = self.assets.ball_armored,
            .name = "Armored ball",
            .description =
            \\Increases the damage 
            \\negation of the ball by 5%
            ,
            .price = 15,
        };
        self.item_infos.get_mut(.BallLight).* = .{
            .texture_id = self.assets.ball_light,
            .name = "Light ball",
            .description = "Makes a ball lighter",
            .price = 5,
        };
        self.item_infos.get_mut(.BallHeavy).* = .{
            .texture_id = self.assets.ball_heavy,
            .name = "Heavy ball",
            .description = "Makes a ball heavier",
            .price = 5,
        };
        self.item_infos.get_mut(.BallAntisocial).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Bouncy ball",
            .description =
            \\Ball gains additional
            \\velocity when collides
            \\with other balls
            ,
            .price = 20,
        };
        self.item_infos.get_mut(.BallGravity).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Antigravity ball",
            .description =
            \\Pushes all balls away
            \\in a small radius
            ,
            .price = 100,
        };
        self.item_infos.get_mut(.BallRunner).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Runner ball",
            .description =
            \\Restores HP proportional
            \\to the distance traveled
            \\during the turn
            ,
            .price = 150,
        };
        self.item_infos.get_mut(.BallRingOfLight).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Ring of light",
            .description =
            \\Adds a ring of light around 
            \\the ball. Other balls can collide
            \\with the ring once per turn.
            \\All collisions follow same
            \\heal/damage rules as if balls
            \\did actually collide.
            ,
            .price = 80,
        };

        self.item_infos.get_mut(.CueScope).* = .{
            .texture_id = self.assets.scope_icon,
            .name = "Sniper scope",
            .description =
            \\Adds a trajectory line
            \\when aiming the cue
            ,
            .price = 15,
        };
        self.item_infos.get_mut(.CueSilencer).* = .{
            .texture_id = self.assets.silencer_icon,
            .name = "Silencer",
            .description =
            \\The ball you hit  will
            \\ghost through friendly
            \\balls and only collide
            \\with the first enemy ball
            ,
            .price = 40,
        };
        self.item_infos.get_mut(.CueRocketBooster).* = .{
            .texture_id = self.assets.rocket_booster_icon,
            .name = "Rocket booster",
            .description =
            \\Increases the strength
            \\of the hit
            ,
            .price = 25,
        };

        self.item_infos.get_mut(.CueDefault).* = .{
            .texture_id = self.assets.cue_default,
            .name = "Default cue",
            .description = "",
            .price = 0,
        };
        self.item_infos.get_mut(.CueKar98K).* = .{
            .texture_id = self.assets.cue_kar98k,
            .name = "Kar98k",
            .description =
            \\In addition to hitting
            \\the ball, deals 5 damage
            \\to all enemy balls in
            \\a straight line
            ,
            .price = 100,
        };
        self.item_infos.get_mut(.CueCross).* = .{
            .texture_id = self.assets.cue_cross,
            .name = "Silver cross",
            .description =
            \\In addition to hitting 
            \\the ball, heals all allied
            \\balls by 15 and damages all
            \\enemy balls by 5 in a small 
            \\radius around the hit ball
            ,
            .price = 100,
        };

        self.dt = 0.0;
    }

    pub fn alloc(self: *GlobalContext) Allocator {
        return self.memory.scratch_alloc();
    }

    pub fn reset(self: *GlobalContext) void {
        self.screen_quads.reset();
    }

    pub fn play_audio(
        self: *GlobalContext,
        audio_id: SoundtrackId,
        left_volume: f32,
        right_volume: f32,
    ) void {
        self.audio.play(
            audio_id,
            left_volume * self.global_audio_volume,
            right_volume * self.global_audio_volume,
        );
    }

    pub fn adjust_volume(self: *GlobalContext, delta: f32) void {
        self.global_audio_volume += delta;
        self.global_audio_volume = std.math.clamp(self.global_audio_volume, 0.0, 1.0);

        if (self.audio.is_playing(self.assets.sound_background))
            self.audio.set_volume(
                self.assets.sound_background,
                self.global_audio_volume,
                0.1,
                self.global_audio_volume,
                0.1,
            );
    }

    pub fn update(
        self: *GlobalContext,
        events: []const Events.Event,
        window_width: u32,
        window_height: u32,
        mouse_x: u32,
        mouse_y: u32,
        dt: f32,
    ) void {
        self.player_input.update(
            events,
            window_width,
            window_height,
            mouse_x,
            mouse_y,
            &self.camera,
        );
        if (self.input.space == .Pressed)
            self.state.debug = !self.state.debug;
        self.dt = dt;
        self.state_change_animation.update(dt);
    }
};

const Runtime = struct {
    soft_renderer: SoftRenderer,

    context: GlobalContext,
    game: Game,

    const Self = @This();

    fn init(
        self: *Self,
        window: *sdl.SDL_Window,
        memory: *Memory,
        window_width: u32,
        window_height: u32,
    ) !void {
        self.soft_renderer = SoftRenderer.init(memory, window, window_width, window_height);
        self.context.init(memory, window_width, window_height);
        self.game.init(&self.context);
    }

    fn run(
        self: *Self,
        memory: *Memory,
        dt: f32,
        events: []const Events.Event,
        window_width: u32,
        window_height: u32,
        mouse_x: u32,
        mouse_y: u32,
    ) void {
        const scratch_alloc = memory.scratch_alloc();
        self.context.reset();

        if (!self.context.audio.is_playing(self.context.assets.sound_background))
            self.context.play_audio(
                self.context.assets.sound_background,
                1.0,
                1.0,
            );

        self.context.update(
            events,
            window_width,
            window_height,
            mouse_x,
            mouse_y,
            dt,
        );
        self.game.update_and_draw(&self.context);

        if (self.context.state.debug) {
            const TaceableTypes = struct {
                SoftRenderer,
                ScreenQuads,
                _objects.Ball,
                GamePhysics,
            };
            Tracing.prepare_next_frame(TaceableTypes);
            Tracing.to_screen_quads(
                TaceableTypes,
                scratch_alloc,
                &self.context.screen_quads,
                &self.context.font,
                32.0,
            );
            Tracing.zero_current(TaceableTypes);
        }

        const mouse_rect: Object2d = .{
            .type = .{ .TextureId = self.context.assets.player_hand },
            .transform = .{
                .position = self.context.player_input.mouse_pos_world.extend(0.0),
            },
            .size = .{
                .x = @floatFromInt(
                    self.context.texture_store.get_texture(self.context.assets.player_hand).width,
                ),
                .y = @floatFromInt(
                    self.context.texture_store.get_texture(self.context.assets.player_hand).height,
                ),
            },
        };
        mouse_rect.to_screen_quad(
            &self.context.camera,
            &self.context.texture_store,
            &self.context.screen_quads,
        );

        self.soft_renderer.start_rendering();
        self.context.screen_quads.render(
            &self.soft_renderer,
            &self.context.texture_store,
            0.0,
            false,
        );
        self.soft_renderer.end_rendering();
    }
};

pub export fn runtime_main(
    window: *sdl.SDL_Window,
    events_ptr: [*]const Events.Event,
    events_len: usize,
    memory: *Memory,
    dt: f32,
    data: ?*anyopaque,
) *anyopaque {
    memory.reset_frame();

    var events: []const Events.Event = undefined;
    events.ptr = events_ptr;
    events.len = events_len;
    var runtime_ptr: ?*Runtime = @alignCast(@ptrCast(data));

    var window_width: i32 = undefined;
    var window_height: i32 = undefined;
    sdl.SDL_GetWindowSize(window, &window_width, &window_height);

    const window_width_u32: u32 = @intCast(window_width);
    const window_height_u32: u32 = @intCast(window_height);

    var mouse_x: i32 = undefined;
    var mouse_y: i32 = undefined;
    _ = sdl.SDL_GetMouseState(&mouse_x, &mouse_y);

    const mouse_x_u32: u32 = @intCast(@max(mouse_x, 0));
    const mouse_y_u32: u32 = @intCast(@max(mouse_y, 0));

    if (runtime_ptr == null) {
        log.info(@src(), "First time runtime init", .{});
        const game_alloc = memory.game_alloc();
        runtime_ptr = game_alloc.create(Runtime) catch unreachable;
        runtime_ptr.?.init(window, memory, window_width_u32, window_height_u32) catch unreachable;
        _ = sdl.SDL_ShowCursor(0);
    } else {
        var runtime = runtime_ptr.?;
        runtime.run(
            memory,
            dt,
            events,
            window_width_u32,
            window_height_u32,
            mouse_x_u32,
            mouse_y_u32,
        );
    }
    return @ptrCast(runtime_ptr);
}
