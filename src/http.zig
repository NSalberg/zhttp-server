const std = @import("std");
const net = std.net;
const posix = std.posix;
pub const request = @import("request.zig");

// const response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 12\r\n\r\nHello World!";
pub const response = @import("response.zig");
const map = @import("map.zig");

pub const Config = struct {
    addr: std.net.Address,
};

pub const HandlerFunc = *const fn (allocator: std.mem.Allocator, r_writer: *response.ResponseWriter, r: request.Request) anyerror!void;

pub const Server = struct {
    addr: std.net.Address,
    allocator: std.mem.Allocator,
    handler: HandlerFunc,
    pub fn init(allocator: std.mem.Allocator, config: Config, handler: HandlerFunc) Server {
        return Server{ .addr = config.addr, .allocator = allocator, .handler = handler };
    }

    // pub fn deinit(self: *Server) void {
    //     _ = self;
    // }
    pub fn handle(self: *Server, connection: std.net.Server.Connection) !void {
        var read_buf = std.mem.zeroes([1024]u8);
        var client_reader = connection.stream.reader(&read_buf);

        var write_buf = std.mem.zeroes([1024]u8);
        var client_writer = connection.stream.writer(&write_buf);

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const alloc = arena.allocator();
        var parser = request.ReqParser.init(alloc);

        var req = try parser.parse(&client_reader.file_reader.interface);
        defer req.deinit(alloc);

        std.debug.print("Head :\n{f}", .{req.head});
        std.debug.print("Body :\n{s}\n", .{req.body});
        var response_writer = response.ResponseWriter{ .writer = &client_writer.interface };
        const resp = try self.handler(self.allocator, &response_writer, req);
        _ = resp;

        // try client_writer.interface.print("{f}", .{resp});

        // //write the response
        // // Maybe response should be an object with a format function?
        // try resp.writeStatusLine(&client_writer.interface);
        // var headers = map.CaseInsensitiveHashMap([]const u8).init(arena.allocator());
        //
        // //convert content length to string
        // const max_len = 20;
        // var buf: [max_len]u8 = undefined;
        // const content_length = try std.fmt.bufPrint(&buf, "{d}", .{0});
        //
        // try response.getDefaultHeaders(&headers, content_length);
        // try response.writeHeaders(&client_writer.interface, &headers);

        try client_writer.interface.flush();
    }

    pub fn serve(self: *Server) !void {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        const listener = try posix.socket(self.addr.any.family, posix.SOCK.STREAM, posix.IPPROTO.TCP);

        defer posix.close(listener);
        var s = try self.addr.listen(net.Address.ListenOptions{ .reuse_address = true });
        defer s.deinit();

        while (true) {
            var conn = try s.accept();
            defer {
                conn.stream.close();
                std.debug.print("Connection closed: {f}\n", .{conn.address});
            }

            std.debug.print("Client Accepted: {f}\n", .{conn.address});
            try self.handle(conn);
        }

        try stdout.flush();
    }
    pub fn stop(self: *Server) void {
        _ = self;
    }
};
