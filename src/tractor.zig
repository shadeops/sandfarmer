const std = @import("std");

const curl = @cImport(
    @cInclude("curl/curl.h"),
);

const MessageCounts = @import("mbox.zig").MessageCounts;

pub const Context = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    msgs: MessageCounts = .{},
    ready: bool = false,
    tsid: ?[36:0]u8 = null,
    url: []const u8,

    pub fn getMessages(self: *Self) ?MessageCounts {
        if (@atomicLoad(bool, &self.ready, .Acquire)) {
            var msgs = self.msgs;
            self.msgs.clear();
            @atomicStore(bool, &self.ready, false, .Release);
            return msgs;
        }
        return null;
    }

    pub fn startThread(self: *Self) !std.Thread {
        try self.tractorLogin();
        var thread = try std.Thread.spawn(.{}, callback, .{self});
        return thread;
    }

    fn callback(self: *Self) !void {
        while (true) {
            var new_msgs = (try self.queryTractor()) orelse continue;
            while (@atomicLoad(bool, &self.ready, .Acquire)) {}
            self.msgs.copy(new_msgs);
            @atomicStore(bool, &self.ready, true, .Release);

            std.time.sleep(1 * std.time.ns_per_s);
        }
        std.debug.print("thread done\n", .{});
    }

    fn tractorLogin(self: *Self) !void {
        //std.debug.print("Logging into Tractor\n", .{});
        var buf: [64:0]u8 = undefined;
        var post = try std.fmt.bufPrintZ(buf[0..], "q=login&user={s}", .{std.os.getenv("USER")});
        std.debug.print("post: {s}\n", .{post});
        var response = try postTractor(self.allocator, post, self.url);
        defer response.deinit();

        var p = std.json.Parser.init(self.allocator, false);
        defer p.deinit();

        var tree = try p.parse(response.items);
        defer tree.deinit();
        self.tsid = [_:0]u8{0} ** 36;
        for (tree.root.Object.get("tsid").?.String) |v, i| {
            self.tsid.?[i] = v;
        }
    }

    pub fn queryTractor(self: *Self) !?MessageCounts {
        var buf: [128:0]u8 = undefined;
        var post = try std.fmt.bufPrintZ(buf[0..], "q=subscribe&jids=0&tsid={s}", .{self.tsid.?});
        var response = try postTractor(self.allocator, post, self.url);
        defer response.deinit();
        //std.debug.print("\n\n{s}\n\n", .{response.items});
        return parseResponse(self.allocator, response);
    }
};

// From https://ziglang.org/learn/samples/#using-curl-from-zig
fn writeToArrayListCallback(
    data: *anyopaque,
    size: c_uint,
    nmemb: c_uint,
    user_data: *anyopaque,
) callconv(.C) c_uint {
    var buffer = @intToPtr(*std.ArrayList(u8), @ptrToInt(user_data));
    var typed_data = @intToPtr([*]u8, @ptrToInt(data));
    buffer.appendSlice(typed_data[0 .. nmemb * size]) catch return 0;
    return nmemb * size;
}

fn postTractor(
    allocator: std.mem.Allocator,
    post: []const u8,
    url: []const u8,
) !std.ArrayList(u8) {

    // global curl init, or fail
    if (curl.curl_global_init(curl.CURL_GLOBAL_ALL) != curl.CURLE_OK)
        return error.CURLGlobalInitFailed;
    defer curl.curl_global_cleanup();

    // curl easy handle init, or fail
    const handle = curl.curl_easy_init() orelse return error.CURLHandleInitFailed;
    defer curl.curl_easy_cleanup(handle);

    var response_buffer = std.ArrayList(u8).init(allocator);

    // superfluous when using an arena allocator, but
    // important if the allocator implementation changes
    errdefer response_buffer.deinit();

    // setup curl options
    if (curl.curl_easy_setopt(handle, curl.CURLOPT_URL, url.ptr) != curl.CURLE_OK)
        return error.CouldNotSetURL;

    if (curl.curl_easy_setopt(handle, curl.CURLOPT_POSTFIELDS, post.ptr) != curl.CURLE_OK)
        return error.CouldNotSetPost;

    // set write function callbacks
    if (curl.curl_easy_setopt(
        handle,
        curl.CURLOPT_WRITEFUNCTION,
        writeToArrayListCallback,
    ) != curl.CURLE_OK)
        return error.CouldNotSetWriteCallback;

    if (curl.curl_easy_setopt(
        handle,
        curl.CURLOPT_WRITEDATA,
        &response_buffer,
    ) != curl.CURLE_OK)
        return error.CouldNotSetWriteCallback;

    // perform
    if (curl.curl_easy_perform(handle) != curl.CURLE_OK)
        return error.FailedToPerformRequest;

    return response_buffer;
}

fn parseResponse(allocator: std.mem.Allocator, response: std.ArrayList(u8)) !?MessageCounts {
    var p = std.json.Parser.init(allocator, false);
    defer p.deinit();

    var tree = try p.parse(response.items);
    defer tree.deinit();

    var mbox = tree.root.Object.get("mbox") orelse return null;

    var msgs = MessageCounts{};

    for (mbox.Array.items) |item| {
        if (std.mem.eql(u8, item.Array.items[0].String, "c")) {
            if (std.mem.eql(u8, item.Array.items[4].String, "A")) msgs.active += 1;
            if (std.mem.eql(u8, item.Array.items[4].String, "B")) msgs.blocked += 1;
            if (std.mem.eql(u8, item.Array.items[4].String, "D")) msgs.done += 1;
            if (std.mem.eql(u8, item.Array.items[4].String, "E")) msgs.err += 1;
        }
    }

    return msgs;
}

//"mbox": [["c", 1203080001,14,13,"I",1,"hostname/11.22.00.33",9005,0,0,0,0, "dml", 1331263984.161]]
