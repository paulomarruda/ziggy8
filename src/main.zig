const std = @import("std");
const app = @import("emulator.zig");
const chip8_cpu = @import("cpu.zig");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub fn main() !void{
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var args_it = try std.process.argsWithAllocator(allocator);
    _ = args_it.skip();
    const filepath = args_it.next() orelse "";
    var emu = try app.Emulator.init(true);
    defer emu.denit();
    try emu.emulate(true, filepath);
}
