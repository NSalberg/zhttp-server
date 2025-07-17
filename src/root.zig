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
    const socket = try posix.socket(host.any.family, posix.SOCK.STREAM, posix.IPPROTO.TCP);
    defer posix.close(socket);

    try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(socket, &host.any, host.getOsSockLen());
    try posix.listen(socket, 128);

    while (true) {
        var fd_p: net.Address = undefined;
        var cl_sock_len: posix.socklen_t = @sizeOf(net.Address);
        const new_sock = try posix.accept(socket, &fd_p.any, &cl_sock_len, 0);
        defer posix.close(new_sock);

        const read_buf: *[1024]u8 = undefined;
        try read(new_sock, read_buf);
        _ = try posix.write(new_sock, "Hello world");
    }
}

fn read(socket: posix.socket_t, read_buf: []u8) !void {
    const bytes_read = try posix.read(socket, read_buf);

    if (bytes_read == 0) {
        std.debug.print("no bytes read", .{});
    } else {
        std.debug.print("{s}", .{read_buf});
    }
}
// fn write(socket: posix.socket_t, msg: []const u8) !void {}
