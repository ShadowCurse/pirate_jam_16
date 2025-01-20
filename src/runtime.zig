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

const Text = stygian.text;
const Font = stygian.font;
const Memory = stygian.memory;
const Physics = stygian.physics;
const Textures = stygian.textures;
const Events = stygian.platform.event;
const SoftRenderer = stygian.soft_renderer.renderer;
const CameraController2d = stygian.camera.CameraController2d;

const Object2d = stygian.objects.Object2d;

const _math = stygian.math;
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;

const _objects = @import("objects.zig");
const Ball = _objects.Ball;
const Table = _objects.Table;

const _animations = @import("animations.zig");
const GameStateChangeAnimation = _animations.GameStateChangeAnimation;

const _ui = @import("ui.zig");
const UiText = _ui.UiText;
const UiPanel = _ui.UiPanel;

const Game = @import("game.zig");

pub const GameState = packed struct(u8) {
    main_menu: bool = true,
    settings: bool = false,
    in_game: bool = false,
    debug: bool = true,
    _: u4 = 0,
};

pub const CAMERA_MAIN_MENU: Vec2 = .{ .y = 1000.0 };
pub const CAMERA_SETTINGS: Vec2 = .{ .x = 1000.0, .y = 1000.0 };
pub const CAMERA_IN_GAME: Vec2 = .{};

pub const InputState = struct {
    lmb: bool = false,
    rmb: bool = false,
    mouse_pos: Vec2 = .{},
    mouse_pos_world: Vec2 = .{},
};

