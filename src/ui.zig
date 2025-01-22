const std = @import("std");
const stygian = @import("stygian_runtime");

const Allocator = std.mem.Allocator;

const Text = stygian.text;
const Font = stygian.font;
const Physics = stygian.physics;
const Color = stygian.color.Color;
const Textures = stygian.textures;
const ScreenQuads = stygian.screen_quads;
const CameraController2d = stygian.camera.CameraController2d;

const _math = stygian.math;
const Vec2 = _math.Vec2;

pub const UiPanel = struct {
    position: Vec2,
    size: Vec2,
    color: Color,

    pub fn init(position: Vec2, size: Vec2, color: Color) UiPanel {
        return .{
            .position = position,
            .size = size,
            .color = color,
        };
    }

    pub fn to_screen_quad(
        self: UiPanel,
        camera_controller: *const CameraController2d,
        screen_quads: *ScreenQuads,
    ) void {
        const position = camera_controller.transform(self.position.extend(0.0));
        screen_quads.add_quad(.{
            .color = self.color,
            .texture_id = Textures.Texture.ID_SOLID_COLOR,
            .position = position.xy().extend(0.0),
            .size = self.size.mul_f32(position.z),
            .options = .{ .clip = false, .no_scale_rotate = true, .no_alpha_blend = true },
        });
    }
};

pub const UiText = struct {
    text: Text,

    pub fn init(position: Vec2, font: *const Font, text: []const u8, text_size: f32) UiText {
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
        self: UiText,
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
        self: UiText,
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

pub const UiDashedLine = struct {
    start: Vec2,
    end: Vec2,

    const COLOR = Color.WHITE;
    const WIDTH: f32 = 10;
    const SEGMENT_GAP: f32 = 10;
    const SEGMENT_LENGTH: f32 = 30;
    const TOTAL_SEGMENT_LEN: f32 = SEGMENT_LENGTH + SEGMENT_GAP;

    const ARROW_ANGLE: f32 = std.math.pi / 4.0;
    const ARROW_H = std.math.sqrt((SEGMENT_LENGTH / 2 * SEGMENT_LENGTH / 2) + (WIDTH / 2 * WIDTH / 2));
    const ARROW_ANGLE_A: f32 = std.math.atan(WIDTH / SEGMENT_LENGTH);
    const ARROW_ANGLE_A_ADJ: f32 = std.math.pi / 4.0 - ARROW_ANGLE_A;
    const ARROW_ANGLE_C: f32 = std.math.pi / 2.0 - ARROW_ANGLE_A_ADJ;
    const ARROW_DELTA: f32 = @sin(ARROW_ANGLE_C) * ARROW_H;
    const ARROW_DELTA_PERP: f32 = @cos(ARROW_ANGLE_C) * ARROW_H;

    pub fn to_screen_quads(
        self: UiDashedLine,
        camera_controller: *const CameraController2d,
        screen_quads: *ScreenQuads,
    ) void {
        const delta = self.end.sub(self.start);
        const delta_len = delta.len();
        const delta_normalized = delta.mul_f32(1.0 / delta_len);
        const c = delta_normalized.cross(.{ .y = 1 });
        const d = delta_normalized.dot(.{ .y = 1 });
        const rotation = if (c < 0.0) -std.math.acos(d) else std.math.acos(d);
        const num_segments: u32 =
            @intFromFloat(@floor(delta_len / TOTAL_SEGMENT_LEN));
        var last_segment_len =
            delta_len - @as(f32, @floatFromInt(num_segments)) * TOTAL_SEGMENT_LEN - ARROW_DELTA;
        var segment_positon = self.start.add(delta_normalized.mul_f32(SEGMENT_LENGTH / 2));
        for (0..num_segments) |_| {
            const position = camera_controller.transform(segment_positon.extend(0.0));
            const size: Vec2 = .{ .x = WIDTH, .y = SEGMENT_LENGTH };
            screen_quads.add_quad(.{
                .color = COLOR,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .rotation = rotation,
                .size = size.mul_f32(position.z),
                .options = .{ .no_alpha_blend = true },
            });

            segment_positon =
                segment_positon.add(delta_normalized.mul_f32(TOTAL_SEGMENT_LEN));
        }

        if (0.0 < last_segment_len) {
            last_segment_len = @min(last_segment_len, SEGMENT_LENGTH);
            segment_positon = segment_positon
                .add(delta_normalized
                .mul_f32(-SEGMENT_LENGTH / 2 + last_segment_len / 2.0));
            const position = camera_controller.transform(segment_positon.extend(0.0));
            const size: Vec2 = .{ .x = WIDTH, .y = last_segment_len };
            screen_quads.add_quad(.{
                .color = COLOR,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .rotation = rotation,
                .size = size.mul_f32(position.z),
                .options = .{ .no_alpha_blend = true },
            });
        }

        const delta_perp = delta_normalized.perp();

        {
            const arrow_left_segment_positon = self.end.add(delta_normalized
                .mul_f32(-ARROW_DELTA)).add(delta_perp.mul_f32(ARROW_DELTA_PERP));
            const position = camera_controller.transform(arrow_left_segment_positon.extend(0.0));
            const size: Vec2 = .{ .x = WIDTH, .y = SEGMENT_LENGTH };
            screen_quads.add_quad(.{
                .color = COLOR,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .rotation = rotation + ARROW_ANGLE,
                .size = size.mul_f32(position.z),
                .options = .{ .no_alpha_blend = true },
            });
        }

        {
            const arrow_right_segment_positon = self.end.add(delta_normalized
                .mul_f32(-ARROW_DELTA)).add(delta_perp.mul_f32(-ARROW_DELTA_PERP));
            const position = camera_controller.transform(arrow_right_segment_positon.extend(0.0));
            const size: Vec2 = .{ .x = WIDTH, .y = SEGMENT_LENGTH };
            screen_quads.add_quad(.{
                .color = COLOR,
                .texture_id = Textures.Texture.ID_SOLID_COLOR,
                .position = position.xy().extend(0.0),
                .rotation = rotation - ARROW_ANGLE,
                .size = size.mul_f32(position.z),
                .options = .{ .no_alpha_blend = true },
            });
        }
    }
};
