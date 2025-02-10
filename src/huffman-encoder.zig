const std = @import("std");
const Allocator = std.mem.Allocator;
const fmt = std.fmt;

const HuffmanEncoding = struct {
    map: HashMap,
    encoded_map: EncodeHashMap,
    p_queue: Queue,
    encoded_string: EncodedString,
    allocator: Allocator,

    const Node = struct {
        ch: ?u8,
        left: ?*Node,
        right: ?*Node,
        freq: i32,
    };

    const Self = @This();
    const HashMap = std.AutoHashMap(u8, i32);
    const EncodeHashMap = std.AutoArrayHashMap(u8, []u8);
    const EncodedString = std.ArrayList(u8);
    const Queue = std.PriorityQueue(*Node, void, _compare);

    fn _compare(_: void, a: *Node, b: *Node) std.math.Order {
        return std.math.order(a.freq, b.freq);
    }

    pub fn init(allocator: Allocator) Self {
        return .{
            .map = HashMap.init(allocator),
            .encoded_map = EncodeHashMap.init(allocator),
            .encoded_string = EncodedString.init(allocator),
            .p_queue = Queue.init(allocator, {}),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.p_queue.deinit();
        self.map.deinit();
        self.encoded_string.deinit();
        self._destroy_encoded_map();
    }

    fn _destroy_encoded_map(self: *Self) void {
        defer self.encoded_map.deinit();
        var iter = self.encoded_map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
    }

    pub fn encode(self: *Self, text: []const u8) ![]u8 {
        try self._buildTree(text);

        for (text) |character| {
            const code = self.encoded_map.get(character) orelse unreachable;
            try self.encoded_string.appendSlice(code);
        }

        return self.encoded_string.items;
    }

    fn _isLeaf(node: *Node) bool {
        if (node.left == null and node.right == null) {
            return true;
        }
        return false;
    }

    fn _concat(self: *Self, a: []const u8, b: []const u8) ![]u8 {
        const result = try self.allocator.alloc(u8, a.len + b.len);
        @memcpy(result[0..a.len], a);
        @memcpy(result[a.len..], b);
        return result;
    }

    fn _encode(self: *Self, node: ?*Node, s: *std.ArrayList(u8)) !void {
        const node_item = node orelse return;

        if (_isLeaf(node_item)) {
            if (node_item.ch) |character| {
                var code: []u8 = undefined;
                if (s.items.len > 0) {
                    code = try self.allocator.dupe(u8, s.items);
                } else {
                    const ptr = try self.allocator.alloc(u8, 1);
                    ptr[0] = '1';
                    code = ptr;
                }
                try self.encoded_map.put(character, code);
            }
        }

        try s.append('0');
        try self._encode(node_item.left, s);
        _ = s.pop();

        try s.append('1');
        try self._encode(node_item.right, s);
        _ = s.pop();
    }

    fn _buildTree(self: *Self, text: []const u8) !void {
        for (text) |char| {
            if (self.map.getPtr(char)) |value| {
                value.* += @intCast(1);
            } else {
                try self.map.put(char, 1);
            }
        }

        const num_chars = self.map.count();
        var node_pool = try std.ArrayList(Node).initCapacity(self.allocator, (2 * num_chars) - 1);
        defer node_pool.deinit();

        var iterator = self.map.iterator();

        while (iterator.next()) |entry| {
            const char = entry.key_ptr.*;
            const freq = entry.value_ptr.*;
            const node = try node_pool.addOne();
            node.* = .{ .ch = char, .freq = freq, .left = null, .right = null };

            try self.p_queue.add(node);
        }

        while (self.p_queue.count() > 1) {
            const left = self.p_queue.remove();
            const right = self.p_queue.remove();

            const new_freq = left.freq + right.freq;
            const intermidate_node = try node_pool.addOne();
            intermidate_node.* = .{
                .ch = null,
                .freq = new_freq,
                .left = left,
                .right = right,
            };

            try self.p_queue.add(intermidate_node);
        }
        const root = self.p_queue.remove();

        var buffer: [256]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        var bit_string = std.ArrayList(u8).init(fba.allocator());
        defer bit_string.deinit();
        try self._encode(root, &bit_string);
    }
};

const ArgsError = error{
    NoArgumentProvided,
};

test "testing_encoding" {
    const text: []const u8 = "abcaabbaaaccaaaa";
    var huffman_encoding = HuffmanEncoding.init(std.testing.allocator);
    defer huffman_encoding.deinit();
    const encoded_string = try huffman_encoding.encode(text);
    try std.testing.expectEqualStrings("1000111000011101011111", encoded_string);
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const outError = std.io.getStdErr().writer();
    var text: []const u8 = undefined;
    if (args.next()) |arg| {
        text = arg;
    } else {
        try outError.print("Please provide text for encoding", .{});
        return error.NoArgumentProvided;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const aa = arena.allocator();
    var huffman_encoding = HuffmanEncoding.init(aa);
    defer huffman_encoding.deinit();
    const encoded_string = try huffman_encoding.encode(text);
    const outw = std.io.getStdOut().writer();
    try outw.print("{s}\n", .{encoded_string});
}
