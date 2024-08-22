const std = @import("std");
const app = @import("emulator.zig");

pub fn main() !void{
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args_it = try std.process.argsWithAllocator(allocator);
    _ = args_it.skip();
    const filepath: [:0]const u8 = args_it.next()
        orelse @panic("No ROM passed.");
    var a = try app.Emulator.init(filepath, true);
    try a.mainLoop();
}
