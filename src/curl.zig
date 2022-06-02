const std = @import("std");

const curl = @cImport(
    @cInclude("curl/curl.h"),
);

pub fn request(
    allocator: std.mem.Allocator,
    post: ?[]const u8,
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

    if (post != null) {
        if (curl.curl_easy_setopt(handle, curl.CURLOPT_POSTFIELDS, post.?.ptr) != curl.CURLE_OK)
            return error.CouldNotSetPost;
    }

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
