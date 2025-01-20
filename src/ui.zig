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
