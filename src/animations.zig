const stygian = @import("stygian_runtime");
const log = stygian.log;
const CameraController2d = stygian.camera.CameraController2d;

const _math = stygian.math;
const Vec2 = _math.Vec2;
const Vec3 = _math.Vec3;

const _runtime = @import("runtime.zig");
const State = _runtime.State;

const _objects = @import("objects.zig");
const Ball = _objects.Ball;

pub const SmoothStepAnimation = struct {
    start_position: Vec3 = .{},
    end_position: Vec3 = .{},
    duration: f32 = 0.0,
    progress: f32 = 0.0,

    pub fn update(self: *SmoothStepAnimation, position: *Vec3, dt: f32) bool {
        const p = self.progress / self.duration;
        const t = p * p * (3.0 - 2.0 * p);
        position.* = self.start_position.lerp(self.end_position, t);
        self.progress += dt;
        return self.duration <= self.progress;
    }
};

pub const StateChangeAnimation = struct {
    camera: *CameraController2d,
    animation: ?SmoothStepAnimation = null,
    state: *State,
    final_state: State = .{},

    const DURATION = 1.0;

    pub fn is_playing(self: StateChangeAnimation) bool {
        return self.animation != null;
    }

    pub fn set(
        self: *StateChangeAnimation,
        target_position: Vec2,
        final_state: State,
    ) void {
        const camera_worl_position = self.camera.world_position().xy();
        const delta = target_position.sub(camera_worl_position);
        self.animation = .{
            .start_position = self.camera.position,
            .end_position = self.camera.position.add(delta.extend(0.0)),
            .duration = DURATION,
            .progress = 0.0,
        };
        self.final_state = final_state;
    }

    pub fn update(self: *StateChangeAnimation, dt: f32) void {
        if (self.animation) |*a| {
            if (a.update(&self.camera.position, dt)) {
                self.animation = null;
                self.state.* = self.final_state;
            }
        }
    }
};

pub const MoveAnimation = struct {
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

pub const BallAnimations = struct {
    animations: [36]BallAnimation = undefined,
    animation_n: u32 = 0,

    const BallAnimation = struct {
        ball: *Ball,
        move_animation: MoveAnimation,
    };

    pub fn add(self: *BallAnimations, ball: *Ball, target: Vec2, duration: f32) void {
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
            .ball = ball,
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

    pub fn run(self: *BallAnimations, dt: f32) bool {
        var start: u32 = 0;
        while (start < self.animation_n) {
            const animation = &self.animations[start];
            const ball = animation.ball;
            if (animation.move_animation.update(&ball.body.position, dt)) {
                log.info(@src(), "Removing ball animation from slot: {d}", .{start});
                self.animations[start] = self.animations[self.animation_n - 1];
                self.animation_n -= 1;
            } else {
                start += 1;
            }
        }
        return self.animation_n == 0;
    }
};
