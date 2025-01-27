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
    settings: bool = false,
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
    table: Textures.Texture.Id,
    cue_defult: Textures.Texture.Id,
    button: Textures.Texture.Id,
    cue_background: Textures.Texture.Id,
    items_background: Textures.Texture.Id,
    shop_panel: Textures.Texture.Id,
    blood: Textures.Texture.Id,
    souls: Textures.Texture.Id,
};

pub const GlobalContext = struct {
    memory: *Memory,
    screen_quads: ScreenQuads,
    texture_store: Textures.Store,
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
        self.screen_quads = ScreenQuads.init(memory, 4096) catch unreachable;
        self.texture_store.init(memory) catch unreachable;
        self.font = Font.init(memory, &self.texture_store, "assets/rm-albion.regular.ttf", 64);

        self.assets.table = self.texture_store.load(memory, "assets/table.png");
        self.assets.cue_defult = self.texture_store.load(memory, "assets/cue.png");
        self.assets.button = self.texture_store.load(memory, "assets/button.png");
        self.assets.cue_background = self.texture_store.load(memory, "assets/cue_background.png");
        self.assets.items_background =
            self.texture_store.load(memory, "assets/items_background.png");
        self.assets.shop_panel = self.texture_store.load(memory, "assets/shop_panel.png");
        self.assets.blood = self.texture_store.load(memory, "assets/blood.png");
        self.assets.souls = self.texture_store.load(memory, "assets/souls.png");

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
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Spiky ball",
            .description =
            \\Increases the ball
            \\damage by 5
            ,
            .price = 20,
        };
        self.item_infos.get_mut(.BallHealthy).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Healthy ball",
            .description =
            \\Increases the ball
            \\hp by 5
            ,
            .price = 20,
        };
        self.item_infos.get_mut(.BallArmored).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Armored ball",
            .description =
            \\Increases the armor
            \\of the ball by 5
            ,
            .price = 20,
        };
        self.item_infos.get_mut(.BallLight).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Light ball",
            .description = "Makes a ball lighter",
            .price = 20,
        };
        self.item_infos.get_mut(.BallHeavy).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Heavy ball",
            .description = "Makes a ball heavier",
            .price = 20,
        };
        self.item_infos.get_mut(.BallAntisocial).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Antisocial ball",
            .description =
            \\Ball gains additional
            \\velocity when collides with other balls
            ,
            .price = 20,
        };
        self.item_infos.get_mut(.BallGravity).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Gravity ball",
            .description = "TODO",
            .price = 20,
        };
        self.item_infos.get_mut(.BallRunner).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Runner ball",
            .description = "TODO",
            .price = 20,
        };
        self.item_infos.get_mut(.BallRingOfLight).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Ring of light",
            .description = "TODO",
            .price = 20,
        };

        self.item_infos.get_mut(.CueWiggleBall).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Wiggle ball",
            .description =
            \\Makes the hit ball
            \\to travel in a sin wave pattern
            ,
            .price = 20,
        };
        self.item_infos.get_mut(.CueScope).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Sniper scope",
            .description =
            \\Adds a trajectory line
            \\when aiming
            ,
            .price = 20,
        };
        self.item_infos.get_mut(.CueSecondBarrel).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Second barrel",
            .description = "",
            .price = 20,
        };
        self.item_infos.get_mut(.CueSilencer).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Silencer",
            .description =
            \\The ball you hit will
            \\ghost through allied
            \\balls and only collide
            \\with the first enemy ball
            ,
            .price = 20,
        };
        self.item_infos.get_mut(.CueRocketBooster).* = .{
            .texture_id = Textures.Texture.ID_DEBUG,
            .name = "Rocket booster",
            .description =
            \\Increases the strength
            \\of the hit
            ,
            .price = 20,
        };

        self.item_infos.get_mut(.CueDefault).* = .{
            .texture_id = self.assets.cue_defult,
            .name = "Default cue",
            .description = "",
            .price = 20,
        };
        self.item_infos.get_mut(.CueKar98K).* = .{
            .texture_id = self.assets.cue_defult,
            .name = "Kar98k",
            .description =
            \\In addition to hitting
            \\the ball, deals 50 damage
            \\to all enemy balls in
            \\a straight line
            ,
            .price = 20,
        };
        self.item_infos.get_mut(.CueCross).* = .{
            .texture_id = self.assets.cue_defult,
            .name = "Silver cross",
            .description =
            \\In addition to hitting 
            \\the ball, heals all allied
            \\balls and damages all
            \\enemy balls in a small radius
            ,
            .price = 20,
        };

        self.dt = 0.0;
    }

    pub fn alloc(self: *GlobalContext) Allocator {
        return self.memory.scratch_alloc();
    }

    pub fn reset(self: *GlobalContext) void {
        self.screen_quads.reset();
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

        {
            const mouse_rect: Object2d = .{
                .type = .{ .Color = Color.ORANGE },
                .transform = .{
                    .position = self.context.input.mouse_pos_world.extend(0.0),
                },
                .size = .{
                    .x = 20.0,
                    .y = 20.0,
                },
            };
            mouse_rect.to_screen_quad(
                &self.context.camera,
                &self.context.texture_store,
                &self.context.screen_quads,
            );
        }
        {
            const mouse_rect: Object2d = .{
                .type = .{ .Color = Color.BLUE },
                .transform = .{
                    .position = self.context.player_input.mouse_pos_world.extend(0.0),
                },
                .size = .{
                    .x = 10.0,
                    .y = 10.0,
                },
            };
            mouse_rect.to_screen_quad(
                &self.context.camera,
                &self.context.texture_store,
                &self.context.screen_quads,
            );
        }

        self.soft_renderer.start_rendering();
        self.context.screen_quads.render(
            &self.soft_renderer,
            &self.context.texture_store,
            0.0,
            false,
        );
        if (self.game.is_aiming) {
            const ball_world_position =
                self.game.balls[self.game.selected_ball.?].physics.body.position;
            const ball_screen_positon =
                ball_world_position.sub(self.context.camera.position.xy());
            const end_positon = self.context.input.mouse_pos;
            self.soft_renderer.draw_line(
                ball_screen_positon,
                end_positon,
                Color.MAGENTA,
            );
        }
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
