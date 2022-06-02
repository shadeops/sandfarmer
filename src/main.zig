const std = @import("std");
const randmsgs = @import("randmsgs.zig");

const users = @import("users.zig");
const tractor = @import("tractor.zig");

const MessageCounts = @import("mbox.zig").MessageCounts;

const ray = @cImport(
    @cInclude("raylib.h"),
);

const fps: i32 = 60;
const res_x: u32 = 320;
const res_y: u32 = 240;
const window_scale: u32 = 3;
const sections: u32 = 4;

const debug = false;

fn update(rand: std.rand.Random, sides: bool, pixels: []ray.Color) bool {
    var ret = false;
    _ = sides;
    var row: u32 = res_y - 1;
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

            if (pixels[i].a == 0) continue;

            var below = i + res_x;
            if (pixels[below].a == 0) {
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
                if (col != 0 and pixels[l_below].a == 0) {
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
                if (col != res_x - 1 and pixels[r_below].a == 0) {
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
                if ((col != res_x - 1) and pixels[r_below].a == 0) {
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
                if (col != 0 and pixels[l_below].a == 0) {
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

const shader_glsl =
    \\#version 330
    \\
    \\// Input vertex attributes (from vertex shader)
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\
    \\// Input uniform values
    \\uniform sampler2D texture0;
    \\uniform sampler2D texture1;
    \\uniform vec4 colDiffuse;
    \\
    \\// Output fragment color
    \\out vec4 finalColor;
    \\
    \\void main()
    \\{
    \\    // Texel color fetching from texture sampler
    \\    vec4 texelColor = texture(texture0, fragTexCoord);
    \\    
    \\    // For reasons unclear we have to use a sampler2D instead of a isampler2D
    \\    // to read the texture. Raylib stores this internally as a R8G8B8A8
    \\    // and passes to OGL as 
    \\    // *glInternalFormat = GL_RGBA8; *glFormat = GL_RGBA; *glType = GL_UNSIGNED_BYTE
    \\    // so I'm not sure why we can't use an i/usampler2D to get the byte values directly.
    \\    // for now we can get the floats and scale/round them.
    \\    ivec4 usr = ivec4(round(texelFetch(texture1, ivec2(127,127), 0)*255));
    \\    // this does not work per note above.
    \\    // ivec4 usr = ivec4(texelFetch(texture1, ivec2(1,0), 0));
    \\
    \\    // Calculate final fragment color
    \\    //finalColor = pow(texelColor, vec4(0.4545));
    \\    finalColor.r = (usr.r == 3) ? 0.5 : 0.0;
    \\    finalColor.g = 0.0;
    \\    finalColor.b = 0.0;
    \\    finalColor.a = 1.0;
    \\}
;

pub fn main() anyerror!void {
    //var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    //defer arena.deinit();
    var arena = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = arena.deinit();
        if (leaked) std.debug.print("Leaked\n", .{});
    }
    var allocator = arena.allocator();
    var user_map = try users.queryUsers(allocator, "http://127.0.0.1:3001/whoswho");
    defer user_map.deinit();
    std.debug.print("{}\n", .{user_map.users[user_map.users.len - 1]});
    
    var uid_iter = user_map.uid_map.keyIterator();
    while (uid_iter.next()) |k| {
        std.debug.print("{s}\n", .{user_map.getKey(k.*)});
    }

    //var umap = try allocator.alloc(ray.Color, 128*128);
    //for (umap) |*p,i| {
    //    p.* = .{.dept=5, .sub=10, .unit=15, .div=20};
    //    if (i<6)
    //        std.debug.print("{}\n", .{p});
    //}

    var arena0 = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena0.deinit();
    var arena1 = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena1.deinit();
    var arena2 = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena2.deinit();
    var arena3 = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena3.deinit();

    var allocator0 = arena0.allocator();
    var allocator1 = arena1.allocator();
    var allocator2 = arena2.allocator();
    var allocator3 = arena3.allocator();

    // Start data gathering
    //var ctxs = [_]randmsgs.Context{.{}} ** sections;
    //for (ctxs) |*ctx, i| {
    //    ctx.prng = std.rand.DefaultPrng.init(i).random();
    //    _ = try ctx.startThread();
    //}
    //ctxs[0].size = 1;
    //ctxs[1].size = 10;
    //ctxs[2].size = 20;
    //ctxs[3].size = 50;

    var ctxs = [_]tractor.Context{undefined} ** sections;
    ctxs[0] = tractor.Context{
        .allocator = allocator0,
        .url = "http://127.0.0.1:3000/Tractor/monitor",
    };
    ctxs[1] = tractor.Context{
        .allocator = allocator1,
        .url = "http://127.0.0.1:3001/Tractor/monitor",
    };
    ctxs[2] = tractor.Context{
        .allocator = allocator2,
        .url = "http://127.0.0.1:3002/Tractor/monitor",
    };
    ctxs[3] = tractor.Context{
        .allocator = allocator3,
        .url = "http://127.0.0.1:3003/Tractor/monitor",
    };
    for (ctxs) |*ctx| {
        _ = try ctx.startThread();
    }

    //"http://tractor/Tractor/monitor"

    // Seed the random number generator
    var prng = std.rand.DefaultPrng.init(42);
    const rand = prng.random();

    ray.SetTraceLogLevel(ray.LOG_DEBUG);
    //ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT);
    ray.InitWindow(res_x * window_scale, res_y * window_scale, "sandfarm");
    ray.SetWindowState(ray.FLAG_WINDOW_ALWAYS_RUN);

    ray.SetTargetFPS(fps);

    // Get shader to apply a gamma correction to the texture
    var shader = ray.LoadShaderFromMemory(null, shader_glsl);
    defer ray.UnloadShader(shader);
    
    var usr_tex_loc = ray.GetShaderLocation(shader, "texture1");

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
    std.debug.print("{}\n", .{usr_tex.format});

    // Set canvas to be blank by default
    var pixels = [_]ray.Color{ray.BLANK} ** (res_x * res_y);
    ray.UpdateTexture(tex, &pixels);

    // Setup a pool and reservoir to hold our randomly selected
    // pixel placements
    var pool = [_]u32{0} ** (res_x / sections);
    for (pool) |_, i| {
        pool[i] = @intCast(u32, i);
    }
    var reservoir = [_]u32{0} ** (res_x / sections);

    // Setup Message boxes
    var msgs = [_]MessageCounts{.{}} ** sections;
    var steps = [_]u32{fps} ** sections;

    // State of
    var clear_steps: usize = 0;
    var sides: bool = true;
    var paused: bool = false;

    while (!ray.WindowShouldClose()) {

        //////////////////////////////
        // BEGIN DRAW
        //
        ray.BeginDrawing();
            ray.ClearBackground(ray.BLACK);
            ray.BeginShaderMode(shader);
                ray.SetShaderValueTexture(shader, usr_tex_loc, usr_tex);
                ray.DrawTextureTiled(
                    tex,
                    .{ .x = 0, .y = 0, .width = res_x, .height = res_y },
                    .{ .x = 0, .y = 0, .width = res_x * window_scale, .height = res_y * window_scale },
                    .{ .x = 0, .y = 0 },
                    0.0,
                    window_scale,
                    ray.WHITE,
                );
                ray.DrawTextureTiled(
                    usr_tex,
                    .{ .x = 0, .y = 0, .width = 128, .height = 128},
                    .{ .x = 0, .y = 0, .width = 512, .height = 512},
                    .{ .x = 0, .y = 0 },
                    0.0,
                    4.0,
                    ray.WHITE,
                );
            ray.EndShaderMode();
            
            ray.DrawFPS(10, 10);
        ray.EndDrawing();
        
        //
        // END DRAW
        //////////////////////////////
        

        for (ctxs) |*ctx, i| {
            var ctx_msgs = ctx.getMessages();
            if (ctx_msgs) |msg| {
                msgs[i].add(msg);
                steps[i] = fps;
            }

            if (msgs[i].hasMsgs() and steps[i] > 0) {
                defer steps[i] -= 1;

                var step_msgs = MessageCounts{};

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
                if (total > res_x / sections) {
                    std.debug.print("Warning: total pixels, {}, more than buffer.\n", .{total});
                    // Here we will cull any points that didn't fit in the current step.
                    // The total msgs[i] will still contain the non-culled points since the
                    // resultanting step_msg is subtracted msgs[i], see * reference_note_1

                    // NOTES:
                    // * A better approach is to remove by a weighted average so higher values
                    // are removed more frequently
                    // * An even better approach is to not cause an overage in the first place
                    // though in practice that seems a rare occurance.
                    // * Another option is to move the step buffering into the threaded msg getters
                    // this would free the main thread up from having to figure out what to do.
                    var overage: u32 = total - (res_x / sections);
                    while (overage > 0) {
                        overage -= 1;
                        switch (overage % 4) {
                            0 => step_msgs.active -= 1,
                            1 => step_msgs.done -= 1,
                            2 => step_msgs.err -= 1,
                            3 => step_msgs.blocked -= 1,
                            else => unreachable,
                        }
                    }
                    total = @minimum(total, res_x / sections - 1);
                }

                if (total > 0) {
                    reservoirSample(rand, pool[0..], reservoir[0..total]);
                    shuffle(rand, reservoir[0..total]);

                    var pixel_offset = (i * res_x / sections);

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
                    // * reference_note_1
                    msgs[i].sub(step_msgs);
                }
            }
        }

        var clear = update(rand, sides, pixels[0..]);
        if (!paused) {
            ray.UpdateTexture(tex, &pixels);
        }

        if (clear) {
            clear_steps = 360;
            sides = false;
        }

        if (clear_steps > 0) {
            clear_steps -= 1;
            if (clear_steps == 0) sides = true;

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
                    pixels[offset_start - pix] = ray.BLANK;
                }
            }
        }

        //if ( ray.IsMouseButtonPressed(0) ) {
        //    var x = @divFloor(ray.GetMouseX(), 2);
        //    var y = @divFloor(ray.GetMouseY(), 2);
        //    var offset = @intCast(usize, res_x*y + x);
        //    pixels[offset] = ray.RED;
        //}

        // Debugging pause, still keeps running in background
        if (ray.IsKeyPressed(32)) paused = !paused;
    }
    // Clean up threads here.
}

test "pixel_update" {
    std.debug.print("\n", .{});
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
    std.debug.print("Second update\n", .{});
    _ = update(rand, true, pixels[0..]);
    try std.testing.expect(pixels[res_x * (res_y - 1) + 6].a == 255);
    try std.testing.expect(pixels[res_x * (res_y - 2) + 5].a == 255);
    try std.testing.expect(pixels[res_x * (res_y - 1) + 5].a == 255);
}

test "range reminder" {
    var foo = [_]u32{0} ** 10;
    for (foo[0..10]) |_| {}
}
