const std = @import("std");
const map = @import("map.zig");
const assert = std.debug.assert;

pub const Headers = struct {
    content_length: ?[]const u8 = null,
    connection: []const u8 = "close",
    content_type: []const u8 = "text/plain",
    headers: ?map.CaseInsensitiveHashMap([]const u8) = null,
};

pub const Trailer = struct {
    name: []const u8,
    value: []const u8,
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
    pub fn writeChunked(self: *ResponseWriter, buf: []const u8) !void {
        assert(self.state == .chunk_body);
        const chunk_len_digits = 8;
        const chunk_header_template = ("0" ** chunk_len_digits) ++ "\r\n";

        // std.debug.print("\nbuffered: {s}\n", .{read_buffered});
        const chunk_head_buf = try self.writer.writableArray(chunk_header_template.len);
        @memcpy(chunk_head_buf, chunk_header_template);
        writeHex(chunk_head_buf[1..chunk_len_digits], buf.len);

        try self.writer.writeAll(buf);
        try self.writer.writeAll("\r\n");
    }

    pub fn writeChunkedEnd(self: *ResponseWriter) !void {
        try self.writer.writeAll("0\r\n");
    }

    pub fn writeTrailers(self: *ResponseWriter, trailers: []Trailer) !void {
        for (trailers) |t| {
            try self.writer.print("{s}: {s}\r\n", .{ t.name, t.value });
        }

        try self.writer.writeAll("\r\n");
    }

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

    pub fn writeResponse(
        self: *ResponseWriter,
        response: Response,
    ) !void {
        try self.writeStatusLine(@enumFromInt(response.status));
        try self.writeHeaders(response.headers);
        if (response.body) |b| {
            try self.writer.writeAll(b);
        } else if (response.body_reader) |br| {
            while (true) {
                const buffered = br.buffered();
                if (buffered.len > 0) {
                    @branchHint(.likely);
                    try self.writeChunked(buffered);
                    br.toss(buffered.len);
                }
                _ = br.fillMore() catch |err| switch (err) {
                    error.EndOfStream => break,
                    else => |e| return e,
                };
            }
            try self.writeChunkedEnd();

            try self.writeTrailers(response.trailers);
        }
    }
};

///writing should be decoupled from the response?...
///state could be kept to ensure functions are called in the right order
///
pub const Response = struct {
    status: u16 = 200,
    headers: Headers,
    trailers: []Trailer = &.{},
    body_reader: ?*std.Io.Reader = null,
    body: ?[]const u8 = &.{},
};
