const std = @import("std");
const stygian = @import("stygian_runtime");

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

const TABLE_WIDTH = 896;
const TABLE_HEIGTH = 514;
const TABLE_BORDER = 66;

const Ball = struct {
    id: u8,
    collider: Physics.Circle,
    previous_position: Vec2,
    velocity: Vec2,
    friction: f32,

    pub fn update(self: *Ball, borders: []const Border, balls: []const Ball, dt: f32) void {
        for (balls) |*ball| {
            if (self.id == ball.id)
                continue;
            const collision_point =
                Physics.circle_circle_collision(self.collider, ball.collider);
            if (collision_point) |cp| {
                if (cp.normal.is_valid()) {
                    const proj = cp.normal.mul_f32(-self.velocity.dot(cp.normal));
                    self.velocity = self.velocity.add(proj.mul_f32(2.0));
                    const new_positon =
                        cp.position.add(cp.normal.mul_f32(self.collider.radius));
                    self.previous_position = self.collider.position;
                    self.collider.position = new_positon;
                }
            }
        }
        for (borders) |*border| {
            const collision_point =
                Physics.circle_rectangle_collision(self.collider, border.collider);
            if (collision_point) |cp| {
                if (cp.normal.is_valid()) {
                    const proj = cp.normal.mul_f32(-self.velocity.dot(cp.normal));
                    self.velocity = self.velocity.add(proj.mul_f32(2.0));
                    const new_positon =
                        cp.position.add(cp.normal.mul_f32(self.collider.radius));
                    self.previous_position = self.collider.position;
                    self.collider.position = new_positon;
                } else {
                    var prev_collider = self.collider;
                    prev_collider.position = self.previous_position;
                    const ncp =
                        Physics.circle_rectangle_closest_collision_point(
                        prev_collider,
                        border.collider,
                    );
                    const proj = ncp.normal.mul_f32(-self.velocity.dot(ncp.normal));
                    self.velocity = self.velocity.add(proj.mul_f32(2.0));
                    const new_positon =
                        ncp.position.add(ncp.normal.mul_f32(self.collider.radius));
                    self.previous_position = self.collider.position;
                    self.collider.position = new_positon;
                }
            }
        }
        self.previous_position = self.collider.position;
        self.collider.position = self.collider.position.add(self.velocity.mul_f32(dt));
        self.velocity = self.velocity.mul_f32(self.friction);
    }
};

