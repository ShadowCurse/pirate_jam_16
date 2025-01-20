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

const UiRect = struct {
    text: Text,

    pub fn init(position: Vec2, font: *const Font, text: []const u8, text_size: f32) UiRect {
        return .{
            .text = Text.init(
                font,
                text,
                text_size,
                position.extend(0.0),
                0.0,
                .{},
                .{ .dont_clip = true },
            ),
        };
    }

    pub fn to_screen_quads(
        self: UiRect,
        allocator: Allocator,
        mouse_pos: Vec2,
        screen_quads: *ScreenQuads,
    ) bool {
        const text_quads = self.text.to_screen_quads_raw(allocator);
        const collision_rectangle: Physics.Rectangle = .{
            .size = .{
                .x = text_quads.total_width,
                .y = self.text.size,
            },
        };
        const rectangle_position: Vec2 =
            self.text.position.xy().add(.{ .y = -self.text.size / 2.0 });
        const intersects = Physics.point_rectangle_intersect(
            mouse_pos,
            collision_rectangle,
            rectangle_position,
        );
        if (intersects) {
            for (text_quads.quads) |*quad| {
                quad.color = Color.RED;
                quad.options.with_tint = true;
            }
        }
        for (text_quads.quads) |quad| {
            screen_quads.add_quad(quad);
        }
        return intersects;
    }

    pub fn to_screen_quads_world_space(
        self: UiRect,
        allocator: Allocator,
        mouse_pos: Vec2,
        camera_controller: *const CameraController2d,
        screen_quads: *ScreenQuads,
    ) bool {
        const text_quads = self.text.to_screen_quads_world_space_raw(allocator, camera_controller);
        const collision_rectangle: Physics.Rectangle = .{
            .size = .{
                .x = text_quads.total_width,
                .y = self.text.size,
            },
        };
        const rectangle_position: Vec2 =
            self.text.position.xy().add(.{ .y = -self.text.size / 2.0 });
        const intersects = Physics.point_rectangle_intersect(
            mouse_pos,
            collision_rectangle,
            rectangle_position,
        );
        if (intersects) {
            for (text_quads.quads) |*quad| {
                quad.color = Color.RED;
                quad.options.with_tint = true;
            }
        }
        for (text_quads.quads) |quad| {
            screen_quads.add_quad(quad);
        }
        return intersects;
    }
};

