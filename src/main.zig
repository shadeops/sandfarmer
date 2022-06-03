const std = @import("std");
const randmsgs = @import("randmsgs.zig");

const users = @import("users.zig");
const tractor = @import("tractor.zig");

const mbox = @import("mbox.zig");

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

            if ((pixels[i].r & 0b1) == 0) continue;
            if (pixels[i].r == 255 and pixels[i].g == 255 and pixels[i].b == 255 and pixels[i].a == 255) continue;

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

const shader_glsl =
    \\#version 330
    \\
    \\// For reasons unclear we have to use a sampler2D instead of a isampler2D
    \\// to read the texture. Raylib stores this internally as a R8G8B8A8
    \\// and passes to OGL as 
    \\// *glInternalFormat = GL_RGBA8; *glFormat = GL_RGBA; *glType = GL_UNSIGNED_BYTE
    \\// so I'm not sure why we can't use an [iu]sampler2D to get the byte values directly.
    \\// for now we can get the floats and scale/round them.
    \\// ivec4 usr = ivec4(texelFetch(texture1, ivec2(1,0), 0));
    \\
    \\// Input vertex attributes (from vertex shader)
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\
    \\// Input uniform values
    \\uniform sampler2D texture0;
    \\
    \\// texture pixel
    \\//  r = (jid & (255<<8)) >> 8;
    \\//  g = (jid & 255);
    \\//  b = rand(0,256);
    \\//  a = (uid & ((1<<14)-1)) | state & (3)
    \\
    \\uniform sampler2D user_texture;
    \\uniform sampler2D rand_texture;
    \\uniform vec4 colDiffuse;
    \\
    \\uniform int mode;
    \\
    \\// Output fragment color
    \\out vec4 finalColor;
    \\
    \\vec3 hsv2rgb(vec3 c)
    \\{
    \\    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    \\    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    \\    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    \\}
    \\
    \\
    \\vec4 statusClr(int status, ivec2 scramble) {
    \\    if (status > 2) return vec4(0.9, 0.16, 0.22, 1.0);
    \\
    \\    vec4 rand = texelFetch(rand_texture, scramble, 0);
    \\    float v = (rand.r*0.15) + 0.6;
    \\    float s = (rand.g*0.45) + 0.35;
    \\    float h = 0.0;
    \\    if (status == 0) {
    \\      h = 0.35;
    \\    } else if (status == 1) {
    \\      h = 0.60;
    \\    } else if (status == 2) {
    \\       h += 0.14;
    \\    }
    \\
    \\    vec3 clr = hsv2rgb(vec3(h, v, s));
    \\    return vec4(clr, 1.0);
    \\}
    \\
    \\vec4 jidClr(int jid) {
    \\    int jid_x = jid % 128;
    \\    int jid_y = jid / 128;
    \\    vec4 clr = texelFetch(rand_texture, ivec2(jid_x, jid_y), 0);
    \\    clr.a = 1.0;
    \\    return clr;
    \\}
    \\vec4 ownerClr(int owner) {
    \\    int owner_x = owner % 128;
    \\    int owner_y = owner / 128;
    \\    vec4 clr = texelFetch(rand_texture, ivec2(owner_x, owner_y), 0);
    \\    clr.a = 1.0;
    \\    return clr;
    \\}
    \\vec4 deptClr(int owner, ivec2 scramble) {
    \\    ivec4 usr_limits = ivec4(round(texelFetch(user_texture, ivec2(127,127), 0)*255));
    \\    vec4 rand = texelFetch(rand_texture, scramble, 0);
    \\    int owner_x = owner % 128;
    \\    int owner_y = owner / 128;
    \\    ivec4 usr = ivec4(round(texelFetch(user_texture, ivec2(owner_x, owner_y), 0)*255));
    \\    float h = float(usr.r) / float(usr_limits.r);
    \\    float v = (rand.r*0.15) + 0.6;
    \\    float s = (rand.g*0.45) + 0.35;
    \\    vec3 clr = hsv2rgb(vec3(h, v, s));
    \\    return vec4(clr, 1.0);
    \\}
    \\vec4 divClr(int owner, ivec2 scramble) {
    \\    ivec4 usr_limits = ivec4(round(texelFetch(user_texture, ivec2(127,127), 0)*255));
    \\    vec4 rand = texelFetch(rand_texture, scramble, 0);
    \\    int owner_x = owner % 128;
    \\    int owner_y = owner / 128;
    \\    ivec4 usr = ivec4(round(texelFetch(user_texture, ivec2(owner_x, owner_y), 0)*255));
    \\    float h = float(usr.g) / float(usr_limits.g);
    \\    float v = (rand.r*0.15) + 0.6;
    \\    float s = (rand.g*0.45) + 0.35;
    \\    vec3 clr = hsv2rgb(vec3(h, v, s));
    \\    return vec4(clr, 1.0);
    \\}
    \\vec4 subClr(int owner, ivec2 scramble) {
    \\    ivec4 usr_limits = ivec4(round(texelFetch(user_texture, ivec2(127,127), 0)*255));
    \\    vec4 rand = texelFetch(rand_texture, scramble, 0);
    \\    int owner_x = owner % 128;
    \\    int owner_y = owner / 128;
    \\    ivec4 usr = ivec4(round(texelFetch(user_texture, ivec2(owner_x, owner_y), 0)*255));
    \\    float h = float(usr.b) / float(usr_limits.b);
    \\    float v = (rand.r*0.15) + 0.6;
    \\    float s = (rand.g*0.45) + 0.35;
    \\    vec3 clr = hsv2rgb(vec3(h, v, s));
    \\    return vec4(clr, 1.0);
    \\}
    \\vec4 unitClr(int owner, ivec2 scramble) {
    \\    ivec4 usr_limits = ivec4(round(texelFetch(user_texture, ivec2(127,127), 0)*255));
    \\    vec4 rand = texelFetch(rand_texture, scramble, 0);
    \\    int owner_x = owner % 128;
    \\    int owner_y = owner / 128;
    \\    ivec4 usr = ivec4(round(texelFetch(user_texture, ivec2(owner_x, owner_y), 0)*255));
    \\    float h = float(usr.a) / float(usr_limits.a);
    \\    float v = (rand.r*0.15) + 0.6;
    \\    float s = (rand.g*0.45) + 0.35;
    \\    vec3 clr = hsv2rgb(vec3(h, v, s));
    \\    return vec4(clr, 1.0);
    \\}
    \\
    \\void main()
    \\{
    \\    vec4 texelColor = texture(texture0, fragTexCoord);
    \\
    \\    ivec4 msg = ivec4(round(texelColor * 255));
    \\
    \\    int status = (int(msg.b) >> 6) & 255;
    \\
    \\    int active = int(msg.r) & 1;
    \\
    \\    // 0b0011_1111 = 63
    \\    int owner = msg.a | ((msg.b & 63) << 8);
    \\
    \\    // 0b0011_1110 = 62
    \\    int jid = msg.g | ((msg.r & 31) << 7);
    \\
    \\    ivec2 scramble = ivec2(msg.r ^ msg.g, msg.r ^ msg.b);
    \\    
    \\// modes:
    \\//  status
    \\//  jid
    \\//  usr
    \\//  dept
    \\//  div
    \\//  sub
    \\//  unit
    \\    if (mode==0) {
    \\        finalColor = statusClr(status, scramble);
    \\    } else if (mode == 1) {
    \\        finalColor = jidClr(jid);
    \\    } else if (mode == 2) {
    \\        finalColor = ownerClr(owner);
    \\    } else if (mode == 3) {
    \\        finalColor = deptClr(owner, scramble);
    \\    } else if (mode == 4) {
    \\        finalColor = divClr(owner, scramble);
    \\    } else if (mode == 5) {
    \\        finalColor = subClr(owner, scramble);
    \\    } else if (mode == 6) {
    \\        finalColor = unitClr(owner, scramble);
    \\    }
    \\    finalColor.a = 1.0;
    \\    finalColor = pow(finalColor, vec4(0.4545)) * active;
    \\    vec4 white = vec4(1.0);
    \\    if (texelColor == white) {
    \\      finalColor = vec4(0.7,0.7,0.7,1.0);
    \\    }
    \\}
