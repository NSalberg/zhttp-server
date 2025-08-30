const std = @import("std");
const map = @import("map.zig");
const assert = std.debug.assert;

///writing should be decoupled from the response?...
///state could be kept to ensure functions are called in the right order
pub const Response = struct {
    status: u16 = 200,
    content_length: ?[]const u8 = null,
    connection: []const u8 = "close",
    content_type: []const u8 = "test/plain",
    headers: ?map.CaseInsensitiveHashMap([]const u8) = null,
    trailers: ?map.CaseInsensitiveHashMap([]const u8) = null,
    body: []const u8 = &.{},

    pub fn writeStatusLine(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const status_enum: std.http.Status = @enumFromInt(self.status);
        try writer.print("HTTP/1.1 {d} {s}\r\n", .{ self.status, status_enum.phrase().? });
    }

    pub fn writeHeaders(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("Content-Length: {s}\r\n", .{self.content_length.?});
        try writer.print("Connection: {s}\r\n", .{self.connection});
        try writer.print("Content-Type: {s}\r\n", .{self.content_type});

        if (self.headers != null) {
            var header_it = self.headers.?.iterator();
            while (header_it.next()) |kv| {
                try writer.print("{s}: {s}\r\n", .{ kv.key_ptr.*, kv.value_ptr.* });
            }
        }
        try writer.writeAll("\r\n");
    }

    // writes chunked bytes from reader until an EOF is reached;
    pub fn writeChunked(writer: *std.Io.Writer, reader: *std.Io.Reader) !void {
        const chunk_len_digits = 8;
        const chunk_header_template = ("0" ** chunk_len_digits) ++ "\r\n";
        defer writer.writeAll("0\r\n\r\n");

        while (true) {
            const read_buffered = reader.buffered()[reader.seek..];
            if (read_buffered.len == 0) {
                try reader.fillMore() catch |err| if (err == std.Io.Reader.Error.EndOfStream) return;
            }

            const chunk_head_buf = writer.writableArray(chunk_header_template.len);
            @memcpy(chunk_head_buf, chunk_header_template);
            writeHex(chunk_head_buf[1..chunk_len_digits], read_buffered.len);
            writer.writeAll(read_buffered);
            reader.toss(read_buffered.len);
        }
    }

    // pub fn writeChunkedEnd(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
    //     //write trailers?
    //
    // }
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