const Runtime = struct {
    camera_controller: CameraController2d,

    texture_store: Textures.Store,
    texture_poll_table: Textures.Texture.Id,
    texture_ball: Textures.Texture.Id,
    font: Font,

    screen_quads: ScreenQuads,
    soft_renderer: SoftRenderer,

    game_state: GameState,
    input_state: InputState,
    game_state_change_animation: GameStateChangeAnimation,
    game: Game,

    show_perf: bool,

    const Self = @This();

    fn init(
        self: *Self,
        window: *sdl.SDL_Window,
        memory: *Memory,
        width: u32,
        height: u32,
    ) !void {
        self.camera_controller = CameraController2d.init(width, height);
        self.camera_controller.position = self.camera_controller.position
            .add(CAMERA_MAIN_MENU.extend(0.0));
        try self.texture_store.init(memory);
        self.texture_poll_table = self.texture_store.load(memory, "assets/table_prototype.png");
        self.texture_ball = self.texture_store.load(memory, "assets/ball_prototype.png");

        self.font = Font.init(memory, &self.texture_store, "assets/Hack-Regular.ttf", 64);

        self.screen_quads = try ScreenQuads.init(memory, 4096);
        self.soft_renderer = SoftRenderer.init(memory, window, width, height);

        self.game_state = .{};
        self.input_state = .{};
        self.game_state_change_animation = .{
            .camera_controller = &self.camera_controller,
            .game_state = &self.game_state,
        };
        self.game.init(self.texture_ball, self.texture_poll_table);

        self.show_perf = false;
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
        const frame_alloc = memory.frame_alloc();
        self.screen_quads.reset();

        if (self.show_perf) {
            const TaceableTypes = struct {
                SoftRenderer,
                ScreenQuads,
                Ball,
                Table,
            };
            Tracing.prepare_next_frame(TaceableTypes);
            Tracing.to_screen_quads(
                TaceableTypes,
                frame_alloc,
                &self.screen_quads,
                &self.font,
                32.0,
            );
            Tracing.zero_current(TaceableTypes);
        }

        self.input_state.mouse_pos = .{
            .x = @floatFromInt(mouse_x),
            .y = @floatFromInt(mouse_y),
        };
        self.input_state.mouse_pos_world = self.input_state.mouse_pos.add(
            self.camera_controller.position.xy(),
        );

        for (events) |event| {
            switch (event) {
                .Mouse => |mouse| {
                    switch (mouse) {
                        .Button => |button| {
                            if (button.key == .LMB)
                                self.input_state.lmb = button.type == .Pressed;
                            if (button.key == .RMB)
                                self.input_state.rmb = button.type == .Pressed;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        self.game_state_change_animation.update(dt);

        if (self.game_state.main_menu)
            self.main_menu(
                memory,
                dt,
                events,
                window_width,
                window_height,
            );
        if (self.game_state.settings)
            self.settings(
                memory,
                dt,
                events,
                window_width,
                window_height,
            );
        if (self.game_state.in_game)
            self.in_game(
                memory,
                dt,
                events,
                window_width,
                window_height,
            );
        if (self.game_state.debug)
            self.debug(
                memory,
                dt,
                events,
                window_width,
                window_height,
            );

        self.soft_renderer.start_rendering();
        self.screen_quads.render(
            &self.soft_renderer,
            0.0,
            &self.texture_store,
        );
        const screen_size: Vec2 = .{
            .x = @floatFromInt(window_width),
            .y = @floatFromInt(window_height),
        };
        // for (collisions) |collision| {
        //     if (collision) |c| {
        //         const c_position = c.position
        //             .add(screen_size.mul_f32(0.5));
        //         self.soft_renderer
        //             .draw_color_rect(c_position, .{ .x = 5.0, .y = 5.0 }, Color.BLUE, false);
        //         if (c.normal.is_valid()) {
        //             const c_normal_end = c_position.add(c.normal.mul_f32(20.0));
        //             self.soft_renderer.draw_line(c_position, c_normal_end, Color.GREEN);
        //         }
        //     }
        // }
        if (self.game.mouse_drag.active) {
            self.soft_renderer.draw_line(
                screen_size.mul_f32(0.5),
                screen_size.mul_f32(0.5).add(self.game.mouse_drag.v),
                Color.MAGENTA,
            );
        }
        self.soft_renderer.end_rendering();
    }

    fn main_menu(
        self: *Self,
        memory: *Memory,
        dt: f32,
        events: []const Events.Event,
        window_width: u32,
        window_height: u32,
    ) void {
        _ = dt;
        _ = events;
        _ = window_width;
        _ = window_height;

        const frame_alloc = memory.frame_alloc();

        const start_button = UiText.init(
            CAMERA_MAIN_MENU,
            &self.font,
            "Start",
            32.0,
        );
        if (start_button.to_screen_quads_world_space(
            frame_alloc,
            self.input_state.mouse_pos_world,
            &self.camera_controller,
            &self.screen_quads,
        ) and self.input_state.lmb) {
            self.game.restart();

            self.game_state.in_game = true;
            var final_game_state = self.game_state;
            final_game_state.main_menu = false;
            self.game_state_change_animation.set(CAMERA_IN_GAME, final_game_state);
        }

        const settings_button = UiText.init(
            CAMERA_MAIN_MENU.add(.{ .y = 50.0 }),
            &self.font,
            "Settings",
            32.0,
        );
        if (settings_button.to_screen_quads_world_space(
            frame_alloc,
            self.input_state.mouse_pos_world,
            &self.camera_controller,
            &self.screen_quads,
        ) and self.input_state.lmb) {
            self.game_state.settings = true;
            var final_game_state = self.game_state;
            final_game_state.main_menu = false;
            self.game_state_change_animation.set(CAMERA_SETTINGS, final_game_state);
        }
    }

    fn settings(
        self: *Self,
        memory: *Memory,
        dt: f32,
        events: []const Events.Event,
        window_width: u32,
        window_height: u32,
    ) void {
        _ = dt;
        _ = events;
        _ = window_width;
        _ = window_height;

        const frame_alloc = memory.frame_alloc();

        const back_button = UiText.init(
            CAMERA_SETTINGS,
            &self.font,
            "Back",
            32.0,
        );
        if (back_button.to_screen_quads_world_space(
            frame_alloc,
            self.input_state.mouse_pos_world,
            &self.camera_controller,
            &self.screen_quads,
        ) and self.input_state.lmb) {
            self.game_state.main_menu = true;
            var final_game_state = self.game_state;
            final_game_state.settings = false;
            self.game_state_change_animation.set(CAMERA_MAIN_MENU, final_game_state);
        }
    }

    fn in_game(
        self: *Self,
        memory: *Memory,
        dt: f32,
        events: []const Events.Event,
        window_width: u32,
        window_height: u32,
    ) void {
        _ = window_width;
        _ = window_height;

        const frame_alloc = memory.frame_alloc();

        self.game.update(events, &self.input_state, dt);
        self.game.draw(&self.camera_controller, &self.texture_store, &self.screen_quads);

        const UI_BACKGROUND_COLOR = Color.GREY;
        const UI_BACKGROUND_COLOR_PLAYING = Color.GREEN;

        // UI section
        const top_panel = UiPanel.init(
            .{ .y = -300.0 },
            .{ .x = 800.0, .y = 60.0 },
            UI_BACKGROUND_COLOR,
        );
        top_panel.to_screen_quad(&self.camera_controller, &self.screen_quads);

        const bot_panel = UiPanel.init(
            .{ .y = 300.0 },
            .{ .x = 800.0, .y = 60.0 },
            UI_BACKGROUND_COLOR,
        );
        bot_panel.to_screen_quad(&self.camera_controller, &self.screen_quads);

        const left_info_opponent_panel = UiPanel.init(
            .{ .x = -550.0, .y = -165 },
            .{ .x = 140.0, .y = 320.0 },
            if (!self.game.player_turn) UI_BACKGROUND_COLOR_PLAYING else UI_BACKGROUND_COLOR,
        );
        left_info_opponent_panel.to_screen_quad(&self.camera_controller, &self.screen_quads);

        const left_info_player_panel = UiPanel.init(
            .{ .x = -550.0, .y = 165 },
            .{ .x = 140.0, .y = 320.0 },
            if (self.game.player_turn) UI_BACKGROUND_COLOR_PLAYING else UI_BACKGROUND_COLOR,
        );
        left_info_player_panel.to_screen_quad(&self.camera_controller, &self.screen_quads);

        const right_cue_panel = UiPanel.init(
            .{ .x = 550.0 },
            .{ .x = 140.0, .y = 600.0 },
            UI_BACKGROUND_COLOR,
        );
        right_cue_panel.to_screen_quad(&self.camera_controller, &self.screen_quads);

        const back_button = UiText.init(
            .{ .x = -550.0, .y = 350.0 },
            &self.font,
            "Back",
            32.0,
        );
        if (back_button.to_screen_quads_world_space(
            frame_alloc,
            self.input_state.mouse_pos_world,
            &self.camera_controller,
            &self.screen_quads,
        ) and self.input_state.lmb) {
            self.game_state.main_menu = true;
            var final_game_state = self.game_state;
            final_game_state.in_game = false;
            self.game_state_change_animation.set(CAMERA_MAIN_MENU, final_game_state);
        }
    }

    fn debug(
        self: *Self,
        memory: *Memory,
        dt: f32,
        events: []const Events.Event,
        window_width: u32,
        window_height: u32,
    ) void {
        _ = events;

        const frame_alloc = memory.frame_alloc();
        const perf_button = UiText.init(
            .{
                .x = @as(f32, @floatFromInt(window_width)) / 2.0,
                .y = @as(f32, @floatFromInt(window_height)) / 2.0 + 300.0,
            },
            &self.font,
            std.fmt.allocPrint(
                frame_alloc,
                "FPS: {d:.1} FT: {d:.3}s, mouse_pos: {d}:{d}, camera_pos: {d}:{d}",
                .{
                    1.0 / dt,
                    dt,
                    self.input_state.mouse_pos.x,
                    self.input_state.mouse_pos.y,
                    self.camera_controller.position.x,
                    self.camera_controller.position.y,
                },
            ) catch unreachable,
            32.0,
        );
        if (perf_button.to_screen_quads(frame_alloc, self.input_state.mouse_pos, &self.screen_quads) and
            self.input_state.lmb)
            self.show_perf = !self.show_perf;

        // for (&self.balls, 0..) |*ball, i| {
        //     const text_ball_info = Text.init(
        //         &self.font,
        //         std.fmt.allocPrint(
        //             frame_alloc,
        //             "ball id: {d}, position: {d: >8.1}/{d: >8.1}, disabled: {}, p_index: {d: >2}",
        //             .{
        //                 ball.id,
        //                 ball.body.position.x,
        //                 ball.body.position.y,
        //                 ball.disabled,
        //                 ball.previous_position_index,
        //             },
        //         ) catch unreachable,
        //         25.0,
        //         .{
        //             .x = @as(f32, @floatFromInt(window_width)) / 2.0,
        //             .y = @as(f32, @floatFromInt(window_height)) / 2.0 + 200.0 +
        //                 25.0 * @as(f32, @floatFromInt(i)),
        //         },
        //         0.0,
        //         .{},
        //         .{ .dont_clip = true },
        //     );
        //     text_ball_info.to_screen_quads(frame_alloc, &self.screen_quads);
        // }
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