;

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

fn drawColor(pixels: []ray.Color, clr: ray.Color) void {
    var x: i32 = ray.GetMouseX();
    var y: i32 = ray.GetMouseY();
    x = std.math.clamp(x, 0, res_x * window_scale);
    y = std.math.clamp(y, 0, res_y * window_scale);
    x = @divFloor(x, 3);
    y = @divFloor(y, 3);
    var offset = @minimum(@intCast(usize, res_x * @intCast(u32, y) + @intCast(u32, x)), res_x * res_y - 1);
    pixels[offset] = clr;
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
    var user_map = try users.queryUsers(allocator, "http://127.0.0.1:3001/whoswho");
    defer user_map.deinit();
    std.debug.print("{}\n", .{user_map.users[user_map.users.len - 1]});

    var uid_iter = user_map.uid_map.keyIterator();
    while (uid_iter.next()) |k| {
        std.debug.print("{s}\n", .{user_map.getKey(k.*)});
    }

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

    const urls = [_][]const u8{
        "http://127.0.0.1:3000/Tractor/monitor",
        "http://127.0.0.1:3001/Tractor/monitor",
        "http://127.0.0.1:3002/Tractor/monitor",
        "http://127.0.0.1:3003/Tractor/monitor",
    };

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
        _ = try ctx.startThread();
    }

    // TODO fix mbuffer leak

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

    var usr_tex_loc = ray.GetShaderLocation(shader, "user_texture");
    var rnd_tex_loc = ray.GetShaderLocation(shader, "rand_texture");
    var mode_uni_loc = ray.GetShaderLocation(shader, "mode");

    var tex_pixels: []ray.Color = undefined;

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
    var clear_steps: usize = 0;
    var sides: bool = true;
    var paused: bool = false;

    var mode: i32 = 0;

    while (!ray.WindowShouldClose()) {

        //////////////////////////////
        // BEGIN DRAW
        //
        ray.BeginDrawing();
        ray.ClearBackground(ray.BLACK);
        ray.BeginShaderMode(shader);
        ray.SetShaderValueTexture(shader, usr_tex_loc, usr_tex);
        ray.SetShaderValueTexture(shader, rnd_tex_loc, rnd_tex);
        ray.SetShaderValue(shader, mode_uni_loc, &mode, ray.SHADER_UNIFORM_INT);
        ray.DrawTextureTiled(
            tex,
            .{ .x = 0, .y = 0, .width = res_x, .height = res_y },
            .{ .x = 0, .y = 0, .width = res_x * window_scale, .height = res_y * window_scale },
            .{ .x = 0, .y = 0 },
            0.0,
            window_scale,
            ray.WHITE,
        );
        ray.EndShaderMode();

        ray.DrawFPS(10, 10);
        ray.EndDrawing();

        //
        // END DRAW
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

        if (ray.IsMouseButtonDown(0)) {
            drawColor(pixels[0..], ray.WHITE);
        } else if (ray.IsMouseButtonDown(1)) {
            drawColor(pixels[0..], ray.BLANK);
        }

        // Debugging pause, still keeps running in background
        if (ray.IsKeyPressed(32)) paused = !paused;
        if (ray.IsKeyPressed(262)) mode = @mod(mode + 1, 7);
        if (ray.IsKeyPressed(263)) {
            mode -= 1;
            if (mode < 0) mode = 7 + mode;
        }
        //std.debug.print("{}\n", .{ray.GetKeyPressed()});
        //std.debug.print("{}\n", .{mode});
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
