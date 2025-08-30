const std = @import("std");

test {
    std.testing.refAllDeclsRecursive(@This());
}

pub const HeadLoader = struct {
    state: State = .start,

    pub const State = enum {
        start,
        seen_r,
        seen_rn,
        seen_rnr,
        finished,
    };

    pub fn feed(self: *HeadLoader, data: []const u8) usize {
        var index: usize = 0;
        while (true) {
            switch (self.state) {
                .finished => return index,
                .start => {
                    switch (data.len - index) {
                        0 => return index,
                        1 => {
                            if (data[index] == '\r')
                                self.state = State.seen_r;
                            index += 1;
                            continue;
                        },
                        else => {
                            index = std.mem.indexOfPos(u8, data, index, "\r") orelse return data.len;
                            index += 1;
                            self.state = State.seen_r;
                            continue;
                        },
                    }
                },
                .seen_r => switch (data.len - index) {
                    0 => return index,
                    else => {
                        switch (data[index]) {
                            '\n' => self.state = .seen_rn,
                            '\r' => self.state = .seen_r,
                            else => self.state = .start,
                        }
                        index += 1;
                        continue;
                    },
                },
                .seen_rn => switch (data.len - index) {
                    0 => return index,
                    else => {
                        switch (data[index]) {
                            '\r' => self.state = .seen_rnr,
                            else => self.state = .start,
                        }
                        index += 1;
                        continue;
                    },
                },
                .seen_rnr => switch (data.len - index) {
                    0 => return index,
                    else => {
                        switch (data[index]) {
                            '\n' => {
                                self.state = .finished;
                                return index + 1;
                            },
                            '\r' => self.state = .seen_r,
                            else => self.state = .start,
                        }
                        index += 1;
                        continue;
                    },
                },
            }
            return index;
        }
    }
    test feed {
        const data = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\nHello";

        for (0..36) |i| {
            var p: HeadLoader = .{};
            try std.testing.expectEqual(i, p.feed(data[0..i]));
            try std.testing.expectEqual(35 - i, p.feed(data[i..]));
        }
    }
};
