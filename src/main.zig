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
    "http://127.0.0.1:3000/Tractor/monitor?min=30&max=200",
    "http://127.0.0.1:3001/Tractor/monitor?min=20&max=100",
    "http://127.0.0.1:3002/Tractor/monitor?min=10&max=50",
    "http://127.0.0.1:3003/Tractor/monitor?min=20&max=100",
};

const user_url = "http://127.0.0.1:3001/whoswho";
const log_level = ray.LOG_ERROR;
const fps: i32 = 60;
const res_x: u32 = 320;
const res_y: u32 = 240;
const window_scale: u32 = 3;
const win_x: u32 = res_x * window_scale;
const win_y: u32 = res_y * window_scale;
const sections: u32 = 4;
const fade_duration: u8 = 120;
const drain_steps: u32 = 360;
const barrier_height: u32 = 200;
const height_limit: u32 = 10;

const stone = ray.Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

const debug = false;

const PixelState = enum {
    empty,
    msg,
    stone,
};

const Grid = struct {
    const Self = @This();
    pixels: []ray.Color,
    state: []PixelState,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) !Grid {
        var grid = Grid{
            .pixels = try allocator.alloc(ray.Color, res_x * res_y),
            .state = try allocator.alloc(PixelState, res_x * res_y),
            .allocator = allocator,
        };
        for (grid.pixels) |*pixel| {
            pixel.* = ray.BLANK;
        }
        for (grid.state) |*pixel| {
            pixel.* = .empty;
        }
        return grid;
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.pixels);
        self.allocator.free(self.state);
        self.pixels = undefined;
        self.state = undefined;
    }

    fn move(self: Self, src: u32, dest: u32) void {
        self.pixels[dest] = self.pixels[src];
        self.state[dest] = self.state[src];
        self.erase(src);
    }

    fn erase(self: Self, offset: u32) void {
        self.pixels[offset] = ray.BLANK;
        self.state[offset] = .empty;
    }
};

fn update(rand: std.rand.Random, sides: bool, grid: Grid, erase: bool) bool {
    var is_full = false;
    var row: u32 = res_y;

    var col_order = [_]u32{0} ** res_x;
    for (col_order) |*col, i| {
        col.* = @intCast(u32, i);
    }

    var random_col = rand.boolean();
    while (row > 0) {
        row -= 1;
        var x: u32 = 0; // counter
        var i: u32 = 0; // pixel index
        var col: u32 = 0;

        // 50% time randomly pick positions to break up artifacts
        var decreasing_row = rand.boolean();

        if (random_col)
            shuffle(rand, col_order[0..]);

        while (x < res_x) : (x += 1) {
            if (random_col) {
                col = col_order[x];
            } else {
                col = if (decreasing_row) (res_x - x) - 1 else x;
            }

            i = row * res_x + col;

            if (grid.state[i] == .stone) {
                // If triggered erase any stones
                if (erase) grid.erase(i);
                continue;
            }

            if (row == res_y - 1) continue;
            if (grid.state[i] != .msg) continue;

            var below = i + res_x;
            if (grid.state[below] == .empty) {
                if (debug) std.debug.print("Moving {} below to {}\n", .{ i, below });
                grid.move(i, below);
                continue;
            }

            var a_below = i + res_x - 1;
            var b_below = i + res_x + 1;
            var a_side: u32 = 0;
            var b_side: u32 = res_x - 1;

            if (rand.boolean()) {
                // check right first
                a_below = i + res_x + 1;
                b_below = i + res_x - 1;
                a_side = res_x - 1;
                b_side = 0;
            }

            // Check to the a side
            if (!sides and col == a_side) {
                grid.erase(i);
                continue;
            }
            if (col != a_side and grid.state[a_below] == .empty) {
                grid.move(i, a_below);
                continue;
            }
            // Check the b (other) side
            if (!sides and col == b_side) {
                grid.erase(i);
                continue;
            }
            if (col != b_side and grid.state[b_below] == .empty) {
                grid.move(i, b_below);
                continue;
            }

            if (row < height_limit) {
                is_full = true;
            }
        }
    }
    return is_full;
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
    // jid 256-8192
    // 0b00111110
    clr.r = @intCast(u8, ((msg.jid >> 8) & 0b0001_1111) << 1);
    // rand
    // 0b11000000
    clr.r |= (rand.intRangeAtMost(u8, 0, 3) << 6);
    // active
    // 0b00000001
    clr.r |= 0b1;

    // jid 0-255
    clr.g = @intCast(u8, msg.jid & 0b1111_1111);

    // user 256-16384
    // 0b00111111
    clr.b = @intCast(u8, (msg.owner >> 8) & 0b0011_1111);
    // msg type
    // 0b11000000
    //  0b00000000 active
    //  0b01000000 done
    //  0b10000000 blocked 
    //  0b11000000 err 
    clr.b |= (@intCast(u8, @enumToInt(msg.msg)) << 6);

    // user 0-255
    clr.a = @intCast(u8, msg.owner & 0b1111_1111);

    // Stone == {0,0,0,255} (inactive but with alpha)
    return clr;
}

