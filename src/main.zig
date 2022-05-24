const std = @import("std");
const tractor = @import("tractor.zig");

const ray = @cImport(
    @cInclude("raylib.h"),
);

const fps: i32 = 60;
const inv_fps: f32 = 1.0 / @intToFloat(f32, fps);
const res_x: u32 = 640 / 2;
const res_y: u32 = 480 / 2;
const num_pixels = res_x * res_y;

fn update(rand: std.rand.Random, sides: bool, pixels: []ray.Color) bool {
    var ret = false;
    _ = sides;
    var row: u32 = res_y - 1;
    while (row > 0) {
        row -= 1;
        var x: u32 = 0;
        var decreasing_row = (rand.float(f32) > 0.5);
        while (x < res_x) : (x += 1) {
            var col: u32 = if (decreasing_row) res_x - x - 1 else x;
            var i = row * res_x + col;

            var below = i + res_x;
            var l_below = i + res_x - 1;
            var r_below = i + res_x + 1;

            if (pixels[i].a == 0)
                continue;

            if (pixels[below].a == 0) {
                pixels[below] = pixels[i];
                pixels[i] = ray.BLANK;
                continue;
            }

            // Check left or right first?
            if (rand.float(f32) > 0.5) {
                // Check to the lower left
                if (!sides and col == 0) {
                    pixels[i] = ray.BLANK;
                    continue;
                }
                if (col != 0 and pixels[l_below].a == 0) {
                    pixels[l_below] = pixels[i];
                    pixels[i] = ray.BLANK;
                    continue;
                }
                // Check the lower right
                if (!sides and col == (res_x - 1)) {
                    pixels[i] = ray.BLANK;
                    continue;
                }
                if (col != res_x - 1 and pixels[r_below].a == 0) {
                    pixels[r_below] = pixels[i];
                    pixels[i] = ray.BLANK;
                    continue;
                }
            } else {
                // Check the lower right
                if (!sides and col == (res_x - 1)) {
                    pixels[i] = ray.BLANK;
                    continue;
                }
                if (col != res_x - 1 and pixels[r_below].a == 0) {
                    pixels[r_below] = pixels[i];
                    pixels[i] = ray.BLANK;
                    continue;
                }
                // Check to the lower left
                if (!sides and col == 0) {
                    pixels[i] = ray.BLANK;
                    continue;
                }
                if (col != 0 and pixels[l_below].a == 0) {
                    pixels[l_below] = pixels[i];
                    pixels[i] = ray.BLANK;
                    continue;
                }
            }
            if (row < 10) {
                ret = true;
            }
        }
    }
    return ret;
}

/// Alogrithm R
/// https://en.wikipedia.org/wiki/Reservoir_sampling#Simple_algorithm
fn reservoirSample(rand: std.rand.Random, s: []u32, r: []u32) void {
    for (r) |*r_ptr, i| {
        r_ptr.* = s[i];
    }

    for (s[r.len..]) |i| {
        var j = rand.intRangeAtMost(u32, 0, @intCast(u32, i));
        if (j < r.len)
            r[j] = s[i];
    }
}

/// Fisher Yates Shuffle (modern)
/// https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle#The_modern_algorithm
fn shuffle(rand: std.rand.Random, r: []u32) void {
    var i = r.len - 1;
    while (i > 0) : (i -= 1) {
        var j = rand.intRangeAtMost(u32, 0, @intCast(u32, i));
        var tmp = r[i];
        r[i] = r[j];
        r[j] = tmp;
    }
}

const gamma_glsl =
    \\#version 330
    \\
    \\// Input vertex attributes (from vertex shader)
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\
    \\// Input uniform values
    \\uniform sampler2D texture0;
    \\uniform vec4 colDiffuse;
    \\
    \\// Output fragment color
    \\out vec4 finalColor;
    \\
    \\// NOTE: Add here your custom variables
    \\
    \\void main()
    \\{
    \\    // Texel color fetching from texture sampler
    \\    vec4 texelColor = texture(texture0, fragTexCoord)*colDiffuse*fragColor;
    \\
    \\    // Calculate final fragment color
    \\    finalColor = pow(texelColor, vec4(0.4545));
    \\}
