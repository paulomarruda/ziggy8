const std = @import("std");
const rl = @import("raylib");
const cpu = @import("cpu.zig");

pub fn Chip8() type{
    return struct {
        const Self = @This();
        const screen_width: u16 = 640;
        const screen_heigth: u16 = 320;
        const drawing_scale: u8 = 10;
        const RL_KEYS = [_]rl.Key{
            rl.KEY_ONE,
            rl.KEY_TWO,
            rl.KEY_THREE,
            rl.KEY_FOUR,
            rl.KEY_Q,
            rl.KEY_W,
            rl.KEY_E,
            rl.KEY_R,
            rl.KEY_A,
            rl.KEY_S,
            rl.KEY_D,
            rl.KEY_F,
            rl.KEY_X,
            rl.KEY_C,
            rl.KEY_V,
            rl.KEY_B,
        };
        cpu: cpu.Chip8CPU(),

        pub fn init() Self{
            return Self{
                .cpu = cpu.Chip8CPU().init(),
            };
        }

        pub fn run(self: *Self) void{
            rl.InitWindow(screen_width, screen_heigth, "Chip8 Emulator");
            rl.InitAudioDevice();
            rl.SetTargetFPS(60.0);
            const beep: rl.Sound = rl.LoadSound("assets/beep.wav");
            defer rl.UnloadSound(beep);
            defer rl.CloseAudioDevice();
            defer rl.CloseWindow();
            const screen_center_x = rl.GetMonitorWidth() / 2;
            const screen_center_y = rl.GetMonitorHeight() / 2;
            rl.SetWindowPosition(screen_center_x, screen_center_y);
            while (!rl.WindowShouldClose()) |_|{
                self.updateInput();
                self.cpu.emulate();
                rl.BeginDrawing();
                rl.EndDrawing();
            }
        }

        fn updateInput(self: *Self) void{
            for (RL_KEYS, 0..) |key, index|{
                if (rl.IsKeyUp(key)){
                    self.cpu.keys[index] = 1;
                }else if (rl.IsKeyDown(key)){
                    self.cpu.keys[index] = 0;
                }
            }
        }
    };
}
