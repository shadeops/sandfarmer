const std = @import("std");
const tractor = @import("tractor.zig");

const ray = @cImport(
    @cInclude("raylib.h"),
);

const fps: i32 = 60;
const inv_fps: f32 = 1.0/@intToFloat(f32, fps);
const res_x: u32 = 640/2;
const res_y: u32 = 480/2;
const num_pixels = res_x * res_y;

fn update(rand: std.rand.Random, pixels: []ray.Color) bool {
    var i: usize = res_x*(res_y-1);
    var ret = false;
    while (i>0) {
        i -= 1;
        var row = @divFloor(i, res_x);
        var col = i % res_x;

        var below = i + res_x;
        var l_below = i + res_x - 1;
        var r_below = i + res_x + 1;
        //std.debug.print("{} {}\n", .{i, below});
        if (pixels[i].a == 0)
            continue;

        if (pixels[below].a == 0) {
            pixels[below] = pixels[i];
            pixels[i] = ray.BLANK;
            continue;
        }
        
        if (rand.float(f32) > 0.5) {
            if (col != 0 and pixels[l_below].a == 0) {
                pixels[l_below] = pixels[i];
                pixels[i] = ray.BLANK;
                continue;
            }
            if ((col != (res_x-1)) and pixels[r_below].a == 0) {
                pixels[r_below] = pixels[i];
                pixels[i] = ray.BLANK;
                continue;
            }
        } else {
            if ((col != (res_x-1)) and pixels[r_below].a == 0) {
                pixels[r_below] = pixels[i];
                pixels[i] = ray.BLANK;
                continue;
            }
            if (col != 0 and pixels[l_below].a == 0) {
                pixels[l_below] = pixels[i];
                pixels[i] = ray.BLANK;
                continue;
            }
        }
        if ( row < 20 ) {
            ret = true;
        }
    }
    return ret;
}

/// Alogrithm R
/// https://en.wikipedia.org/wiki/Reservoir_sampling#Simple_algorithm
fn reservoirSample(rand: std.rand.Random, s : []u32, r: []u32) void {
    for (r) |*r_ptr, i| {
        r_ptr.* = s[i];
    }

    for (s[r.len..]) |i| {
        var j = rand.intRangeAtMost(u32, 0, @intCast(u32,i));
        if (j < r.len)
            r[j] = s[i];
    }
}

