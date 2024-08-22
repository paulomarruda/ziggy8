const cpu = @import("cpu.zig");
const db = @import("debugger.zig");
const rl = @import("raylib");

pub const Emulator = struct {
    pub const SCREEN_WIDTH = 640;
    pub const SCREEN_HEIGHT = 320;
    pub const WINDOW_NAME = "Chip 8 Emulator";

    cpu: cpu.Chip8CPU,
    dbg: ?db.Debugger,

    pub fn init(filepath: [:0]const u8, debug: bool) !Emulator{
        const dbg = if (debug) db.Debugger.init() else null;
        var self = Emulator{.cpu = cpu.Chip8CPU.init(), .dbg = dbg};
        try self.cpu.loadRom(filepath);
        return self;
    }

    pub fn mainLoop(self: *Emulator) !void{
        rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, WINDOW_NAME);
        defer rl.closeWindow();
        rl.setTargetFPS(60);
        while (!rl.windowShouldClose()){
            const dbgp = if (self.dbg) |*dp| dp else null;
            try self.cpu.emulateCycle(dbgp);
            rl.beginDrawing();
            rl.clearBackground(rl.Color.black);
            for (0..cpu.Chip8Graphics.DCOLS) |x|{
                for (0..cpu.Chip8Graphics.DROWS) |y|{
                    if (self.cpu.graphics.pixelIsOn(x, y)){
                        const pos_x: i32 = @intCast(x * cpu.Chip8Graphics.RESIZE_RATE);
                        const pos_y: i32 = @intCast(y * cpu.Chip8Graphics.RESIZE_RATE);
                        const width: i32 = @intCast(cpu.Chip8Graphics.RESIZE_RATE);
                        const height: i32 = @intCast(cpu.Chip8Graphics.RESIZE_RATE);
                        rl.drawRectangle(
                            pos_x,
                            pos_y,
                            width,
                            height,
                            rl.Color.green
                        );
                    }
                }
            }
            defer rl.endDrawing();
        }
    }
};