const Border = struct {
    collider: Physics.Rectangle,
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

    screen_quads: ScreenQuads,
    soft_renderer: SoftRenderer,

    balls: [16]Ball,
    borders: [4]Border,

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

        self.screen_quads = try ScreenQuads.init(memory, 2048);
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
                .collider = .{
                    .position = position,
                    .radius = 20.0,
                },
                .previous_position = .{},
                .velocity = .{},
                .friction = 0.95,
            };
        }
        self.borders = .{
            // left
            .{
                .collider = .{
                    .position = .{ .x = -TABLE_WIDTH / 2 + TABLE_BORDER / 2 },
                    .size = .{ .x = TABLE_BORDER, .y = TABLE_HEIGTH },
                },
            },
            // right
            .{
                .collider = .{
                    .position = .{ .x = TABLE_WIDTH / 2 - TABLE_BORDER / 2 },
                    .size = .{ .x = TABLE_BORDER, .y = TABLE_HEIGTH },
                },
            },
            // bottom
            .{
                .collider = .{
                    .position = .{ .y = -TABLE_HEIGTH / 2 + TABLE_BORDER / 2 },
                    .size = .{ .x = TABLE_WIDTH, .y = TABLE_BORDER },
                },
            },
            // top
            .{
                .collider = .{
                    .position = .{ .y = TABLE_HEIGTH / 2 - TABLE_BORDER / 2 },
                    .size = .{ .x = TABLE_WIDTH, .y = TABLE_BORDER },
                },
            },
        };
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
        _ = memory;

        self.screen_quads.reset();

        if (self.mouse_drag.update(events, dt)) |v| {
            for (&self.balls) |*ball| {
                ball.velocity = ball.velocity.add(v);
            }
        }

        const collision_0 =
            Physics.circle_rectangle_collision(self.balls[0].collider, self.borders[0].collider);
        const collision_1 =
            Physics.circle_rectangle_collision(self.balls[0].collider, self.borders[1].collider);
        const collision_2 =
            Physics.circle_rectangle_collision(self.balls[0].collider, self.borders[2].collider);
        const collision_3 =
            Physics.circle_rectangle_collision(self.balls[0].collider, self.borders[3].collider);
        const collisions = [_]?Physics.CollisionPoint{
            collision_0,
            collision_1,
            collision_2,
            collision_3,
        };

        for (&self.balls) |*ball| {
            ball.update(&self.borders, &self.balls, dt);
        }

        const collision_color = Color.from_parts(255.0, 0.0, 0.0, 64.0);
        const no_collision_color = Color.from_parts(255.0, 255.0, 255.0, 64.0);

        const objects = [_]Object2d{
            .{
                .type = .{ .TextureId = self.texture_poll_table },
                .transform = .{
                    .position = .{ .z = 0 },
                },
                .size = .{
                    .x = @floatFromInt(self.texture_store.get_texture(self.texture_poll_table).width),
                    .y = @floatFromInt(self.texture_store.get_texture(self.texture_poll_table).height),
                },
            },
            .{
                .type = .{ .Color = if (collision_0) |_| collision_color else no_collision_color },
                .transform = .{
                    .position = self.borders[0].collider.position.extend(0.0),
                },
                .size = self.borders[0].collider.size,
                .options = .{ .draw_aabb = true },
            },
            .{
                .type = .{ .Color = if (collision_1) |_| collision_color else no_collision_color },
                .transform = .{
                    .position = self.borders[1].collider.position.extend(0.0),
                },
                .size = self.borders[1].collider.size,
                .options = .{ .draw_aabb = true },
            },
            .{
                .type = .{ .Color = if (collision_2) |_| collision_color else no_collision_color },
                .transform = .{
                    .position = self.borders[2].collider.position.extend(0.0),
                },
                .size = self.borders[2].collider.size,
                .options = .{ .draw_aabb = true },
            },
            .{
                .type = .{ .Color = if (collision_3) |_| collision_color else no_collision_color },
                .transform = .{
                    .position = self.borders[3].collider.position.extend(0.0),
                },
                .size = self.borders[3].collider.size,
                .options = .{ .draw_aabb = true },
            },
        };

        for (&objects) |*object| {
            object.to_screen_quad(
                &self.camera_controller,
                &self.texture_store,
                &self.screen_quads,
            );
        }

        var ball_objects: [16]Object2d = undefined;
        for (&self.balls, &ball_objects) |*ball, *bo| {
            bo.* =
                .{
                .type = .{ .TextureId = self.texture_ball },
                .transform = .{
                    .position = ball.collider.position.extend(0.0),
                },
                .size = .{
                    .x = 40.0,
                    .y = 40.0,
                },
                .options = .{ .draw_aabb = true },
            };
        }

        for (&ball_objects) |*object| {
            object.to_screen_quad(
                &self.camera_controller,
                &self.texture_store,
                &self.screen_quads,
            );
        }

        self.soft_renderer.start_rendering();
        self.screen_quads.render(
            &self.soft_renderer,
            0.0,
            &self.texture_store,
        );
        const screen_size: Vec2 = .{ .x = @floatFromInt(width), .y = @floatFromInt(height) };
        for (collisions) |collision| {
            if (collision) |c| {
                const c_position = c.position
                    .add(screen_size.mul_f32(0.5));
                self.soft_renderer
                    .draw_color_rect(c_position, .{ .x = 5.0, .y = 5.0 }, Color.BLUE, false);
                if (c.normal.is_valid()) {
                    const c_normal_end = c_position.add(c.normal.mul_f32(20.0));
                    self.soft_renderer.draw_line(c_position, c_normal_end, Color.GREEN);
                }
            }
        }
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
