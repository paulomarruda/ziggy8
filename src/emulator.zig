// @file: emulator.zig
// @author: Paulo Arruda
// @license: MIT
// @brief: Implementation of Chip8's emulation routines with SDL for graphics.

const std = @import("std");
const core = @import("core.zig");
const dbg = @import("debugger.zig");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const EmulationError = error{
    SDL_INIT_FAILED,
    FAILED_TO_CREATE_SDL_WINDOW,
    FAILED_TO_CREATE_SLD_RENDERER,
    FAILED_TO_CREATE_SDL_TEXTURE,
};

pub const Emulator = struct {
    pub const SCREEN_WIDTH: usize = 640;
    pub const SCREEN_HEIGHT: usize = 320;
    pub const SCALE_FACTOR = 10;
    pub const WINDOW_NAME = "Z8: Chip8 emulator";

    is_open: bool,
    core: core.Chip8,
    debug: ?dbg.Debugger,
    window: ?*c.SDL_Window,
    renderer: ?*c.SDL_Renderer,
    texture: ?*c.SDL_Texture,

    pub fn init(debug: bool) EmulationError!Emulator{
        if (c.SDL_Init(c.SDL_INIT_EVERYTHING) != 0){
            return EmulationError.SDL_INIT_FAILED;
        }
        var self: Emulator = undefined;
        self.is_open = true;
        self.core = core.Chip8.init();
        self.debug = if (debug) dbg.Debugger.init() else null;
        self.window = c.SDL_CreateWindow(WINDOW_NAME, c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED, SCREEN_WIDTH, SCREEN_HEIGHT,
            c.SDL_WINDOW_OPENGL)
            orelse {
                c.SDL_Quit();
                return EmulationError.FAILED_TO_CREATE_SDL_WINDOW;
            };
        self.renderer = c.SDL_CreateRenderer(self.window, -1, 0)
            orelse {
                c.SDL_DestroyWindow(self.window);
                c.SDL_Quit();
                return EmulationError.FAILED_TO_CREATE_SLD_RENDERER;
            };
        self.texture = c.SDL_CreateTexture(self.renderer,
            c.SDL_PIXELFORMAT_RGBA8888,
            c.SDL_TEXTUREACCESS_STREAMING, 64, 32)
            orelse {
                c.SDL_DestroyWindow(self.window);
                c.SDL_DestroyRenderer(self.renderer);
                c.SDL_Quit();
                return EmulationError.FAILED_TO_CREATE_SDL_TEXTURE;
            };
        return self;
    }

    pub fn denit(self: *Emulator) void{
        c.SDL_DestroyWindow(self.window);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyTexture(self.texture);
        c.SDL_Quit();
    }

    pub fn emulate(self: *Emulator, german: bool, room_filepath: [:0]const u8) !void{
        const d = if (self.debug) |*db| db else null;
        try self.core.memory.loadRom(room_filepath);
        // MAIN EMULATION LOOP
        while (self.is_open){
            var event: c.SDL_Event = undefined;
            while (c.SDL_PollEvent(&event) != 0){
                self.execEvent(event, german);
            }
            _ = c.SDL_RenderClear(self.renderer);
            for (0..10) |_|{
                try self.core.emulate(d);
            }
            self.core.tickTimers();
            self.generateSprites();
            var dst = c.SDL_Rect{.x = 0, .y = 0, .w = SCREEN_WIDTH, .h = SCREEN_HEIGHT};
            _ = c.SDL_RenderCopy(self.renderer, self.texture, null, &dst);
            _ = c.SDL_RenderPresent(self.renderer);
            c.SDL_Delay(17);
        }
    }

    fn execEvent(self: *Emulator, event: c.SDL_Event, german: bool) void{
                switch (event.type) {
                    c.SDL_QUIT => {
                        self.is_open = false;
                    },
                    c.SDL_KEYDOWN => {
                        if (event.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE){
                            self.is_open = false;
                        }
                        const key = _getKey(event.key.keysym.scancode, german);
                        if (key) |k|{
                            self.core.loadKey(k, true);
                        }
                    },
                    c.SDL_KEYUP => {
                        const key = _getKey(event.key.keysym.scancode, german);
                        if (key) |k|{
                            self.core.loadKey(k, false);
                        }
                    },
                    else => {},
                }
    }

    fn generateSprites(self: *Emulator) void{
        var pixels: ?[*]u32 = null;
        var pitch: c_int = 0;
        _ = c.SDL_LockTexture(self.texture, null, @ptrCast(&pixels), &pitch);
        for (0..core.Ch8Graphics.DCOLS) |col|{
            for (0..core.Ch8Graphics.DROWS) |row|{
                pixels.?[row*core.Ch8Graphics.DCOLS + col] = if (self.core.graphics.isPixelActive(col, row))
                    0xFFFFFFFF else 0x000000FF;
            }
        }
        c.SDL_UnlockTexture(self.texture);
    }
};

fn _getKey(key: c_uint, german: bool) ?u4{
    return if (german) switch (key) {
        c.SDL_SCANCODE_1 => 0x1,
        c.SDL_SCANCODE_2 => 0x2,
        c.SDL_SCANCODE_3 => 0x3,
        c.SDL_SCANCODE_4 => 0x4,

        c.SDL_SCANCODE_Q => 0x5,
        c.SDL_SCANCODE_W => 0x6,
        c.SDL_SCANCODE_E => 0x7,
        c.SDL_SCANCODE_R => 0x8,

        c.SDL_SCANCODE_A => 0x9,
        c.SDL_SCANCODE_S => 0xA,
        c.SDL_SCANCODE_D => 0xB,
        c.SDL_SCANCODE_F => 0xC,

        c.SDL_SCANCODE_Z => 0xD,
        c.SDL_SCANCODE_X => 0x0,
        c.SDL_SCANCODE_C => 0xE,
        c.SDL_SCANCODE_V => 0xF,
        else => null,
    } else switch (key) {
        c.SDL_SCANCODE_1 => 0x1,
        c.SDL_SCANCODE_2 => 0x2,
        c.SDL_SCANCODE_3 => 0x3,
        c.SDL_SCANCODE_4 => 0x4,

        c.SDL_SCANCODE_Q => 0x5,
        c.SDL_SCANCODE_W => 0x6,
        c.SDL_SCANCODE_E => 0x7,
        c.SDL_SCANCODE_R => 0x8,

        c.SDL_SCANCODE_A => 0x9,
        c.SDL_SCANCODE_S => 0xA,
        c.SDL_SCANCODE_D => 0xB,
        c.SDL_SCANCODE_F => 0xC,

        c.SDL_SCANCODE_Z => 0xD,
        c.SDL_SCANCODE_X => 0x0,
        c.SDL_SCANCODE_C => 0xE,
        c.SDL_SCANCODE_V => 0xF,
        else => null,
    };
}
