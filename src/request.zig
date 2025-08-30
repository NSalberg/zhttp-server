const std = @import("std");
const Io = std.Io;

const hparser = @import("headparser.zig");
const map = @import("map.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}

pub const Method = enum {
    GET,
    HEAD,
    POST,
    PUT,
    DELETE,
    CONNECT,
    OPTIONS,
    TRACE,
    PATCH,
};

pub const Version = enum {
    @"HTTP/1.0",
    @"HTTP/1.1",
};
const RequestLine = struct {
    method: Method,
    version: Version,
    target: []const u8,

    pub const RequestLineError = error{
        UnknownHttpMethod,
        /// This should probably be raised to the implementation of the server
        UnsupportedHttpVersion,
        InvalidRequestLine,
    };

    pub fn parse(line: []const u8) RequestLineError!RequestLine {
        if (std.mem.count(u8, line, " ") != 2) return error.InvalidRequestLine;

        var it = std.mem.splitSequence(u8, line, " ");
        const method_string = it.first();

        for (method_string) |c| {
            if (std.ascii.isUpper(c) != true)
                return error.InvalidRequestLine;
        }

        const method = std.meta.stringToEnum(Method, method_string) orelse
            return error.UnknownHttpMethod;

        const target = it.next().?;
        for (target) |c| {
            if (std.ascii.isAscii(c) != true)
                return error.InvalidRequestLine;
        }

        const version_string = it.next().?;

        if (version_string.len != 8)
            return error.InvalidRequestLine;

        const version = std.meta.stringToEnum(Version, version_string) orelse
            return error.UnsupportedHttpVersion;

        if (version == Version.@"HTTP/1.0")
            return error.UnsupportedHttpVersion;

        return RequestLine{ .method = method, .target = target, .version = version };
    }
};

pub const Head = struct {
    request_line: RequestLine,
    headers: map.CaseInsensitiveHashMap([]const u8),

    fn parseHeaders(allocator: std.mem.Allocator, it: *std.mem.SplitIterator(u8, std.mem.DelimiterType.sequence)) !map.CaseInsensitiveHashMap([]const u8) {
        var headers = map.CaseInsensitiveHashMap([]const u8).init(allocator);
        while (it.next()) |line| {
            if (line.len == 0) {
                break;
            }
            var line_it = std.mem.splitScalar(u8, line, ':');
            const header_name = try allocator.dupe(u8, line_it.first());
            errdefer allocator.free(header_name);

            for (header_name[0..]) |c| {
                if (std.ascii.isAscii(c) != true)
                    return error.HttpHeadersInvalid;
            }

            if (header_name.len == 0)
                return error.HttpHeadersInvalid;
            // this could be vectorized?
            if (std.mem.containsAtLeast(u8, header_name, 1, " ") or std.mem.containsAtLeast(u8, header_name, 1, "\t"))
                return error.HttpHeadersInvalid;

            const header_value = std.mem.trim(u8, line_it.rest(), " \t");

            var new_value: []const u8 = undefined;
            if (headers.getEntry(header_name)) |entry| {
                allocator.free(header_name);

                const old_value = entry.value_ptr.*;
                new_value = try std.mem.concat(allocator, u8, &[_][]const u8{ old_value, ", ", header_value });

                allocator.free(old_value);
                entry.value_ptr.* = new_value;
                // std.debug.print("dadfadf {s} {x} {x}\n", .{ entry.value_ptr.*, new_value, old_value });
                // std.debug.print("oldvalue {x}\n", .{old_value});

                // allocator.free(cur_entry.value_ptr.*);
            } else {
                new_value = try allocator.dupe(u8, header_value);
                try headers.put(header_name, new_value);
            }
        }
        return headers;
    }

    /// Parse the Header Buffer
    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !Head {
        var it = std.mem.splitSequence(u8, bytes, "\r\n");
        const request_line = try RequestLine.parse(it.first());

        return Head{ .request_line = request_line, .headers = try parseHeaders(allocator, &it) };
    }

    pub fn clean(self: *Head) void {
        var header_it = self.headers.iterator();
        while (header_it.next()) |kv| {
            self.headers.allocator.free(kv.value_ptr.*);
            self.headers.allocator.free(kv.key_ptr.*);
        }

        defer self.headers.deinit();
    }

    pub fn format(self: Head, w: *Io.Writer) Io.Writer.Error!void {
        const request_line = self.request_line;
        try w.print(
            \\Request line:
            \\ - Method: {t}
            \\ - Target: {s}
            \\ - Version: {t}
            \\Headers:
            \\
        , .{
            request_line.method,
            request_line.target,
            request_line.version,
        });

        var header_it = self.headers.iterator();
        while (header_it.next()) |kv| {
            try w.print(
                \\ - {s}: {s}
                \\
            , .{
                kv.key_ptr.*,
                kv.value_ptr.*,
            });
        }
    }
};

pub const parseError = Io.Reader.Error || RequestLine.RequestLineError;

pub const Request = struct {
    head: Head,
    body: []u8,
    pub fn deinit(self: *Request, allocator: std.mem.Allocator) void {
        self.head.clean();
        allocator.free(self.body);
    }
};

pub const ReqParser = struct {
    state: State,
    allocator: std.mem.Allocator,
    content_length: ?usize = null,
    pub const State = enum {
        start,
        reading_head,
        reading_body,
        finished,
    };

    pub fn init(allocator: std.mem.Allocator) ReqParser {
        return .{ .allocator = allocator, .state = .start };
    }

    pub fn parse(self: *ReqParser, reader: *Io.Reader) !Request {
        var request: Request = undefined;
        errdefer request.head.clean();
        while (true) {
            switch (self.state) {
                .start => {
                    self.state = .reading_head;
                    continue;
                },
                .reading_head => {
                    const head = try self.recieveHead(reader);
                    request = .{ .head = head, .body = "" };
                    const content_length_string = request.head.headers.get("content-length");
                    if (content_length_string != null) {
                        self.content_length = try std.fmt.parseInt(usize, content_length_string.?, 10);
                        self.state = .reading_body;
                    } else {
                        self.state = .finished;
                    }
                    continue;
                },
                .reading_body => {
                    request.body = try self.recieveBody(reader);
                    self.state = .finished;
                },
                .finished => {
                    break;
                },
            }
        }

        return request;
    }
    fn recieveHead(self: *ReqParser, reader: *Io.Reader) !Head {
        var bytes_read: usize = 0;
        var hp = hparser.HeadLoader{};
        while (true) {
            const cur_buf = reader.buffered()[bytes_read..];

            if (cur_buf.len == 0) {
                try reader.fillMore();
                continue;
            }
            bytes_read += hp.feed(cur_buf);

            if (hp.state == .finished) {
                const head = try Head.parse(
                    self.allocator,
                    reader.buffered()[0..bytes_read],
                );
                reader.toss(bytes_read);
                return head;
            }
        }
    }

    fn recieveBody(self: *ReqParser, reader: *Io.Reader) ![]u8 {
        var body = try self.allocator.alloc(u8, self.content_length.?);
        errdefer self.allocator.free(body);
        var num_bytes_read: usize = 0;

        while (true) {
            const num_buffered = reader.bufferedLen();
            if (num_buffered == 0) {
                reader.fillMore() catch |err| switch (err) {
                    error.ReadFailed => {
                        return error.ReadFailed;
                    },
                    error.EndOfStream => {
                        return error.HttpBodyTooShort;
                    },
                };
                continue;
            }

            if (num_bytes_read + num_buffered > self.content_length.?) {
                return error.HttpBodyTooLong;
            }

            std.mem.copyForwards(u8, body[num_bytes_read .. num_bytes_read + num_buffered], try reader.take(num_buffered));
            num_bytes_read += num_buffered;
            if (num_bytes_read == self.content_length) {
                break;
            }
        }
        return body;
    }

    test recieveBody {
        const req_string = "POST /submit HTTP/1.1\r\n" ++
            "Host: localhost:42069\r\n" ++
            "Content-Length: 13\r\n" ++
            "\r\n" ++
            "hello world!\n";
        var reader = std.Io.Reader.fixed(req_string);
        try reader.fill(13);
        const allocator = std.testing.allocator;
        var parser = ReqParser.init(allocator);
        var req = try parser.parse(&reader);
        defer req.deinit(allocator);
        try std.testing.expectEqualSlices(u8, "hello world!\n", req.body);
    }

    test "Body Too Small" {
        const req_string = "POST /submit HTTP/1.1\r\n" ++
            "Host: localhost:42069\r\n" ++
            "Content-Length: 13\r\n" ++
            "\r\n" ++
            "hello wod!\n";
        var reader = std.Io.Reader.fixed(req_string);
        const allocator = std.testing.allocator;
        var parser = ReqParser.init(allocator);
        const req = parser.parse(&reader);
        try std.testing.expectError(error.HttpBodyTooShort, req);
    }
};

test "Good GET Request line" {
    const req = "GET / HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nSet-Person: lane-loves-go\r\nSet-Person: prime-loves-zig\r\nSet-Person: tj-loves-ocaml\r\nAccept: */*\r\n\r\n";
    var r = try Head.parse(std.testing.allocator, req);
    defer r.clean();

    try std.testing.expectEqual(Method.GET, r.request_line.method);
    try std.testing.expectEqualSlices(u8, "/", r.request_line.target);
    try std.testing.expectEqual(Version.@"HTTP/1.1", r.request_line.version);
    try std.testing.expectEqualSlices(u8, "lane-loves-go, prime-loves-zig, tj-loves-ocaml", r.headers.get("set-person").?);
}

test "Good GET Request line with path" {
    const req = "GET /coffee HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n";

    var r = try Head.parse(std.testing.allocator, req);
    defer r.clean();

    try std.testing.expectEqual(Method.GET, r.request_line.method);
    try std.testing.expectEqualSlices(u8, "/coffee", r.request_line.target);
    try std.testing.expectEqual(Version.@"HTTP/1.1", r.request_line.version);
}

test "Good POST Request line" {
    const req = "POST / HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n";

    var r = try Head.parse(std.testing.allocator, req);
    defer r.clean();

    try std.testing.expectEqual(Method.POST, r.request_line.method);
    try std.testing.expectEqualSlices(u8, "/", r.request_line.target);
    try std.testing.expectEqual(Version.@"HTTP/1.1", r.request_line.version);
    try std.testing.expect(r.headers.get("host") != null);
}

test "Invalid number of parts in request line" {
    const req = "/coffee HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n";

    const r = Head.parse(std.testing.allocator, req);
    try std.testing.expectError(RequestLine.RequestLineError.InvalidRequestLine, r);
}

test "Invalid method (out of order) in request line" {
    const req = "/coffee GET HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n";

    const r = Head.parse(std.testing.allocator, req);
    try std.testing.expectError(RequestLine.RequestLineError.InvalidRequestLine, r);
}

test "Invalid Version in Head Line" {
    const req = "GET / HTTP/1.0\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n";

    const r = Head.parse(std.testing.allocator, req);
    try std.testing.expectError(RequestLine.RequestLineError.UnsupportedHttpVersion, r);
}

test "Invalid Header" {
    const req = "GET / HTTP/1.1\r\nHost : localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n";

    const r = Head.parse(std.testing.allocator, req);
    try std.testing.expectEqual(error.HttpHeadersInvalid, r);
}

// test "fmt" {
//     var reader = std.Io.Reader.fixed("GET / HTTP/1.1\r\nHost: localhost:42069\r\nUser-Agent: curl/7.81.0\r\nAccept: */*\r\n\r\n");
//
//     const r = try Request.parse(&reader);
//     std.debug.print("{f}", .{r});
// }
