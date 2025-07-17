//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const posix = std.posix;
const net = std.net;

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    // Buffering can improve performance significantly in print-heavy programs.
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

const host = std.net.Address{ .in = std.net.Ip4Address.init(.{ 127, 0, 0, 1 }, 8000) };

pub fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var server = try host.listen(.{ .reuse_address = true });
    defer server.deinit();

    const addr = server.listen_address;
    std.debug.print("Listening on {}, access this port to end the program\n", .{addr.getPort()});

    var client = try server.accept();
    defer client.stream.close();

    std.debug.print("Connection received! {} is sending data.\n", .{client.address});

    const message = try client.stream.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(message);
    std.debug.print("{s}", .{message});

    const writer = client.stream.writer();
    _ = try writer.write(message);
}

// fn write(socket: posix.socket_t, msg: []const u8) !void {}
