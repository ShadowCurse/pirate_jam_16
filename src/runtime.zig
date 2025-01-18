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
    collider: Physics.Circle,
    velocity: Vec2,
    friction: f32,

    pub fn update(self: *Ball, collision_points: []const ?Physics.CollisionPoint, dt: f32) void {
        for (collision_points) |collision_point| {
            if (collision_point) |cp| {
                if (cp.normal.is_valid()) {
                    const proj = cp.normal.mul_f32(-self.velocity.dot(cp.normal));
                    self.velocity = self.velocity.add(proj.mul_f32(2.0));
                    const point_on_the_circle =
                        self.collider.position.add(cp.normal.mul_f32(self.collider.radius));
                    const to_move = cp.position.sub(point_on_the_circle);
                    self.collider.position = self.collider.position.sub(to_move);
                }
            }
        }
        self.collider.position = self.collider.position.add(self.velocity.mul_f32(dt));
        self.velocity = self.velocity.mul_f32(self.friction);
    }
};

const Border = struct {
    collider: Physics.Rectangle,
};

const Runtime = struct {
    camera_controller: CameraController2d,

    texture_store: Textures.Store,
    texture_poll_table: Textures.Texture.Id,
    texture_ball: Textures.Texture.Id,

    screen_quads: ScreenQuads,
    soft_renderer: SoftRenderer,

    ball: Ball,
    borders: [4]Border,

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

        self.ball = .{
            .collider = .{
                .radius = 20.0,
            },
            .velocity = .{},
            .friction = 0.95,
        };
        self.borders = .{
            .{
                .collider = .{
                    .position = .{ .x = -TABLE_WIDTH / 2 + TABLE_BORDER / 2 },
                    .size = .{ .x = TABLE_BORDER, .y = TABLE_HEIGTH },
                },
            },
            .{
                .collider = .{
                    .position = .{ .x = TABLE_WIDTH / 2 - TABLE_BORDER / 2 },
                    .size = .{ .x = TABLE_BORDER, .y = TABLE_HEIGTH },
                },
            },
            .{
                .collider = .{
                    .position = .{ .y = -TABLE_HEIGTH / 2 + TABLE_BORDER / 2 },
                    .size = .{ .x = TABLE_WIDTH, .y = TABLE_BORDER },
                },
            },
            .{
                .collider = .{
                    .position = .{ .y = TABLE_HEIGTH / 2 - TABLE_BORDER / 2 },
                    .size = .{ .x = TABLE_WIDTH, .y = TABLE_BORDER },
                },
            },
        };
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

        for (events) |event| {
            switch (event) {
                .Keyboard => |key| {
                    if (key.type == .Pressed) {
                        switch (key.key) {
                            .UP => {
                                self.ball.velocity.y -= 10.0;
                            },
                            .DOWN => {
                                self.ball.velocity.y += 10.0;
                            },
                            .LEFT => {
                                self.ball.velocity.x -= 10.0;
                            },
                            .RIGHT => {
                                self.ball.velocity.x += 10.0;
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }

        const collision_0 =
            Physics.circle_rectangle_collision(self.ball.collider, self.borders[0].collider);
        const collision_1 =
            Physics.circle_rectangle_collision(self.ball.collider, self.borders[1].collider);
        const collision_2 =
            Physics.circle_rectangle_collision(self.ball.collider, self.borders[2].collider);
        const collision_3 =
            Physics.circle_rectangle_collision(self.ball.collider, self.borders[3].collider);
        const collisions = [_]?Physics.CollisionPoint{ collision_0, collision_1, collision_2, collision_3 };

        self.ball.update(&collisions, dt);

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
                .type = .{ .TextureId = self.texture_ball },
                .transform = .{
                    .position = self.ball.collider.position.extend(0.0),
                },
                .size = .{
                    .x = 40.0,
                    .y = 40.0,
                },
                .options = .{ .draw_aabb = true },
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

        self.soft_renderer.start_rendering();
        self.screen_quads.render(
            &self.soft_renderer,
            0.0,
            &self.texture_store,
        );
        for (collisions) |collision| {
            if (collision) |c| {
                const c_position = c.position
                    .add((Vec2{ .x = @floatFromInt(width), .y = @floatFromInt(height) }).mul_f32(0.5));
                self.soft_renderer
                    .draw_color_rect(c_position, .{ .x = 5.0, .y = 5.0 }, Color.BLUE, false);
                if (c.normal.is_valid()) {
                    const c_normal_end = c_position.add(c.normal.mul_f32(20.0));
                    self.soft_renderer.draw_line(c_position, c_normal_end, Color.GREEN);
                }
            }
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
