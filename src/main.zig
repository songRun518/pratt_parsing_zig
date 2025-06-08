const std = @import("std");
const root = @import("root.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var input = std.ArrayList(u8).init(allocator);
    defer input.deinit();

    try std.io.getStdIn().reader()
        .readUntilDelimiterArrayList(
        &input,
        '\n',
        std.math.maxInt(usize),
    );
    _ = input.pop();

    const result = try root.pratt(allocator, input.items);
    std.debug.print("{d}", .{result});
}
