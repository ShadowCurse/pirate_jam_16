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
            .position = self.text.position.xy().add(.{ .y = -self.text.size / 2.0 }),
            .size = .{
                .x = text_quads.total_width,
                .y = self.text.size,
            },
        };
        const intersects = Physics.point_rectangle_intersect(mouse_pos, collision_rectangle);
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

const BallAnimation = struct {
    ball_id: u8,
    velocity: Vec2,
    duration: f32,
    progress: f32,

    pub fn update(
        self: *BallAnimation,
        balls: []Ball,
        dt: f32,
    ) bool {
        const ball = &balls[self.ball_id];
        ball.collider.position = ball.collider.position.add(self.velocity.mul_f32(dt));
        self.progress += dt;
        return self.duration <= self.progress;
    }
};

const BallAnimations = struct {
    animations: [36]BallAnimation = undefined,
    animation_n: u32 = 0,

    pub fn add(self: *BallAnimations, ball: *const Ball, target: Vec2, duration: f32) void {
        if (self.animation_n == self.animations.len) {
            log.err(
                @src(),
                "Trying to add ball animation, but there is no available slots for it",
                .{},
            );
            return;
        }
        const velocity = target.sub(ball.collider.position).mul_f32(1.0 / duration);
        self.animations[self.animation_n] = .{
            .ball_id = ball.id,
            .velocity = velocity,
            .duration = duration,
            .progress = 0,
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
            if (animation.update(balls, dt)) {
                log.info(@src(), "Removing ball animation from slot: {d}", .{start});
                self.animations[start] = self.animations[self.animation_n - 1];
                self.animation_n -= 1;
            } else {
                start += 1;
            }
        }
    }
};

const Runtime = struct {
    camera_controller: CameraController2d,

    texture_store: Textures.Store,
    texture_poll_table: Textures.Texture.Id,
    texture_ball: Textures.Texture.Id,
    font: Font,

    screen_quads: ScreenQuads,
    soft_renderer: SoftRenderer,

    balls: [4]Ball,
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
        try self.texture_store.init(memory);
        self.texture_poll_table = self.texture_store.load(memory, "assets/table_prototype.png");
        self.texture_ball = self.texture_store.load(memory, "assets/ball_prototype.png");

        self.font = Font.init(memory, &self.texture_store, "assets/Hack-Regular.ttf", 64);

        self.screen_quads = try ScreenQuads.init(memory, 4096);
        self.soft_renderer = SoftRenderer.init(memory, window, width, height);

        for (&self.balls, 0..) |*ball, i| {
            const row: f32 = @floatFromInt(@divFloor(i, 4));
            const column: f32 = @floatFromInt(i % 4);
            const position: Vec2 = .{
                .x = -60.0 * 2 + column * 60.0 + 30.0,
                .y = -60.0 * 2 + row * 60.0 + 30.0,
            };
            ball.* = .{
                .id = @intCast(i),
                .texture_id = self.texture_ball,
                .collider = .{
                    .position = position,
                    .radius = 20.0,
                },
                .previous_positions = [_]Vec2{position} ** 64,
                .previous_position_index = 0,
                .velocity = .{},
                .friction = 0.95,
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

        const mouse_pos: Vec2 = .{ .x = @floatFromInt(mouse_x), .y = @floatFromInt(mouse_y) };
        const mouse_pos_world = mouse_pos.add(self.camera_controller.position.xy());

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

        var mouse_button_pressed = false;
        for (events) |event| {
            switch (event) {
                .Mouse => |mouse| {
                    switch (mouse) {
                        .Button => |button| {
                            mouse_button_pressed = button.type == .Pressed;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        if (self.mouse_drag.update(events, dt)) |v| {
            for (&self.balls) |*ball| {
                if (ball.disabled)
                    continue;
                ball.velocity = ball.velocity.add(v);
            }
        }

        for (&self.balls) |*ball| {
            if (ball.disabled)
                continue;
            ball.update(frame_alloc, &self.table, &self.balls, dt);
        }

        for (&self.balls) |*ball| {
            if (ball.disabled)
                continue;

            for (&self.table.pockets) |*pocket| {
                const collision_point =
                    Physics.circle_circle_collision(ball.collider, pocket.collider);
                if (collision_point) |_| {
                    ball.disabled = true;
                    self.ball_animations.add(ball, pocket.collider.position, 1.0);
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
            if (ball.is_hovered(mouse_pos_world) and mouse_button_pressed) {
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
        if (!new_ball_selected and mouse_button_pressed)
            self.selected_ball = null;

        const ui_rect = UiRect.init(
            .{
                .x = @as(f32, @floatFromInt(window_width)) / 2.0,
                .y = @as(f32, @floatFromInt(window_height)) / 2.0 + 300.0,
            },
            &self.font,

            std.fmt.allocPrint(
                frame_alloc,
                "FPS: {d:.1} FT: {d:.3}s, mouse_pos: {d}:{d}",
                .{ 1.0 / dt, dt, mouse_x, mouse_y },
            ) catch unreachable,
            32.0,
        );
        if (ui_rect.to_screen_quads(
            frame_alloc,
            mouse_pos,
            &self.screen_quads,
        ) and mouse_button_pressed)
            self.show_perf = !self.show_perf;

        for (&self.balls, 0..) |*ball, i| {
            const text_ball_info = Text.init(
                &self.font,
                std.fmt.allocPrint(
                    frame_alloc,
                    "ball id: {d}, position: {d: >8.1}/{d: >8.1}, disabled: {}, p_index: {d: >2}",
                    .{
                        ball.id,
                        ball.collider.position.x,
                        ball.collider.position.y,
                        ball.disabled,
                        ball.previous_position_index,
                    },
                ) catch unreachable,
                25.0,
                .{
                    .x = @as(f32, @floatFromInt(window_width)) / 2.0,
                    .y = @as(f32, @floatFromInt(window_height)) / 2.0 + 200.0 +
                        25.0 * @as(f32, @floatFromInt(i)),
                },
                0.0,
                .{},
                .{ .dont_clip = true },
            );
            text_ball_info.to_screen_quads(frame_alloc, &self.screen_quads);
        }

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

    const mouse_x_u32: u32 = @intCast(mouse_x);
    const mouse_y_u32: u32 = @intCast(mouse_y);

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