const MouseDrag = struct {
    active: bool = false,
    sensitivity: f32 = 100.0,
    v: Vec2 = .{},

    pub fn update(
        self: *MouseDrag,
        events: []const Events.Event,
        dt: f32,
    ) ?Vec2 {
        for (events) |event| {
            switch (event) {
                .Mouse => |mouse| {
                    switch (mouse) {
                        .Button => |button| {
                            if (button.key == .RMB) {
                                if (button.type == .Pressed) {
                                    self.active = true;
                                } else {
                                    if (self.active) {
                                        const v = self.v;
                                        self.v = .{};
                                        self.active = false;
                                        return v;
                                    }
                                }
                            }
                        },
                        .Motion => |motion| {
                            if (self.active) {
                                self.v = self.v.sub(.{
                                    .x = @as(f32, @floatFromInt(motion.x)) *
                                        self.sensitivity * dt,
                                    .y = @as(f32, @floatFromInt(motion.y)) *
                                        self.sensitivity * dt,
                                });
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
        return null;
    }
};

const SmoothStepAnimation = struct {
    start_position: Vec3,
    end_position: Vec3,
    duration: f32,
    progress: f32,

    pub fn update(self: *SmoothStepAnimation, position: *Vec3, dt: f32) bool {
        const p = self.progress / self.duration;
        const t = p * p * (3.0 - 2.0 * p);
        position.* = self.start_position.lerp(self.end_position, t);
        self.progress += dt;
        return self.duration <= self.progress;
    }
};

const GameStateChangeAnimation = struct {
    camera_controller: *CameraController2d,
    animation: ?SmoothStepAnimation = null,
    game_state: *GameState,
    final_game_state: GameState = .{},

    const DURATION = 1.0;

    pub fn set(
        self: *GameStateChangeAnimation,
        target_position: Vec2,
        final_game_state: GameState,
    ) void {
        const camera_worl_position = self.camera_controller.world_position().xy();
        const delta = target_position.sub(camera_worl_position);
        self.animation = .{
            .start_position = self.camera_controller.position,
            .end_position = self.camera_controller.position.add(delta.extend(0.0)),
            .duration = DURATION,
            .progress = 0.0,
        };
        self.final_game_state = final_game_state;
    }

    pub fn update(self: *GameStateChangeAnimation, dt: f32) void {
        if (self.animation) |*a| {
            if (a.update(&self.camera_controller.position, dt)) {
                self.animation = null;
                self.game_state.* = self.final_game_state;
            }
        }
    }
};

const MoveAnimation = struct {
    velocity: Vec2,
    duration: f32,
    progress: f32,

    pub fn update(
        self: *MoveAnimation,
        position: *Vec2,
        dt: f32,
    ) bool {
        position.* = position.add(self.velocity.mul_f32(dt));
        self.progress += dt;
        return self.duration <= self.progress;
    }
};

const BallAnimations = struct {
    animations: [36]BallAnimation = undefined,
    animation_n: u32 = 0,

    const BallAnimation = struct {
        ball_id: u8,
        move_animation: MoveAnimation,
    };

    pub fn add(self: *BallAnimations, ball: *const Ball, target: Vec2, duration: f32) void {
        if (self.animation_n == self.animations.len) {
            log.err(
                @src(),
                "Trying to add ball animation, but there is no available slots for it",
                .{},
            );
            return;
        }
        const velocity = target.sub(ball.body.position).mul_f32(1.0 / duration);
        self.animations[self.animation_n] = .{
            .ball_id = ball.id,
            .move_animation = .{
                .velocity = velocity,
                .duration = duration,
                .progress = 0,
            },
        };
        log.info(@src(), "Adding ball animation in slot: {d}", .{self.animation_n});
        self.animation_n += 1;
        log.assert(
            @src(),
            self.animation_n < self.animations.len,
            "Animation counter overflow",
            .{},
        );
    }

    pub fn update(self: *BallAnimations, balls: []Ball, dt: f32) void {
        var start: u32 = 0;
        while (start < self.animation_n) {
            const animation = &self.animations[start];
            const ball = &balls[animation.ball_id];
            if (animation.move_animation.update(&ball.body.position, dt)) {
                log.info(@src(), "Removing ball animation from slot: {d}", .{start});
                self.animations[start] = self.animations[self.animation_n - 1];
                self.animation_n -= 1;
            } else {
                start += 1;
            }
        }
    }
};

const GameState = packed struct(u8) {
    main_menu: bool = true,
    settings: bool = false,
    in_game: bool = false,
    debug: bool = true,
    _: u4 = 0,
};

const CAMERA_MAIN_MENU: Vec2 = .{ .y = 1000.0 };
const CAMERA_SETTINGS: Vec2 = .{ .x = 1000.0, .y = 1000.0 };
const CAMERA_IN_GAME: Vec2 = .{};

const InputState = struct {
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

    balls: [16]Ball,
    table: Table,
    ball_animations: BallAnimations,

    show_perf: bool,
    selected_ball: ?u32,

    mouse_drag: MouseDrag,

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

        for (&self.balls, 0..) |*ball, i| {
            const row: f32 = @floatFromInt(@divFloor(i, 4));
            const column: f32 = @floatFromInt(i % 4);
            const position: Vec2 = .{
                .x = -60.0 * 2 + column * 60.0 + 30.0,
                .y = -60.0 * 2 + row * 60.0 + 30.0,
            };
            const id: u8 = @intCast(i);
            const color = Color.from_parts(
                @intCast((i * 64) % 255),
                @intCast((i * 17) % 255),
                @intCast((i * 33) % 255),
                255,
            );
            ball.* = .{
                .id = id,
                .texture_id = self.texture_ball,
                .color = color,
                .body = .{
                    .position = position,
                    .velocity = .{},
                    .restitution = 1.0,
                    .friction = 0.95,
                    .inv_mass = 1.0,
                },
                .collider = .{
                    .radius = 20.0,
                },
                .previous_positions = [_]Vec2{position} ** 64,
                .previous_position_index = 0,
            };
        }
        self.table = Table.init(self.texture_poll_table);
        self.ball_animations = .{};

        self.show_perf = false;
        self.selected_ball = null;

        self.mouse_drag = .{};
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

        self.input_state.mouse_pos = .{ .x = @floatFromInt(mouse_x), .y = @floatFromInt(mouse_y) };
        self.input_state.mouse_pos_world = self.input_state.mouse_pos.add(self.camera_controller.position.xy());

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
        if (self.mouse_drag.active) {
            self.soft_renderer.draw_line(
                screen_size.mul_f32(0.5),
                screen_size.mul_f32(0.5).add(self.mouse_drag.v),
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

        const start_button = UiRect.init(
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
            self.game_state.in_game = true;
            var final_game_state = self.game_state;
            final_game_state.main_menu = false;
            self.game_state_change_animation.set(CAMERA_IN_GAME, final_game_state);
        }

        const settings_button = UiRect.init(
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

        const back_button = UiRect.init(
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
        if (self.mouse_drag.update(events, dt)) |v| {
            if (self.selected_ball) |sb| {
                const ball = &self.balls[sb];
                ball.body.velocity = ball.body.velocity.add(v);
            }
        }

        for (&self.balls) |*ball| {
            if (ball.disabled)
                continue;
            ball.update(&self.table, &self.balls, dt);
        }

        for (&self.balls) |*ball| {
            if (ball.disabled)
                continue;

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

        self.ball_animations.update(&self.balls, dt);

        self.table.to_screen_quad(
            &self.camera_controller,
            &self.texture_store,
            &self.screen_quads,
        );
        self.table.borders_to_screen_quads(
            &self.camera_controller,
            &self.screen_quads,
        );
        self.table.pockets_to_screen_quads(
            &self.camera_controller,
            &self.screen_quads,
        );

        var new_ball_selected: bool = false;
        for (&self.balls) |*ball| {
            if (!ball.disabled and ball.is_hovered(self.input_state.mouse_pos_world) and
                self.input_state.lmb)
            {
                new_ball_selected = true;
                self.selected_ball = ball.id;
            }
            const bo = ball.to_object_2d();
            bo.to_screen_quad(
                &self.camera_controller,
                &self.texture_store,
                &self.screen_quads,
            );
            if (self.selected_ball) |sb| {
                if (ball.id == sb) {
                    const pbo = ball.previous_positions_to_object_2d();
                    for (&pbo) |pb| {
                        pb.to_screen_quad(
                            &self.camera_controller,
                            &self.texture_store,
                            &self.screen_quads,
                        );
                    }
                }
            }
        }
        if (!new_ball_selected and self.input_state.lmb)
            self.selected_ball = null;

        const back_button = UiRect.init(
            .{ .x = -550.0 },
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
        const perf_button = UiRect.init(
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
