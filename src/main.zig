const std = @import("std");
const http_server = @import("http_server");
const http = http_server.http;

const bad_request =
    \\<html>
    \\  <head>
    \\    <title>400 Bad Request</title>
    \\  </head>
    \\  <body>
    \\    <h1>Bad Request</h1>
    \\    <p>Your request honestly kinda sucked.</p>
    \\  </body>
    \\</html>
;

const internal_error =
    \\<html>
    \\  <head>
    \\    <title>500 Internal Server Error</title>
    \\  </head>
    \\  <body>
    \\    <h1>Internal Server Error</h1>
    \\    <p>Okay, you know what? This one is on me.</p>
    \\  </body>
    \\</html>
;
const ok =
    \\<html>
    \\  <head>
    \\    <title>200 OK</title>
    \\  </head>
    \\  <body>
    \\    <h1>Success!</h1>
    \\    <p>Your request was an absolute banger.</p>
    \\  </body>
    \\</html>
;

const html = "text/html";

// this doesn't need to be passed a response writer just a *Io.Writer, we can create the Response writer ourselves
pub fn handleRequest(allocator: std.mem.Allocator, r_writer: *http.response.ResponseWriter, req: http.request.Request) anyerror!void {
    const target = req.head.request_line.target;
    if (std.mem.eql(u8, target, "/yourproblem")) {
        const headers = http.response.Headers{
            .content_type = html,
            .content_length = try std.fmt.allocPrint(allocator, "{}", .{bad_request.len}),
        };
        const resp = http.response.Response{
            .status = 400,
            .headers = headers,
            .body = bad_request,
        };
        // try r_writer.writer.print("{f}", .{resp});
        try r_writer.writeResponse(resp);
    } else if (std.mem.eql(u8, target, "/myproblem")) {
        const headers = http.response.Headers{
            .content_type = html,
            .content_length = try std.fmt.allocPrint(allocator, "{}", .{internal_error.len}),
        };
        const resp = http.response.Response{
            .status = 500,
            .headers = headers,
            .body = internal_error,
        };
        // try r_writer.writer.print("{f}", .{resp});
        try r_writer.writeResponse(resp);
    } else if (std.mem.startsWith(u8, target, "/httpbin/")) {
        const location = std.mem.trim(u8, target, "/httpbin/");
        const url = try std.mem.concat(allocator, u8, &[_][]const u8{ "https://httpbin.org/", location });

        var client = std.http.Client{ .allocator = allocator };

        var reques = try client.request(.GET, try std.Uri.parse(url), .{});
        defer reques.deinit();
        try reques.sendBodiless();

        const redirect_buffer = try client.allocator.alloc(u8, 8 * 1024);
        defer client.allocator.free(redirect_buffer);

        var response = try reques.receiveHead(redirect_buffer);
        try r_writer.writeStatusLine(response.head.status);
        try r_writer.writeHeaders(http.response.Headers{});

        // TODO: better error handling here
        if (response.head.status != .ok) {
            return error.BAD;
        }

        var transfer_buffer: [64]u8 = undefined;
        const repsonse_reader = response.reader(&transfer_buffer);
        // use chunkwriter thing...
        // try r_writer.writeChunked(repsonse_reader);
        var sha = std.crypto.hash.sha2.Sha256.init(.{});

        var body_len: usize = 0;

        while (true) {
            const read_buffered = repsonse_reader.buffer[repsonse_reader.seek..repsonse_reader.end];

            if (read_buffered.len > 0) {
                @branchHint(.likely);
                sha.update(read_buffered);
                body_len += read_buffered.len;
                try r_writer.writeChunked(read_buffered);
                repsonse_reader.toss(read_buffered.len);
            }
            _ = repsonse_reader.fillMore() catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };
        }
        try r_writer.writeChunkedEnd();
        const final_sha = sha.finalResult();
        // const hex_str = try std.fmt.bufPrint(&final_sha, "{s}", .{std.fmt.bytesToHex(final_sha)});
        var trailers: [2]http.response.Trailer = .{
            http.response.Trailer{
                .name = "X-Content-SHA256",
                .value = try std.fmt.allocPrint(allocator, "{b64}", .{final_sha}),
            },
            http.response.Trailer{
                .name = "X-Content-Length",
                .value = try std.fmt.allocPrint(allocator, "{d}", .{body_len}),
            },
        };
        try r_writer.writeTrailers(&trailers);
    } else {
        const headers = http.response.Headers{
            .content_type = html,
            .content_length = try std.fmt.allocPrint(allocator, "{}", .{ok.len}),
        };
        const resp = http.response.Response{
            .status = 400,
            .headers = headers,
            .body = ok,
        };
        try r_writer.writeResponse(resp);
    }
}

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const host_addr = try std.net.Address.parseIp4("127.0.0.1", 42069);

    var server = http_server.http.Server.init(arena.allocator(), http_server.http.Config{ .addr = host_addr }, &handleRequest);
    try server.serve();
}
