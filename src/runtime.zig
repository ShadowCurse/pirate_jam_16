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
    .enabled = false,
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

const _objects = stygian.objects;
const Object2d = _objects.Object2d;

const _math = stygian.math;
const Vec2 = _math.Vec2;

const Ball = struct {
    id: u8,
    texture_id: Textures.Texture.Id,
    collider: Physics.Circle,
    previous_positions: [PREVIOUS_POSITIONS]Vec2,
    previous_position_index: u32,
    velocity: Vec2,
    friction: f32,
    disabled: bool = false,

    const PREVIOUS_POSITIONS = 64;

    pub fn update(self: *Ball, allocator: Allocator, table: *const Table, balls: []const Ball, dt: f32) void {
        if (self.disabled)
            return;

        const collisions =
            allocator.alloc(Physics.CollisionPoint, table.borders.len + balls.len) catch unreachable;
        var collisions_n: u32 = 0;

        for (balls) |*ball| {
            if (self.id == ball.id)
                continue;
            const collision_point =
                Physics.circle_circle_collision(self.collider, ball.collider);
            if (collision_point) |cp| {
                if (cp.normal.is_valid()) {
                    collisions[collisions_n] = cp;
                    collisions_n += 1;
                    log.info(
                        @src(),
                        "collision of ball: {d} and ball: {d}",
                        .{ self.id, ball.id },
                    );
                } else {
                    log.info(
                        @src(),
                        "invalid normal for collision of ball: {d} and ball: {d}",
                        .{ self.id, ball.id },
                    );
                }
            }
        }
        for (&table.borders, 0..) |*border, i| {
            const collision_point =
                Physics.circle_rectangle_collision(self.collider, border.collider);
            if (collision_point) |cp| {
                if (cp.normal.is_valid()) {
                    collisions[collisions_n] = cp;
                    collisions_n += 1;
                    log.info(
                        @src(),
                        "collision of ball: {d} and border: {d}",
                        .{ self.id, i },
                    );
                } else {
                    var prev_collider = self.collider;
                    prev_collider.position = self.previous_positions[self.previous_position_index];
                    const ncp =
                        Physics.circle_rectangle_closest_collision_point(
                        prev_collider,
                        border.collider,
                    );
                    if (!ncp.normal.is_valid()) @panic("wtf");

                    collisions[collisions_n] = cp;
                    collisions_n += 1;
                    log.info(
                        @src(),
                        "invalid normal for collision of ball: {d} and border: {d}",
                        .{ self.id, i },
                    );
                }
            }
        }

        if (collisions_n != 0) {
            log.info(
                @src(),
                "resolving {d} collisions for ball: {d}",
                .{ collisions_n, self.id },
            );

            var avg_collision_position: Vec2 = .{};
            var avg_collision_normal: Vec2 = .{};
            for (collisions[0..collisions_n]) |*collision| {
                if (!collision.normal.is_valid())
                    continue;
                avg_collision_position = avg_collision_position.add(collision.position);
                avg_collision_normal = avg_collision_normal.add(collision.normal);
            }
            log.assert(@src(), avg_collision_position.is_valid(), "", .{});
            log.assert(@src(), avg_collision_normal.is_valid(), "", .{});

            avg_collision_position = avg_collision_position.mul_f32(1.0 / @as(f32, @floatFromInt(collisions_n)));
            avg_collision_normal = avg_collision_normal.mul_f32(1.0 / @as(f32, @floatFromInt(collisions_n)));

            const proj = avg_collision_normal.mul_f32(-self.velocity.dot(avg_collision_normal));
            self.velocity = self.velocity.add(proj.mul_f32(2.0));
            const new_positon =
                avg_collision_position.add(avg_collision_normal.mul_f32(self.collider.radius));
            self.previous_positions[self.previous_position_index] = self.collider.position;
            self.previous_position_index += 1;
            self.previous_position_index %= PREVIOUS_POSITIONS;
            self.collider.position = new_positon;
        }

        self.previous_positions[self.previous_position_index] = self.collider.position;
        self.previous_position_index += 1;
        self.previous_position_index %= PREVIOUS_POSITIONS;
        self.collider.position = self.collider.position.add(self.velocity.mul_f32(dt));
        self.velocity = self.velocity.mul_f32(self.friction);

        if (self.collider.position.x < -Table.WIDTH / 2.0 or Table.WIDTH / 2.0 < self.collider.position.x or
            self.collider.position.y < -Table.HEIGTH / 2.0 or Table.HEIGTH / 2.0 < self.collider.position.y)
        {
            self.velocity = .{};
            self.disabled = true;
        }
    }

    fn to_object_2d(
        self: Ball,
    ) Object2d {
        return .{
            .type = .{ .TextureId = self.texture_id },
            .transform = .{
                .position = self.collider.position.extend(0.0),
            },
            .size = .{
                .x = 40.0,
                .y = 40.0,
            },
            // .options = .{ .draw_aabb = true, .no_scale_rotate = true },
            .options = .{ .draw_aabb = true },
        };
    }

    fn previous_positions_to_object_2d(self: Ball) [PREVIOUS_POSITIONS]Object2d {
        var pp_objects: [PREVIOUS_POSITIONS]Object2d = undefined;
        var pp_index = self.previous_position_index;
        const id: u32 = @intCast(self.id);
        const base_color = Color.from_parts(
            @intCast((id * 64) % 255),
            @intCast((id * 17) % 255),
            @intCast((id * 33) % 255),
            0,
        );
        for (&pp_objects, 0..) |*o, i| {
            const previous_position = self.previous_positions[pp_index];
            var color = base_color;
            color.format.a = @as(u8, @intCast(i)) * 2;
            o.* = .{
                .type = .{ .TextureId = self.texture_id },
                .tint = color,
                .transform = .{
                    .position = previous_position.extend(0.0),
                },
                .size = .{
                    .x = 40.0,
                    .y = 40.0,
                },
                // .options = .{ .with_tint = true, .draw_aabb = true, .no_scale_rotate = true },
                .options = .{ .with_tint = true },
                // .options = .{ .draw_aabb = true, .no_scale_rotate = true },
            };
            pp_index += 1;
            pp_index %= PREVIOUS_POSITIONS;
        }
        return pp_objects;
    }
};

