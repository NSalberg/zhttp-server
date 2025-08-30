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

pub fn handleRequest(allocator: std.mem.Allocator, req: http.request.Request) anyerror!http.response.Response {
    var resp = http.response.Response{};
    const target = req.head.request_line.target;
    if (std.mem.eql(u8, target, "/yourproblem")) {
        resp.status = 400;
        // resp.body = try allocator.dupe(u8, "Your problem is not my problem\n");
        resp.body = bad_request;
    } else if (std.mem.eql(u8, target, "/myproblem")) {
        resp.status = 500;
        // resp.body = try allocator.dupe(u8, "Woopsie, my bad\n");
        resp.body = internal_error;
    } else if (std.mem.startsWith(u8, target, "/httpbin/")) {
        _ = std.mem.trim(u8, target, "/httpbin/");
        resp.body = ok;
    } else {
        // resp.body = try allocator.dupe(u8, "All good, frfr\n");
        resp.body = ok;
    }
    resp.content_type = html;
    // const body_len: u64 = resp.body.len;
    resp.content_length = try std.fmt.allocPrint(allocator, "{}", .{resp.body.len});
    return resp;
}

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const host_addr = try std.net.Address.parseIp4("127.0.0.1", 42069);

    var server = http_server.http.Server.init(arena.allocator(), http_server.http.Config{ .addr = host_addr }, &handleRequest);
    try server.serve();
}