fn drawPixel(
    grid: Grid,
    clr: ray.Color,
    state: PixelState,
    x: i32,
    y: i32,
) void {
    if (x < 0 or y < 0 or x >= res_x or y >= res_y) return;
    var offset = @minimum(
        @intCast(usize, res_x * @intCast(u32, y) + @intCast(u32, x)),
        res_x * res_y - 1,
    );
    grid.pixels[offset] = clr;
    grid.state[offset] = state;
}

fn drawColor(
    grid: Grid,
    clr: ray.Color,
    state: PixelState,
) void {
    var x: i32 = ray.GetMouseX();
    var y: i32 = ray.GetMouseY();
    if (x < 0 or y < 0 or x >= win_x or y >= win_y) return;
    x = @divFloor(x, window_scale);
    y = @divFloor(y, window_scale);
    drawPixel(grid, clr, state, x, y);
    drawPixel(grid, clr, state, x + 1, y);
    drawPixel(grid, clr, state, x - 1, y);
    drawPixel(grid, clr, state, x, y + 1);
    drawPixel(grid, clr, state, x, y - 1);
}

fn createSectionBarriers(grid: Grid) void {
    if (sections < 2) return;
    var section_gap = res_x / sections;
    var x: usize = section_gap;
    while (x < res_x) : (x += section_gap) {
        var y: usize = res_y - barrier_height;
        while (y < res_y) : (y += 1) {
            var pixel_offset = res_x * y + x - 1;
            grid.pixels[pixel_offset] = stone;
            grid.state[pixel_offset] = .stone;
        }
    }
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked) std.debug.print("Leaked\n", .{});
    }
    var allocator = gpa.allocator();
    var user_map = users.queryUsers(allocator, user_url) catch {
        std.log.err("Unable to connect to user database.", .{});
        return;
    };
    defer user_map.deinit();

    var ctxs = [_]tractor.Context{undefined} ** sections;
    for (ctxs) |*ctx, i| {
        var ctx_allocator = std.heap.page_allocator;
        ctx.* = .{
            .allocator = ctx_allocator,
            .url = urls[i],
            .usermap = &user_map,
            .msgs = .{
                .msgs = try ctx_allocator.alloc(mbox.Msg, (fps * res_x) / sections),
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

    ray.SetTraceLogLevel(log_level);
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

    var grid = try Grid.init(allocator);
    defer grid.deinit();

    ray.UpdateTexture(tex, grid.pixels.ptr);

    // Setup a pool and reservoir to hold our randomly selected
    // pixel placements
    var pool = [_]u32{0} ** (res_x / sections);
    for (pool) |_, i| {
        pool[i] = @intCast(u32, i);
    }
    // Setup Message boxes
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

            // Most of the time this will be null
            if (ctx.getMessages(&msg_boxes[i]))
                steps[i] = fps;

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
                grid.pixels[x + pixel_offset] = encodeColor(rand, msg);
                grid.state[x + pixel_offset] = .msg;
            }
        }

        var needs_draining = update(rand, sides, grid, erase);
        erase = false;
        sides = true;
        if (needs_draining) {
            drain_step = drain_steps;
        }

        if (!paused) {
            ray.UpdateTexture(tex, grid.pixels.ptr);
        }

        if (drain_step > 0) {
            drain_step -= 1;
            draining = true;
        }

        if (draining) {
            draining = false;
            sides = false;

            // Randomized holes
            var pix: u32 = 0;
            while (pix < res_x) : (pix += 1) {
                var offset_start = (res_x * res_y - 1);
                if (rand.boolean()) {
                    var pixel_offset = offset_start - pix;
                    if (grid.state[pixel_offset] == .msg)
                        grid.erase(pixel_offset);
                }
            }
        }

        //////////////////////////////
        // BEGIN INTERACTIONS {
        //

        // Draw / erase pixels
        if (ray.IsMouseButtonDown(0)) {
            drawColor(grid, stone, .stone);
        } else if (ray.IsMouseButtonDown(1)) {
            drawColor(grid, ray.BLANK, .empty);
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

        if (ray.IsKeyPressed(83)) {
            createSectionBarriers(grid);
        }

        if (ray.IsKeyDown(68)) {
            draining = true;
        }
        //
        // END INTERACTIONS }
        //////////////////////////////

        //std.debug.print("{}\n", .{ray.GetKeyPressed()});
    }
}

test "range reminder" {
    var foo = [_]u32{0} ** 10;
    for (foo[0..10]) |_| {}
}
