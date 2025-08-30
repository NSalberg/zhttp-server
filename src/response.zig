const std = @import("std");
const map = @import("map.zig");
const assert = std.debug.assert;

pub const Headers = struct {
    content_length: ?[]const u8 = null,
    connection: []const u8 = "close",
    content_type: []const u8 = "text/plain",
    headers: ?map.CaseInsensitiveHashMap([]const u8) = null,
};

pub const ResponseWriter = struct {
    writer: *std.Io.Writer,
    state: State = .status_line,

    pub const State = enum {
        status_line,
        headers,
        body,
        chunk_body,
        trailers,
        finished,
    };

    pub fn writeStatusLine(self: *ResponseWriter, status: std.http.Status) std.Io.Writer.Error!void {
        assert(self.state == .status_line);
        try self.writer.print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(status), status.phrase().? });
        self.state = .headers;
    }

    pub fn writeHeaders(self: *ResponseWriter, headers: Headers) std.Io.Writer.Error!void {
        assert(self.state == .headers);
        var next_state: State = undefined;

        if (headers.content_length) |cl| {
            try self.writer.print("Content-Length: {s}\r\n", .{cl});
            next_state = .body;
        } else {
            try self.writer.writeAll("Transfer-Encoding: chunked\r\n");
            next_state = .chunk_body;
        }

        try self.writer.print("Connection: {s}\r\n", .{headers.connection});
        try self.writer.print("Content-Type: {s}\r\n", .{headers.content_type});

        if (headers.headers != null) {
            var header_it = headers.headers.?.iterator();
            while (header_it.next()) |kv| {
                try self.writer.print("{s}: {s}\r\n", .{ kv.key_ptr.*, kv.value_ptr.* });
            }
        }
        try self.writer.writeAll("\r\n");
        self.state = next_state;
    }

    // writes chunked bytes from reader until an EOF is reached;
    pub fn writeChunked(self: *ResponseWriter, reader: *std.Io.Reader) !void {
        assert(self.state == .chunk_body);
        std.debug.print("\nbuffered: adfasdf \n", .{});
        const chunk_len_digits = 8;
        const chunk_header_template = ("0" ** chunk_len_digits) ++ "\r\n";

        while (true) {
            // _ = try reader.stream(self.writer);

            const read_buffered = reader.buffer[reader.seek..reader.end];

            // std.debug.print("\nbuffered: {s}\n", .{read_buffered});
            if (read_buffered.len > 0) {
                @branchHint(.likely);

                const chunk_head_buf = try self.writer.writableArray(chunk_header_template.len);
                @memcpy(chunk_head_buf, chunk_header_template);
                writeHex(chunk_head_buf[1..chunk_len_digits], read_buffered.len);

                try self.writer.writeAll(read_buffered);
                try self.writer.writeAll("\r\n");
                reader.toss(read_buffered.len);
            }

            _ = reader.fillMore() catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };
        }

        try self.writer.writeAll("0\r\n\r\n");
    }

    pub fn writeChunkedEnd(self: @This()) std.Io.Writer.Error!void {
        try self.writer.writeAll("0\r\n\r\n");
    }
    // pub fn writeTrailers(self: @This(), *std.Io.Writer){
    // }

    fn writeHex(buf: []u8, x: usize) void {
        assert(std.mem.allEqual(u8, buf, '0'));
        const base = 16;
        var index: usize = buf.len;
        var a = x;
        while (a > 0) {
            const digit = a % base;
            index -= 1;
            buf[index] = std.fmt.digitToChar(@intCast(digit), .lower);
            a /= base;
        }
    }

    ///if content-lenght is null this will writeChunked
    /// this is is bad... need a reader for chunked?
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try self.writeStatusLine(writer);
        try self.writeHeaders(writer);
        try writer.writeAll(self.body);
    }
};

///writing should be decoupled from the response?...
///state could be kept to ensure functions are called in the right order
pub const Response = struct {
    status: u16 = 200,
    headers: Headers,
    trailers: ?map.CaseInsensitiveHashMap([]const u8) = null,
    body_reader: ?*std.Io.Reader = null,
    body: []const u8 = &.{},
};
