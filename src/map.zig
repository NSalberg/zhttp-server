const std = @import("std");

const CaseInsensitiveContext = struct {
    pub fn hash(self: @This(), key: []const u8) u64 {
        _ = self;
        var h = std.hash.Wyhash.init(0);
        for (key) |c| {
            const lower = .{std.ascii.toLower(c)};
            h.update(&lower);
        }
        return h.final();
    }

    pub fn eql(self: @This(), a: []const u8, b: []const u8) bool {
        _ = self;
        return std.ascii.eqlIgnoreCase(a, b);
    }
};

pub fn CaseInsensitiveHashMap(comptime V: type) type {
    return std.hash_map.HashMap([]const u8, V, CaseInsensitiveContext, std.hash_map.default_max_load_percentage);
}

test CaseInsensitiveHashMap {
    var map = CaseInsensitiveHashMap(u8).init(std.testing.allocator);
    defer map.deinit();
    try map.put("TesT", 1);
    try std.testing.expect(map.get("TesT") != null);
    try std.testing.expect(map.get("Test") != null);
}