;

pub fn main() anyerror!void {

    // Start data gathering
    var ctxs = [_]tractor.ThreadContext{.{}} ** 4;
    for (ctxs) |*ctx, i| {
        ctx.prng = std.rand.DefaultPrng.init(i).random();
        _ = try tractor.startGenerator(ctx);
    }
    ctxs[0].size = 1;
    ctxs[1].size = 10;
    ctxs[2].size = 20;
    ctxs[3].size = 50;

    // Seed the random number generator
    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.os.getrandom(std.mem.asBytes(&seed)) catch {
            break :blk 42;
        };
        break :blk 42;
    });
    const rand = prng.random();

    //ray.SetTraceLogLevel(ray.LOG_INFO);
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT);
    ray.InitWindow(res_x * 2, res_y * 2, "sandfarm");
    ray.SetWindowState(ray.FLAG_WINDOW_ALWAYS_RUN);

    ray.SetTargetFPS(fps);

    // Get shader to apply a gamma correction to the texture
    var gamma_shader = ray.LoadShaderFromMemory(null, gamma_glsl);
    defer ray.UnloadShader(gamma_shader);

    // Build the texture buffer which we'll use as our canvas
    var img = ray.GenImageColor(res_x, res_y, ray.BLANK);
    defer ray.UnloadImage(img);

    var tex = ray.LoadTextureFromImage(img);
    defer ray.UnloadTexture(tex);
    ray.SetTextureFilter(tex, ray.TEXTURE_FILTER_POINT);
    ray.SetTextureWrap(tex, ray.TEXTURE_WRAP_CLAMP);

    // Set canvas to be blank by default
    var pixels = [_]ray.Color{ray.BLANK} ** (res_x * res_y);
    ray.UpdateTexture(tex, &pixels);

    // Setup a pool and reservoir to hold our randomly selected
    // pixel placements
    var pool = [_]u32{0} ** (res_x / 4);
    for (pool) |_, i| {
        pool[i] = @intCast(u32, i);
    }
    var reservoir = [_]u32{0} ** (res_x / 4);

    var msgs = [_]tractor.MessageCounts{.{}} ** 4;
    var steps = [_]u32{fps} ** 4;

    // State of
    var clear_steps: usize = 0;
    var sides: bool = true;

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        ray.ClearBackground(ray.BLACK);
        ray.BeginShaderMode(gamma_shader);
        ray.DrawTextureTiled(
            tex,
            .{ .x = 0, .y = 0, .width = res_x, .height = res_y },
            .{ .x = 0, .y = 0, .width = res_x * 2, .height = res_y * 2 },
            .{ .x = 0, .y = 0 },
            0.0,
            2.0,
            ray.WHITE,
        );
        ray.EndShaderMode();
        ray.DrawFPS(10, 10);
        ray.EndDrawing();

        for (ctxs) |*ctx, i| {
            var ctx_msgs = tractor.getMessages(ctx);
            if (ctx_msgs) |msg| {
                msgs[i].add(msg);
                steps[i] = fps;
            }

            if (msgs[i].hasMsgs() and steps[i] > 0) {
                defer steps[i] -= 1;

                var step_msgs = tractor.MessageCounts{};

                var msg_pct: f32 = undefined;
                if (msgs[i].active > 0) {
                    msg_pct = @intToFloat(f32, msgs[i].active) / @intToFloat(f32, steps[i]);
                    step_msgs.active = @floatToInt(u32, msg_pct);
                    if (@mod(msg_pct, 1.0) > rand.float(f32))
                        step_msgs.active += 1;
                }

                if (msgs[i].blocked > 0) {
                    msg_pct = @intToFloat(f32, msgs[i].blocked) / @intToFloat(f32, steps[i]);
                    step_msgs.blocked = @floatToInt(u32, msg_pct);
                    if (@mod(msg_pct, 1.0) > rand.float(f32))
                        step_msgs.blocked += 1;
                }

                if (msgs[i].err > 0) {
                    msg_pct = @intToFloat(f32, msgs[i].err) / @intToFloat(f32, steps[i]);
                    step_msgs.err = @floatToInt(u32, msg_pct);
                    if (@mod(msg_pct, 1.0) > rand.float(f32))
                        step_msgs.err += 1;
                }

                if (msgs[i].done > 0) {
                    msg_pct = @intToFloat(f32, msgs[i].done) / @intToFloat(f32, steps[i]);
                    step_msgs.done = @floatToInt(u32, msg_pct);
                    if (@mod(msg_pct, 1.0) > rand.float(f32))
                        step_msgs.done += 1;
                }

                var total = (step_msgs.active + step_msgs.err + step_msgs.done + step_msgs.blocked);
                if (total >= res_x / 4) {
                    std.debug.print("Warning: total pixels, {}, more than buffer.", .{total});
                    total = @minimum(total, res_x / 4 - 1);
                }

                if (total > 0) {
                    reservoirSample(rand, pool[0..], reservoir[0..total]);
                    shuffle(rand, reservoir[0..total]);

                    var pixel_offset = (i * res_x / 4);

                    var start: u32 = 0;
                    for (reservoir[start .. step_msgs.err + start]) |x| {
                        pixels[x + pixel_offset] = ray.RED;
                    }
                    start += step_msgs.err;
                    for (reservoir[start .. step_msgs.active + start]) |x| {
                        //pixels[x] = ray.LIME;
                        pixels[x + pixel_offset] = ray.ColorFromHSV(
                            125.0,
                            rand.float(f32) * 0.15 + 0.6,
                            rand.float(f32) * 0.45 + 0.35,
                        );
                    }
                    start += step_msgs.active;
                    for (reservoir[start .. step_msgs.done + start]) |x| {
                        //pixels[x] = ray.SKYBLUE;
                        pixels[x + pixel_offset] = ray.ColorFromHSV(
                            215.0,
                            rand.float(f32) * 0.15 + 0.6,
                            rand.float(f32) * 0.45 + 0.35,
                        );
                    }
                    start += step_msgs.done;
                    for (reservoir[start .. step_msgs.blocked + start]) |x| {
                        //pixels[x] = ray.ORANGE;
                        pixels[x + pixel_offset] = ray.ColorFromHSV(
                            50.0,
                            rand.float(f32) * 0.15 + 0.6,
                            rand.float(f32) * 0.45 + 0.35,
                        );
                    }
                    msgs[i].sub(step_msgs);
                }
            }
        }

        var clear = update(rand, sides, pixels[0..]);
        ray.UpdateTexture(tex, &pixels);

        if (clear) {
            clear_steps = 400;
            sides = false;
        }
        if (clear_steps > 0) {
            clear_steps -= 1;
            //var pix: u32 = 1;
            //while (pix < res_x) : (pix += 6) {
            //    pixels[(res_x*res_y)-pix] = ray.BLANK;
            //    pixels[(res_x*res_y)-(pix+1)] = ray.BLANK;
            //    pixels[(res_x*res_y)-(pix+2)] = ray.BLANK;
            //}
            var pix: u32 = 0;
            while (pix < res_x) : (pix += 1) {
                var offset_start = (res_x * res_y - 1);
                if (rand.float(f32) > 0.5) {
                    pixels[offset_start - pix] = ray.BLANK;
                }
            }
            if (clear_steps == 0) sides = true;
        }

        //if ( ray.IsMouseButtonPressed(0) ) {
        //    var x = @divFloor(ray.GetMouseX(), 2);
        //    var y = @divFloor(ray.GetMouseY(), 2);
        //    var offset = @intCast(usize, res_x*y + x);
        //    pixels[offset] = ray.RED;
        //}

    }
}
