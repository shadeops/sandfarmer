const std = @import("std");
const randmsgs = @import("randmsgs.zig");

const users = @import("users.zig");
const tractor = @import("tractor.zig");

const mbox = @import("mbox.zig");

const ray = @cImport(
    @cInclude("raylib.h"),
);

const world_png = @embedFile("../resources/map.png");
const shader_glsl = @embedFile("../resources/shader.glsl");

const urls = [_][]const u8{
    "http://127.0.0.1:3000/Tractor/monitor",
    "http://127.0.0.1:3001/Tractor/monitor",
    "http://127.0.0.1:3002/Tractor/monitor",
    "http://127.0.0.1:3003/Tractor/monitor",
};

const user_url = "http://127.0.0.1:3001/whoswho";

const fps: i32 = 60;
const res_x: u32 = 320;
const res_y: u32 = 240;
const window_scale: u32 = 3;
const win_x: u32 = res_x * window_scale;
const win_y: u32 = res_y * window_scale;
const sections: u32 = 4;
const fade_duration: u8 = 120;
const drain_steps: u32 = 360;

const debug = false;

fn update(rand: std.rand.Random, sides: bool, pixels: []ray.Color, erase: bool) bool {
    var ret = false;
    var row: u32 = res_y;
    while (row > 0) {
        row -= 1;
        var x: u32 = 0; // counter
        var i: u32 = 0; // pixel index
        var col: u32 = 0;
        var decreasing_row = (rand.float(f32) > 0.5);

        x = 0;
        while (x < res_x) : (x += 1) {
            col = if (decreasing_row) (res_x - x) - 1 else x;
            i = row * res_x + col;

            if ((pixels[i].r & 0b1) == 0) continue;
            if (pixels[i].r == 255 and pixels[i].g == 255 and pixels[i].b == 255 and pixels[i].a == 255) {
                if (erase) pixels[i] = ray.BLANK;
                continue;
            }

            if (row == res_y-1) continue;

            var below = i + res_x;
            if ((pixels[below].r & 0b1) == 0) {
                if (debug) std.debug.print("Moving {} below to {}\n", .{ i, below });
                pixels[below] = pixels[i];
                pixels[i] = ray.BLANK;
                continue;
            }

            var l_below = i + res_x - 1;
            var r_below = i + res_x + 1;

            // Check left or right first?
            if (rand.float(f32) > 0.5) {
                // Check to the lower left
                if (!sides and col == 0) {
                    pixels[i] = ray.BLANK;
                    continue;
                }
                if (col != 0 and (pixels[l_below].r & 0b1) == 0) {
                    if (debug) std.debug.print("Moving {} below left to {}\n", .{ i, l_below });
                    pixels[l_below] = pixels[i];
                    pixels[i] = ray.BLANK;
                    continue;
                }
                // Check the lower right
                if (!sides and col == (res_x - 1)) {
                    pixels[i] = ray.BLANK;
                    continue;
                }
                if (col != res_x - 1 and (pixels[r_below].r & 0b1) == 0) {
                    if (debug) std.debug.print("Moving {} below right to {}\n", .{ i, r_below });
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
                if ((col != res_x - 1) and (pixels[r_below].r & 0b1) == 0) {
                    if (debug) std.debug.print("Moving {} below right to {}\n", .{ i, r_below });
                    pixels[r_below] = pixels[i];
                    pixels[i] = ray.BLANK;
                    continue;
                }
                // Check to the lower left
                if (!sides and col == 0) {
                    pixels[i] = ray.BLANK;
                    continue;
                }
                if (col != 0 and (pixels[l_below].r & 0b1) == 0) {
                    if (debug) std.debug.print("Moving {} below left to {}\n", .{ i, l_below });
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

fn encodeColor(rand: std.rand.Random, msg: mbox.Msg) ray.Color {
    var clr = ray.BLANK;
    _ = rand;
    _ = msg;
    clr.r = @intCast(u8, ((msg.jid >> 8) & 0b0001_1111) << 1);
    clr.r |= (rand.intRangeAtMost(u8, 0, 3) << 6);
    clr.r |= 0b1;

    clr.g = @intCast(u8, msg.jid & 0b1111_1111);

    clr.b = @intCast(u8, (msg.owner >> 8) & 0b0011_1111);
    clr.b |= (@intCast(u8, @enumToInt(msg.msg)) << 6);

    clr.a = @intCast(u8, msg.owner & 0b1111_1111);
    return clr;
}

fn drawPixel(pixels: []ray.Color, clr: ray.Color, x: i32, y: i32) void {
    if (x < 0 or y < 0 or x >= res_x or y >= res_y) return;
    var offset = @minimum(
        @intCast(usize, res_x * @intCast(u32, y) + @intCast(u32, x)),
        res_x * res_y - 1,
    );
    pixels[offset] = clr;
}

fn drawColor(pixels: []ray.Color, clr: ray.Color) void {
    var x: i32 = ray.GetMouseX();
    var y: i32 = ray.GetMouseY();
    if (x < 0 or y < 0 or x >= win_x or y >= win_y) return;
    x = @divFloor(x, window_scale);
    y = @divFloor(y, window_scale);
    drawPixel(pixels, clr, x, y);
    drawPixel(pixels, clr, x + 1, y);
    drawPixel(pixels, clr, x - 1, y);
    drawPixel(pixels, clr, x, y + 1);
    drawPixel(pixels, clr, x, y - 1);
}

pub fn main() anyerror!void {
    //var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    //defer arena.deinit();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked) std.debug.print("Leaked\n", .{});
    }
    var allocator = gpa.allocator();
    var user_map = try users.queryUsers(allocator, user_url);
    defer user_map.deinit();

    var ctxs = [_]tractor.Context{undefined} ** sections;
    for (ctxs) |*ctx, i| {
        ctx.* = .{
            .allocator = std.heap.page_allocator,
            .url = urls[i],
            .usermap = &user_map,
            .mbuffer = .{
                .msgs = try std.heap.page_allocator.alloc(mbox.Msg, (fps * res_x) / sections),
            },
        };
        var thread = try ctx.startThread();
        thread.detach();
    }

    // TODO fix mbuffer leak

    var user_name = std.os.getenv("USER");
    var uid: i32 = 128 * 128 - 1;
    if (user_name != null) {
        uid = @intCast(i32, user_map.getUid(user_name.?) orelse (128 * 128 - 2));
    }

    // Seed the random number generator
    var prng = std.rand.DefaultPrng.init(42);
    const rand = prng.random();

    ray.SetTraceLogLevel(ray.LOG_DEBUG);
    //ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT);
    ray.InitWindow(win_x, win_y, "sandfarm");
    ray.SetWindowState(ray.FLAG_WINDOW_ALWAYS_RUN);

    ray.SetTargetFPS(fps);

    // Get shader to apply a gamma correction to the texture
    var shader = ray.LoadShaderFromMemory(null, shader_glsl);
    defer ray.UnloadShader(shader);

    var usr_tex_loc = ray.GetShaderLocation(shader, "user_texture");
    var rnd_tex_loc = ray.GetShaderLocation(shader, "rand_texture");
    var mode_uni_loc = ray.GetShaderLocation(shader, "mode");
    var user_uni_loc = ray.GetShaderLocation(shader, "current_user");

    var tex_pixels: []ray.Color = undefined;

    var world_img = ray.LoadImageFromMemory(".png", world_png, world_png.len);
    var world_tex = ray.LoadTextureFromImage(world_img);
    defer ray.UnloadTexture(world_tex);
    ray.UnloadImage(world_img);

    // Build the texture buffer which we'll use as our canvas
    var img = ray.GenImageColor(res_x, res_y, ray.BLANK);
    defer ray.UnloadImage(img);

    var tex = ray.LoadTextureFromImage(img);
    defer ray.UnloadTexture(tex);
    ray.SetTextureFilter(tex, ray.TEXTURE_FILTER_POINT);
    ray.SetTextureWrap(tex, ray.TEXTURE_WRAP_CLAMP);

    var usr_img = ray.GenImageColor(128, 128, ray.BLANK);
    var usr_tex = ray.LoadTextureFromImage(usr_img);
    defer ray.UnloadTexture(usr_tex);
    ray.UnloadImage(usr_img);
    ray.SetTextureFilter(usr_tex, ray.TEXTURE_FILTER_POINT);
    ray.SetTextureWrap(usr_tex, ray.TEXTURE_WRAP_CLAMP);
    ray.UpdateTexture(usr_tex, user_map.users.ptr);

    var rnd_img = ray.GenImageColor(256, 256, ray.BLANK);
    var rnd_tex = ray.LoadTextureFromImage(rnd_img);
    defer ray.UnloadTexture(rnd_tex);
    ray.UnloadImage(rnd_img);
    ray.SetTextureFilter(rnd_tex, ray.TEXTURE_FILTER_POINT);
    ray.SetTextureWrap(rnd_tex, ray.TEXTURE_WRAP_CLAMP);
    tex_pixels = try allocator.alloc(ray.Color, 256 * 256);
    for (tex_pixels) |*pixel| {
        // TODO instead of just random we could make these stratified to get the
        // maximum spacing between colors
        pixel.* = .{
            .r = rand.intRangeAtMost(u8, 0, 255),
            .g = rand.intRangeAtMost(u8, 0, 255),
            .b = rand.intRangeAtMost(u8, 0, 255),
            .a = rand.intRangeAtMost(u8, 0, 255),
        };
    }
    ray.UpdateTexture(rnd_tex, tex_pixels.ptr);
    allocator.free(tex_pixels);

    // Set canvas to be blank by default
    var pixels = [_]ray.Color{ray.BLANK} ** (res_x * res_y);
    ray.UpdateTexture(tex, &pixels);

    // Setup a pool and reservoir to hold our randomly selected
    // pixel placements
    var pool = [_]u32{0} ** (res_x / sections);
    for (pool) |_, i| {
        pool[i] = @intCast(u32, i);
    }
    // Setup Message boxes
    var msgs = [_]mbox.MessageCounts{.{}} ** sections;
    var msg_boxes = [_]mbox.MsgBuffer{.{ .msgs = undefined }} ** sections;
    for (msg_boxes) |*msg_box| {
        msg_box.msgs = try allocator.alloc(mbox.Msg, (fps * res_x) / sections);
    }
    defer {
        for (msg_boxes) |*msg_box| {
            allocator.free(msg_box.msgs);
        }
    }

    var steps = [_]u32{fps} ** sections;

    // State of
    var drain_step: u32 = 0;
    var sides: bool = true;
    var paused: bool = false;
    var fade_out: u8 = 0;
    var erase = false;
    var draining = false;

    var mode: i32 = 0;

    const modes = [_][]const u8{
        "Status",
        "JID",
        "Owner",
        "Department",
        "Sub-Department",
        "Unit",
        "Division",
        "User's Jobs",
    };

    while (!ray.WindowShouldClose()) {

        //////////////////////////////
        // BEGIN DRAW {
        //
        ray.BeginDrawing();
        ray.ClearBackground(ray.BLACK);
        ray.DrawTexture(world_tex, 0, 0, ray.WHITE);
        ray.BeginShaderMode(shader);
        ray.SetShaderValueTexture(shader, usr_tex_loc, usr_tex);
        ray.SetShaderValueTexture(shader, rnd_tex_loc, rnd_tex);
        ray.SetShaderValue(shader, mode_uni_loc, &mode, ray.SHADER_UNIFORM_INT);
        ray.SetShaderValue(shader, user_uni_loc, &uid, ray.SHADER_UNIFORM_INT);
        ray.DrawTextureTiled(
            tex,
            .{ .x = 0, .y = 0, .width = res_x, .height = res_y },
            .{ .x = 0, .y = 0, .width = win_x, .height = win_y },
            .{ .x = 0, .y = 0 },
            0.0,
            window_scale,
            ray.WHITE,
        );
        ray.EndShaderMode();

        if (fade_out > 0) {
            ray.DrawText(
                modes[@intCast(usize, mode)].ptr,
                10,
                20,
                36,
                ray.Fade(
                    .{ .r = 192, .g = 192, .b = 192, .a = 255 },
                    @intToFloat(f32, fade_out) / @intToFloat(f32, fade_duration),
                ),
            );
            fade_out -= 1;
        }
        //ray.DrawFPS(10, 10);
        ray.EndDrawing();

        //
        // END DRAW }
        //////////////////////////////

        for (ctxs) |*ctx, i| {
            var ctx_msgs = ctx.getMessages(&msg_boxes[i]);
            if (ctx_msgs) |msg| {
                msgs[i].add(msg);
                steps[i] = fps;
            }

            if (msg_boxes[i].size == 0 or steps[i] == 0) {
                continue;
            }

            defer steps[i] -= 1;

            var msg_pct = @intToFloat(f32, msg_boxes[i].size) / @intToFloat(f32, steps[i]);
            var spawn_count = @floatToInt(u32, msg_pct);
            if (@mod(msg_pct, 1.0) > rand.float(f32))
                spawn_count += 1;

            if (spawn_count == 0) continue;

            // every iteration shuffle the indicies
            shuffle(rand, pool[0..]);

            if (spawn_count > res_x / sections) {
                std.debug.print("Warning: total pixels, {}, more than buffer.\n", .{spawn_count});
                spawn_count = @minimum(spawn_count, res_x / sections - 1);
            }

            var pixel_offset = (i * res_x / sections);

            var j: usize = 0;
            while (j < spawn_count) : (j += 1) {
                var msg = msg_boxes[i].next() orelse break;
                var x = pool[j];
                pixels[x + pixel_offset] = encodeColor(rand, msg);
                //switch (msg.msg) {
                //    .active => pixels[x + pixel_offset] = ray.LIME,
                //    .done => pixels[x + pixel_offset] = ray.SKYBLUE,
                //    .err => pixels[x + pixel_offset] = ray.RED,
                //    .blocked => pixels[x + pixel_offset] = ray.ORANGE,
                //}
            }
        }

        var needs_draining = update(rand, sides, pixels[0..], erase);
        erase = false;
        sides = true;
        if (needs_draining) {
            drain_step = drain_steps;
        }

        if (!paused) {
            ray.UpdateTexture(tex, &pixels);
        }

        if (drain_step > 0) {
            drain_step -= 1;
            draining = true;
        }

        if (draining) {
            draining = false;
            sides = false;

            // Binned holes
            // var pix: u32 = 1;
            // while (pix < res_x) : (pix += 6) {
            //     pixels[(res_x*res_y)-pix] = ray.BLANK;
            //     pixels[(res_x*res_y)-(pix+1)] = ray.BLANK;
            //     pixels[(res_x*res_y)-(pix+2)] = ray.BLANK;
            // }

            // Randomized holes
            var pix: u32 = 0;
            while (pix < res_x) : (pix += 1) {
                var offset_start = (res_x * res_y - 1);
                if (rand.float(f32) > 0.5) {
                    var pixel_offset = offset_start - pix;
                    if (pixels[pixel_offset].r != 255 and
                        pixels[pixel_offset].g != 255 and
                        pixels[pixel_offset].b != 255 and
                        pixels[pixel_offset].a != 255)
                        pixels[pixel_offset] = ray.BLANK;
                }
            }
        }

        //////////////////////////////
        // BEGIN INTERACTIONS {
        //

        // Draw / erase pixels
        if (ray.IsMouseButtonDown(0)) {
            drawColor(pixels[0..], ray.WHITE);
        } else if (ray.IsMouseButtonDown(1)) {
            drawColor(pixels[0..], ray.BLANK);
        }

        // Debugging pause, still keeps running in background
        if (ray.IsKeyPressed(32)) paused = !paused;

        // Switch shader mode
        if (ray.IsKeyPressed(262)) {
            mode = @mod(mode + 1, 8);
            fade_out = fade_duration;
        }
        if (ray.IsKeyPressed(263)) {
            mode -= 1;
            if (mode < 0) mode = 8 + mode;
            fade_out = fade_duration;
        }

        // Erase any blockers
        if (ray.IsKeyPressed(67)) {
            erase = true;
        }

        if (ray.IsKeyDown(68)) {
            draining = true;
        }
        //
        // END INTERACTIONS }
        //////////////////////////////

        //std.debug.print("{}\n", .{ray.GetKeyPressed()});
    }
    // Clean up threads here.
}

test "pixel_update" {
    //std.debug.print("\n", .{});
    var prng = std.rand.DefaultPrng.init(42);
    const rand = prng.random();
    var pixels = [_]ray.Color{ray.BLANK} ** (res_x * res_y);
    pixels[res_x * (res_y - 2) + 5] = ray.WHITE;
    pixels[res_x * (res_y - 3) + 5] = ray.WHITE;
    pixels[res_x * (res_y - 4) + 5] = ray.WHITE;
    try std.testing.expect(pixels[res_x * (res_y - 2) + 5].a == 255);
    _ = update(rand, true, pixels[0..]);
    try std.testing.expect(pixels[res_x * (res_y - 3) + 5].a == 255);
    try std.testing.expect(pixels[res_x * (res_y - 2) + 5].a == 255);
    try std.testing.expect(pixels[res_x * (res_y - 1) + 5].a == 255);
    //std.debug.print("Second update\n", .{});
    _ = update(rand, true, pixels[0..]);
    try std.testing.expect(pixels[res_x * (res_y - 1) + 6].a == 255);
    try std.testing.expect(pixels[res_x * (res_y - 2) + 5].a == 255);
    try std.testing.expect(pixels[res_x * (res_y - 1) + 5].a == 255);
}

test "range reminder" {
    var foo = [_]u32{0} ** 10;
    for (foo[0..10]) |_| {}
}
