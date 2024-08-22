const std = @import("std");
const testing = std.testing;
const cpu = @import("cpu.zig");
const utils = @import("utils.zig");

pub const Debugger = struct {
        // The hexadecimal string representation of an u8.
        //     0xXY  -> 4 characters long.
        pub const HexU8: type = [4]u8;
        // The hexadecimal string representation of an u16.
        //     0xXYZW  -> 6 characters long.
        pub const HexU16: type = [6]u8;
        // A stack level is one line in the string representation of the stack
        // | 0xL | 0xXYZW |\n -> 17 characters long.
        // If level is of type StackLevel, then:
        // level[2:5] is the hex repr of its index.
        // level[8:14] is the hey repr of its u16 address.
        pub const StackLevel: type = [17]u8;
        pub const StackRepr: type = [16]StackLevel;
        // Instructions string representations.
        I_0x00E0: [3]u8,
        I_0x00EE: [3]u8,
        // Edit i[3..]
        I_0x1NNN: [9]u8,
        // edit i[5..]
        I_0x2NNN: [11]u8,
        // edit X: i[5..8]
        // byte: i[11..]
        I_0x3XNN: [15]u8,
        // X: i[6..9]
        // byte: i[12..]
        I_0x4XKK: [16]u8,
        // x: i[5..8]
        // y: i[13..16]
        I_0x5XY0: [17]u8,
        // x: i[5..8]
        // byte: [11..]
        I_0x6XKK: [15]u8,
        // x: i[6..9]
        // kk: i[12..]
        I_0x7XKK: [16]u8,
        // x: i[5..8]
        // y: i[13..16]
        I_0x8XY0: [17]u8,
        // x: i[5..8]
        // y: i[13..16]
        I_0x8XY1: [17]u8,
        // x: i[5..8]
        // y: i[13..16]
        I_0x8XY2: [18]u8,
        // x: i[5..8]
        // y: i[13..16]
        I_0x8XY3: [18]u8,
        // x: i[5..8]
        // y: i[13..16]
        I_0x8XY4: [18]u8,
        // x: i[5..8]
        // y: i[13..16]
        I_0x8XY5: [18]u8,
        // x: i[5..8]
        // y: i[13..16]
        I_0x8XY6: [18]u8,
        // x: i[7..10]
        // y: i[14..17]
        I_0x8XY7: [19]u8,
        // x: i[5..8]
        // y: i[13..16]
        I_0x8XYE: [18]u8,
        // x: i[5..8]
        // y: i[13..16]
        I_0x9XY0: [18]u8,
        // addr: i[6..]
        I_0xANNN: [12]u8,
        // addr: i[7..]
        I_0xBNNN: [13]u8,
        // x: [6..9]
        // kk: [12..]
        I_0xCXKK: [16]u8,
        // x: i[6..9]
        // y: i[14..17]
        // n: i[20..]
        I_0xDXYN: [23]u8,
        // x: i[6..]
        I_0xEX9E: [10]u8,
        // x: i[7..]
        I_0xEXA1: [11]u8,
        // x: i[5..8]
        I_0xFX07: [13]u8,
        // x: i[5..8]
        I_0xFX0A: [14]u8,
        // x: i[9..12]
        I_0xFX15: [13]u8,
        // x: i[9..12]
        I_0xFX18: [13]u8,
        // x: i[9..12]
        I_0xFX1E: [13]u8,
        // x: i[8..11]
        I_0xFX29: [12]u8,
        // x: i[8..11]
        I_0xFX33: [12]u8,
        // x: i[10..13]
        I_0xFX55: [14]u8,
        // x: i[5..8]
        I_0xFX65: [14]u8,

        pc_repr: HexU16,
        ir_repr: HexU16,
        stack_repr: StackRepr,
        register_repr: [16]HexU16,
        last_instruction: []u8,

        pub fn init() Debugger{
            var self: Debugger = undefined;
            utils.u16Hex(cpu.Chip8Memory.MEM_ISTART, &self.pc_repr);
            self.I_0x00E0= "CLS".*;
            self.I_0x00EE= "RET".*;
            self.I_0x1NNN= "JP 0x0NNN".*;
            self.I_0x2NNN = "CALL 0x0NNN".*;
            self.I_0x3XNN = "SE V{0x0}, 0xBB".*;
            self.I_0x4XKK = "SNE V{0x0}, 0xBB".*;
            self.I_0x5XY0 = "SE V{0xX}, V{0xY}".*;
            self.I_0x6XKK = "LD V{0xX}, 0xBB".*;
            self.I_0x7XKK = "ADD V{0xX}, 0xBB".*;
            self.I_0x8XY0 = "LD V{0xX}, V{0xY}".*;
            self.I_0x8XY1 = "OR V{0xX}, V{0xY}".*;
            self.I_0x8XY2 = "AND V{0xX}, V{0xY}".*;
            self.I_0x8XY3 = "XOR V{0xX}, V{0xY}".*;
            self.I_0x8XY4 = "ADD V{0xX}, V{0xY}".*;
            self.I_0x8XY5 = "SUB V{0xX}, V{0xY}".*;
            self.I_0x8XY6 = "SHR V{0xX}, V{0xY}".*;
            self.I_0x8XY7 = "SUBN V{0xX}, V{0xY}".*;
            self.I_0x8XYE = "SHL V{0xX}, V{0xY}".*;
            self.I_0x9XY0 = "SNE V{0xX}, V{0xY}".*;
            self.I_0xANNN = "LD I, 0x0NNN".*;
            self.I_0xBNNN = "JP V0, 0x0NNN".*;
            self.I_0xCXKK = "RND V{0xX}, 0xBB".*;
            self.I_0xDXYN = "DRW V{0xX}, V{0xY}, 0xN".*;
            self.I_0xEX9E = "SKP V{0xX}".*;
            self.I_0xEXA1 = "SKNP V{0xX}".*;
            self.I_0xFX07 = "LD V{0xX}, DT".*;
            self.I_0xFX0A = "LD V{0xX}, KEY".*;
            self.I_0xFX15 = "LD DT, V{0xX}".*;
            self.I_0xFX18 = "LD ST, V{0xX}".*;
            self.I_0xFX1E = "ADD I, V{0xX}".*;
            self.I_0xFX29 = "LD F, V{0xX}".*;
            self.I_0xFX33 = "LD B, V{0xX}".*;
            self.I_0xFX55 = "LD [I], V{0xX}".*;
            self.I_0xFX65 = "LD V{0xX}, [I]".*;
            return self;
        }

        pub fn loadStack(self: *Debugger, index: usize, addr: u16) void{
            const x: u8 = @intCast(index);
            utils.byteHex(x, self.stack_repr[index][2..5]);
            utils.byteHex(addr, self.stack_repr[index][8..14]);
        }

        pub fn print(self: Debugger) void{
            std.log.debug("{s}", .{self.last_instruction});
        }
    };