/// Fisher Yates Shuffle (modern)
/// https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle#The_modern_algorithm
fn shuffle(rand: std.rand.Random, r: []u32)  void {
    var i = r.len - 1;
    while (i > 0) : (i-=1) {
        var j = rand.intRangeAtMost(u32, 0, @intCast(u32,i));
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

    var ctx = tractor.ThreadContext{};
    _ = try tractor.startGenerator(&ctx);

    var prng = std.rand.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.os.getrandom(std.mem.asBytes(&seed)) catch { break :blk 42; };
        break :blk 42;
    });
    const rand = prng.random();

    //ray.SetTraceLogLevel(ray.LOG_INFO);
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT); 
    ray.InitWindow(res_x*2, res_y*2, "sandfarm");
    defer ray.CloseWindow();

    ray.SetTargetFPS(fps);

    var img = ray.GenImageColor(res_x, res_y, ray.BLANK);
    defer ray.UnloadImage(img);
    var tex = ray.LoadTextureFromImage(img);
    defer ray.UnloadTexture(tex);
    ray.SetTextureFilter(tex, ray.TEXTURE_FILTER_POINT);
    ray.SetTextureWrap(tex, ray.TEXTURE_WRAP_CLAMP);

    var pixels = [_]ray.Color{ray.BLANK} ** (res_x*res_y);
    ray.UpdateTexture(tex, &pixels);

    //const pix_factor: f32 = 360.0/(@intToFloat(f32, num_pixels));

    var pool = [_]u32{0} ** res_x;
    var reservoir = [_]u32{0} ** res_x;
    for (pool) |_, i| {
        pool[i] = @intCast(u32, i);
        reservoir[i] = @intCast(u32, i);
    }

    var msgs = tractor.MessageCounts{};
    var steps: u32 = fps;

    var gamma_shader = ray.LoadShaderFromMemory(null, gamma_glsl);
    defer ray.UnloadShader(gamma_shader);

    var clear_steps: usize = 0;

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        ray.ClearBackground(ray.BLACK);
        ray.BeginShaderMode(gamma_shader);
            ray.DrawTextureTiled(
                tex,
                .{.x=0, .y=0, .width=res_x, .height=res_y},
                .{.x=0, .y=0, .width=res_x*2, .height=res_y*2},
                .{.x=0, .y=0},
                0.0,
                2.0,
                ray.WHITE,
            );
        ray.EndShaderMode();
        ray.DrawFPS(10,10);
        ray.EndDrawing();
        //for (pixels) |*pixel, i| {
        //    _ = i;
        //    pixel.* = ray.ColorFromHSV(@intToFloat(f32, i) * pix_factor, 1.0 ,1.0);
        //}
        
        var new_msgs = tractor.getMessages(&ctx);
        if (new_msgs) |msg| {
            msgs.add(msg);
            steps = fps;
        }

        if (msgs.hasMsgs() and steps > 0) {
            defer steps -= 1;

            var step_msgs = tractor.MessageCounts{};

            var msg_pct: f32 = undefined;
            if (msgs.active > 0) {
                msg_pct = @intToFloat(f32, msgs.active) / @intToFloat(f32, steps);
                step_msgs.active = @floatToInt(u32, msg_pct);
                if (@mod(msg_pct,1.0) > rand.float(f32))
                    step_msgs.active += 1;
            }
            
            if (msgs.blocked > 0) {
                msg_pct = @intToFloat(f32, msgs.blocked) / @intToFloat(f32, steps);
                step_msgs.blocked = @floatToInt(u32, msg_pct);
                if (@mod(msg_pct,1.0) > rand.float(f32))
                    step_msgs.blocked += 1;
            }
            
            if (msgs.err > 0) {
                msg_pct = @intToFloat(f32, msgs.err) / @intToFloat(f32, steps);
                step_msgs.err = @floatToInt(u32, msg_pct);
                if (@mod(msg_pct,1.0) > rand.float(f32))
                    step_msgs.err += 1;
            }
            
            if (msgs.done > 0) {
                msg_pct = @intToFloat(f32, msgs.done) / @intToFloat(f32, steps);
                step_msgs.done = @floatToInt(u32, msg_pct);
                if (@mod(msg_pct,1.0) > rand.float(f32))
                    step_msgs.done += 1;
            }

            var total = (step_msgs.active + step_msgs.err + step_msgs.done + step_msgs.blocked);

            if (total > 0) {

                reservoirSample(rand, pool[0..], reservoir[0..total]);
                shuffle(rand, reservoir[0..total]);

                var start: u32 = 0;
                for (reservoir[start .. step_msgs.err+start]) |x| {
                    pixels[x] = ray.RED;
                    //pixels[x] = ray.ColorFromHSV(0.0, rand.float(f32)*0.15 + 0.6, rand.float(f32)*0.45+0.35);
                }
                start += step_msgs.err;
                for (reservoir[start .. step_msgs.active+start]) |x| {
                    //pixels[x] = ray.LIME;
                    pixels[x] = ray.ColorFromHSV(125.0, rand.float(f32)*0.15 + 0.6, rand.float(f32)*0.45+0.35);
                }
                start += step_msgs.active;
                for (reservoir[start .. step_msgs.done+start]) |x| {
                    //pixels[x] = ray.SKYBLUE;
                    pixels[x] = ray.ColorFromHSV(215.0, rand.float(f32)*0.15 + 0.6, rand.float(f32)*0.45+0.35);
                }
                start += step_msgs.done;
                for (reservoir[start .. step_msgs.blocked+start]) |x| {
                    //pixels[x] = ray.ORANGE;
                    pixels[x] = ray.ColorFromHSV(50.0, rand.float(f32)*0.15 + 0.6, rand.float(f32)*0.45+0.35);
                }
                msgs.sub(step_msgs);
            }
        }
        
        var clear = update(rand, pixels[0..]);
        ray.UpdateTexture(tex, &pixels);

        if (clear) {
            clear_steps = 60;
        }
        if (clear_steps > 1) {
            clear_steps -= 1;
            var pix: u32 = 1;
            while (pix < res_x) : (pix += 6) {
                pixels[(res_x*res_y)-pix] = ray.BLANK;
                pixels[(res_x*res_y)-(pix+1)] = ray.BLANK;
                pixels[(res_x*res_y)-(pix+2)] = ray.BLANK;
            }
        }
        
        //if ( ray.IsMouseButtonPressed(0) ) {
        //    var x = @divFloor(ray.GetMouseX(), 2);
        //    var y = @divFloor(ray.GetMouseY(), 2);
        //    var offset = @intCast(usize, res_x*y + x);
        //    pixels[offset] = ray.RED;
        //}
        
    }

}