const Table = struct {
    borders: [4]Border,
    texture_id: Textures.Texture.Id,

    const WIDTH = 896;
    const HEIGTH = 514;
    const BORDER = 66;

    const Border = struct {
        collider: Physics.Rectangle,
    };

    fn init(texture_id: Textures.Texture.Id) Table {
        return .{
            .borders = .{
                // left
                .{
                    .collider = .{
                        .position = .{ .x = -WIDTH / 2 + BORDER / 2 },
                        .size = .{ .x = BORDER, .y = HEIGTH },
                    },
                },
                // right
                .{
                    .collider = .{
                        .position = .{ .x = WIDTH / 2 - BORDER / 2 },
                        .size = .{ .x = BORDER, .y = HEIGTH },
                    },
                },
                // bottom
                .{
                    .collider = .{
                        .position = .{ .y = -HEIGTH / 2 + BORDER / 2 },
                        .size = .{ .x = WIDTH, .y = BORDER },
                    },
                },
                // top
                .{
                    .collider = .{
                        .position = .{ .y = HEIGTH / 2 - BORDER / 2 },
                        .size = .{ .x = WIDTH, .y = BORDER },
                    },
                },
            },
            .texture_id = texture_id,
        };
    }

    fn to_screen_quad(
        self: Table,
        camera_controller: *const CameraController2d,
        texture_store: *const Textures.Store,
        screen_quads: *ScreenQuads,
    ) void {
        const table_object: Object2d = .{
            .type = .{ .TextureId = self.texture_id },
            .transform = .{},
            .size = .{
                .x = @floatFromInt(texture_store.get_texture(self.texture_id).width),
                .y = @floatFromInt(texture_store.get_texture(self.texture_id).height),
            },
            .options = .{ .no_alpha_blend = true },
        };
        table_object.to_screen_quad(camera_controller, texture_store, screen_quads);
    }

    fn borders_to_screen_quads(
        self: Table,
        camera_controller: *const CameraController2d,
        screen_quads: *ScreenQuads,
    ) void {
        const border_color = Color.from_parts(255.0, 255.0, 255.0, 64.0);
        for (&self.borders) |*border| {
            const position = camera_controller.transform(border.collider.position.extend(0.0));
            screen_quads.add_quad(.{
                .color = border_color,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .size = border.collider.size.mul_f32(position.z),
                .options = .{ .draw_aabb = true },
            });
        }
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

        self.mouse_drag = .{};
    }

    fn run(
        self: *Self,
        memory: *Memory,
        dt: f32,
        events: []const Events.Event,
        width: i32,
        height: i32,
    ) void {
        const frame_alloc = memory.frame_alloc();
        self.screen_quads.reset();

        Tracing.prepare_next_frame(struct {
            SoftRenderer,
            ScreenQuads,
            _objects,
        });
        Tracing.to_screen_quads(
            struct { SoftRenderer, ScreenQuads, _objects },
            frame_alloc,
            &self.screen_quads,
            &self.font,
            32.0,
        );
        Tracing.zero_current(struct {
            SoftRenderer,
            ScreenQuads,
            _objects,
        });

        if (self.mouse_drag.update(events, dt)) |v| {
            for (&self.balls) |*ball| {
                ball.velocity = ball.velocity.add(v);
            }
        }

        for (&self.balls) |*ball| {
            ball.update(frame_alloc, &self.table, &self.balls, dt);
        }

        self.table.to_screen_quad(
            &self.camera_controller,
            &self.texture_store,
            &self.screen_quads,
        );
        self.table.borders_to_screen_quads(
            &self.camera_controller,
            &self.screen_quads,
        );

        for (&self.balls) |*ball| {
            const bo = ball.to_object_2d();
            bo.to_screen_quad(
                &self.camera_controller,
                &self.texture_store,
                &self.screen_quads,
            );
            const pbo = ball.previous_positions_to_object_2d();
            for (&pbo) |pb| {
                pb.to_screen_quad(
                    &self.camera_controller,
                    &self.texture_store,
                    &self.screen_quads,
                );
            }
        }

        const text_fps = Text.init(
            &self.font,
            std.fmt.allocPrint(
                frame_alloc,
                "FPS: {d:.1} FT: {d:.3}s",
                .{ 1.0 / dt, dt },
            ) catch unreachable,
            32.0,
            .{
                .x = @as(f32, @floatFromInt(width)) / 2.0,
                .y = @as(f32, @floatFromInt(height)) / 2.0 + 300.0,
            },
            0.0,
            .{},
            .{ .dont_clip = true },
        );
        text_fps.to_screen_quads(&self.screen_quads);

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
                    .x = @as(f32, @floatFromInt(width)) / 2.0 + 300.0,
                    .y = @as(f32, @floatFromInt(height)) / 2.0 + 200.0 +
                        25.0 * @as(f32, @floatFromInt(i)),
                },
                0.0,
                .{},
                .{ .dont_clip = true },
            );
            text_ball_info.to_screen_quads(&self.screen_quads);
        }

        self.soft_renderer.start_rendering();
        self.screen_quads.render(
            &self.soft_renderer,
            0.0,
            &self.texture_store,
        );
        const screen_size: Vec2 = .{ .x = @floatFromInt(width), .y = @floatFromInt(height) };
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

    var width: i32 = undefined;
    var height: i32 = undefined;
    sdl.SDL_GetWindowSize(window, &width, &height);

    if (runtime_ptr == null) {
        log.info(@src(), "First time runtime init", .{});
        const game_alloc = memory.game_alloc();
        runtime_ptr = game_alloc.create(Runtime) catch unreachable;
        runtime_ptr.?.init(window, memory, @intCast(width), @intCast(height)) catch unreachable;
    } else {
        var runtime = runtime_ptr.?;
        runtime.run(memory, dt, events, width, height);
    }
    return @ptrCast(runtime_ptr);
}
