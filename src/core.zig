// @file core.zig
// @author Paulo Arruda
// @license MIT
// @brief Implementation of Chip8's instructions and their executions.

const std = @import("std");
const testing = std.testing;
const math = std.math;
const utils = @import("utils.zig");
const db = @import("debugger.zig");


pub const CPUError = error{
    InvalidOpcode,
    FileNotFound,
};

pub const StackError = error{
    INVALID_ADDRESS,
    EMPTY_STACK,
    STACK_OVERFLOW,
};

pub const MemoryError = error{
    OUT_OF_MEMORY,
    MEMORY_INDEX_OUT_OF_BOUNDS,
};

pub const Opcode = packed struct(u16){
    // The opcode consists of a 16-bit uint
    //         0x X Y W Z
    //            | | | |_ least significan quarter
    //            | | |___ info quarter 1
    //            | |_____ info quarter 2
    //            |_______ most significant quarter
    lsq: u4,
    iq1: u4,
    iq2: u4,
    msq: u4,

    pub fn init(code: u16) Opcode{
        return @bitCast(code);
    }

    // The address consists of a 12-bit unsigned integer retrieved from the
    // opcode as follows
    //
    //         0x X N N N
    //             |_____|
    //                |___ address
    //
    pub fn fetchAddr(self: Opcode) u16{
        return @as(u16, self.iq2) << 8 | @as(u16, self.iq1) << 4 | @as(u16, self.lsq); 
    }

    // The byte consists of a 8.bit unsigned integer retrieved from the
    // opcode as follows
    //
    //         0x X Y K K
    //               |___|
    //                 |__ byte
    //
    pub fn fetchByte(self: Opcode) u8{
        return @as(u8, self.iq1) << 4 | @as(u8, self.lsq);
    }
};

pub const Ch8Graphics = struct {
    pub const DROWS: usize = 32;
    pub const DCOLS: usize = 64;
    pub const DSIZE: usize = DROWS * DCOLS;
    pub const Sprite = []const u8;
    buffer: [DSIZE]u1,

    pub fn cls(self: *Ch8Graphics) void{
        @memset(&self.buffer, 0);
    }

    pub fn init() Ch8Graphics{
        var self: Ch8Graphics = undefined;
        @memset(&self.buffer, 0);
        return self;
    }

    pub fn getPixelPtr(self: *Ch8Graphics, pos_x: usize, pos_y: usize) *u1{
        const x: usize = pos_x & 63;
        const y: usize = pos_y & 31;
        return &self.buffer[y*DCOLS + x];
    }

    pub fn isPixelActive(self: *Ch8Graphics, pos_x: usize, pos_y: usize) bool{
        return if (self.getPixelPtr(pos_x, pos_y).* == 1) true else false;
    }

    pub fn draw(self: *Ch8Graphics, vx: usize, vy: usize, sprite: Sprite, v0xF: *u8) void{
        for (sprite, 0..) |byte, row|{
            for (0..8) |col|{
                const pos_y = vy + row;
                const pos_x = vx + col;
                const pixel_ptr = self.getPixelPtr(pos_x, pos_y);
                const bit: u1 = @truncate((byte >> @truncate(7-col)) & 0x1);
                pixel_ptr.* ^= bit;
                if (bit == 1 and pixel_ptr.* == 0){
                    v0xF.* = 1;
                }
            }
        }
    }
};

pub const Ch8Memory = struct {
    pub const MEM_SIZE: usize = 4096;
    pub const FONT_MEM_START: usize = 0x050;
    pub const FONT_MEM_END: usize = 0x0A0;
    pub const MEM_PROGRAM_START: usize = 0x0200;
    pub const MEM_END: usize = 0x0FFF;
    pub const Sprite = [] const u8;

    buffer: [MEM_SIZE]u8,

    pub fn init() Ch8Memory{
        const FONT_SET = [_]u8{
            0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
            0x20, 0x60, 0x20, 0x20, 0x70, // 1
            0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
            0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
            0x90, 0x90, 0xF0, 0x10, 0x10, // 4
            0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
            0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
            0xF0, 0x10, 0x20, 0x40, 0x40, // 7
            0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
            0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
            0xF0, 0x90, 0xF0, 0x90, 0x90, // A
            0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
            0xF0, 0x80, 0x80, 0x80, 0xF0, // C
            0xE0, 0x90, 0x90, 0x90, 0xE0, // D
            0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
            0xF0, 0x80, 0xF0, 0x80, 0x80, // F
        };
        var self: Ch8Memory = undefined;
        @memset(&self.buffer, 0);
        @memcpy(self.buffer[FONT_MEM_START..FONT_MEM_END], &FONT_SET);
        return self;
    }

    pub fn ldByte(self: *Ch8Memory, byte: u8, index: usize) MemoryError!void{
        if (!isMemAdrrValid(index)){
            return MemoryError.MEMORY_INDEX_OUT_OF_BOUNDS;
        }
        self.buffer[index] = byte;
    }

    pub fn getByte(self: Ch8Memory, index: usize) MemoryError!u8{
        if (!isMemAdrrValid(index)){
            return MemoryError.MEMORY_INDEX_OUT_OF_BOUNDS;
        }
        return self.buffer[index];
    }

    pub fn isMemAdrrValid(index: usize) bool{
        return if (index >= MEM_PROGRAM_START and index <= MEM_END) true else false;
    }

    pub fn loadRom(self: *Ch8Memory, filepath: [:0]const u8) !void{
        var file = std.fs.cwd().openFile(filepath, .{})
            catch |err| return err;
        defer file.close();
        const size = file.getEndPos()
            catch |err| return err;
        var reader = file.reader();
        for (0..size) |i|{
            const byte = reader.readByte()
                catch |err| return err;
            self.buffer[MEM_PROGRAM_START + i] =  byte; 
        }
    }

    pub fn getOpcode(self: Ch8Memory, pc: usize) Opcode{
        var code: u16 = self.buffer[pc];
        code <<= 8;
        code |= @as(u16, self.buffer[pc + 1]);
        return Opcode.init(code);
    }

    pub fn getSprite(self: Ch8Memory, ir: usize, nibble: usize) Sprite{
        return self.buffer[ir .. ir + nibble];
    }
};

pub const Chip8 = struct {
    const Self = @This();
    pub const KEY_SIZE: usize = 16;
    pub const REGISTER_SIZE = 16;
    pub const STACK_SIZE = 16;
    // Chip8 has 16 8-bit registers, ranging from 0x0 to 0xF. The register
    // 0xF is not for use of the programs, instead it holds information from
    // instructions performed.
    registers: [REGISTER_SIZE]u8,
    // The program counter (PC) is a special register that holds the address of
    // the next instruction to be executed.
    pc: u16,
    // The 16-bit index register (IR) is used to point at locations in memory.
    ir: u16,
    // The 8-bit delay timer register.
    dt: u8,
    // The -bit sound timer register.
    st: u8,
    // 16-level stack.
    stack: [STACK_SIZE]u16,
    // The Stack pointer.
    sp: u8,
    memory: Ch8Memory,
    // Chip8 has 16 keys that can either be activated (or down) or deactivated (or up).
    keys: [KEY_SIZE]u1,
    // The original Chip8 had a 32x64 black-and-white display. Here we represent it as a contiguous
    // block of memory that can be either activated (=1, representing white) or deactivated (=0, 
    // representing black). The abstract position (X,Y) correspond to the index Y*DCOLS + X in our
    // representation.
    graphics: Ch8Graphics,

    pub fn init() Self{
        var self: Self = undefined;
        self.pc = Ch8Memory.MEM_PROGRAM_START;
        self.ir = 0x0000;
        self.dt = 0x00;
        self.st = 0x00;
        self.sp = 0;
        @memset(&self.registers, 0);
        @memset(&self.stack, 0);
        @memset(&self.keys, 0);
        self.memory = Ch8Memory.init();
        self.graphics = Ch8Graphics.init();
        return self;
    }

    pub fn loadKey(self: *Self, key: usize, down: bool) void{
        self.keys[key] = if (down) 1 else 0;
    }

    // THE EMULATION CYCLE
    // -------------------

    pub fn emulate(self: *Self, dbg: ?*db.Debugger) !void{
        const opcode: Opcode = self.memory.getOpcode(self.pc);
        self.incrementPC();
        try self.decode(opcode, dbg);
        if (dbg) |d|{
            d.print();
        }
    }

    pub fn tickTimers(self: *Self) void{
        if (self.dt > 0){
            self.dt -= 1;
        }
        if (self.st > 0){
            if (self.st == 1){
                // TO-DO
                // BEEP
            }
            self.st -= 1;
        }
    }

    pub fn decode(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) !void{
        try switch (opcode.msq) {
            0x0 => {
                try switch (opcode.lsq) {
                    0x0 => self.cls(dbg),
                    0xE => self.ret(dbg),
                    else => return CPUError.InvalidOpcode,
                };
            },
            0x1 => self.jpAddr(opcode, dbg),
            0x2 => try self.callAdrr(opcode, dbg),
            0x3 => self.seVxByte(opcode, dbg),
            0x4 => self.sneVxByte(opcode, dbg),
            0x5 => self.seVxVy(opcode, dbg),
            0x6 => self.ldVxByte(opcode, dbg),
            0x7 => self.addVxByte(opcode, dbg),
            0x8 => {
                switch (opcode.lsq) {
                    0x0 => self.ldVxVy(opcode, dbg),
                    0x1 => self.orVxVy(opcode, dbg),
                    0x2 => self.andVxVy(opcode, dbg),
                    0x3 => self.xorVxVy(opcode, dbg),
                    0x4 => self.addVxVy(opcode, dbg),
                    0x5 => self.subVxVy(opcode, dbg),
                    0x6 => self.shrVx(opcode, dbg),
                    0x7 => self.subnVxVy(opcode, dbg),
                    0xE => self.shlVx(opcode, dbg),
                    else => return CPUError.InvalidOpcode
                }
            },
            0x9 => self.sneVxVy(opcode, dbg),
            0xA => self.ldIAddr(opcode, dbg),
            0xB => self.jpV0Addr(opcode, dbg),
            0xC => self.rndVxByte(opcode, dbg),
            0xD => self.drwVxVyNibble(opcode, dbg),
            0xE => {
                switch (opcode.lsq) {
                    0xE => self.skpVx(opcode, dbg),
                    0x1 => self.sknpVX(opcode, dbg),
                    else => return CPUError.InvalidOpcode
                }
            },
            0xF => {
                try switch (opcode.lsq) {
                    0x7 => self.ldVxDt(opcode, dbg),
                    0xA => self.ldVxKey(opcode, dbg),
                    0x5 => {
                        try switch (opcode.iq1) {
                            0x1 => self.ldDtVx(opcode, dbg),
                            0x5 => self.ldIV0Vx(opcode, dbg),
                            0x6 => self.ldV0VxI(opcode, dbg),
                            else => return CPUError.InvalidOpcode
                        };
                    },
                    0x8 => self.ldStVx(opcode, dbg),
                    0xE => self.addIVx(opcode, dbg),
                    0x9 => self.ldFVx(opcode, dbg),
                    0x3 => self.ldBVx(opcode, dbg),
                    else => return CPUError.InvalidOpcode
                };
            },
        };
    }

    // REGISTERS INCREMENTS
    // --------------------

    fn incrementPC(self: *Self) void{
        self.pc += 2;
    }

    // THE INSTRUCTIONS
    // ----------------

    // Opcode: 0x0NNN.
    // // Jump to machine code routine at 0x0NNN.
    // // NOT IMPLEENTED FOR THIS EMULATOR.
    // fn sysAdrr(self: *Self, dbg: ?*db.Debugger) void{
    // }

    // OPCODE: 0x00E0
    // clear the screen.
    // The interpreter sets the graphic's representation's entries to 0.
    fn cls(self: *Self, dbg: ?*db.Debugger) void{
        self.graphics.cls();
        if (dbg) |d|{
            d.last_instruction = &d.I_0x00E0;
        }
    }

    // OPCODE: 0x00EE
    // The interpreter sets the PC to the address at the top of the stack.
    fn ret(self: *Self, dbg: ?*db.Debugger) StackError!void{
        if (self.sp == 0){
            return StackError.EMPTY_STACK;
        }
        self.sp -= 1;
        self.pc = self.stack[self.sp];
        if (dbg) |d|{
            d.last_instruction = &d.I_0x00EE;
        }
    }

    // OPCODE: 0x1NNN
    // Jumps to addr NNN.
    // The interpreter sets the PC to the address NNN.
    fn jpAddr(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        self.pc = opcode.fetchAddr();
        if (dbg) |d|{
            utils.u16Hex(self.pc, d.I_0x1NNN[3..]);
            d.last_instruction = &d.I_0x1NNN;
        }
    }

    // OPCODE: 0x2NNN
    // call the subroutine at NNN.
    // The interpreter sets the top of the stack to PC and the PC to NNN.
    fn callAdrr(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) StackError!void{
        if (self.sp == 16){
            return StackError.STACK_OVERFLOW;
        }
        self.stack[self.sp] = self.pc;
        self.sp += 1;
        self.pc = opcode.fetchAddr();
        if (dbg) |d|{
            utils.u16Hex(self.pc, d.I_0x2NNN[5..]);
            d.last_instruction = &d.I_0x2NNN;
        }
    }

    // OPCODE: 0x3XKK
    // Skip next instruction if VX = KK.
    // The interpreter compares Vx with the byte KK; if they are equal, it
    // increments the PC.
    fn seVxByte(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const kk = opcode.fetchByte();
        if (self.registers[x] == kk){
            self.incrementPC();
        }
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x3XNN[5..8]);
            utils.byteHex(kk, d.I_0x3XNN[11..]);
            d.last_instruction = &d.I_0x3XNN;
        }
    }

    // OPCODE: 0x4XKK
    // Skip next instruction if VX != KK.
    // The interpreter compares Vx with the byte KK; if they are not equal, it
    // increments the PC.
    fn sneVxByte(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const kk = opcode.fetchByte();
        if (self.registers[x] != kk){
            self.incrementPC();
        }
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x4XKK[6..9]);
            utils.byteHex(kk, d.I_0x4XKK[12..]);
            d.last_instruction = &d.I_0x4XKK;
        }
    }

    // OPCODE: 0x5XY0
    // Skip next instruction if VX = XY.
    // The interpreter compares VX with VY; if they are equal, it increments
    // the PC.
    fn seVxVy(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const y = opcode.iq1;
        if (self.registers[x] == self.registers[y]){
            self.incrementPC();
        }
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x5XY0[5..8]);
            utils.nibbleHex(y, d.I_0x5XY0[13..16]);
            d.last_instruction = &d.I_0x5XY0;
        }
    }

    // OPCODE: 0x6XKK
    // Set VX := KK.
    // The interpreter set the register VX to the byte KK.
    fn ldVxByte(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        self.registers[x] = opcode.fetchByte();
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x6XKK[5..8]);
            utils.byteHex(self.registers[x], d.I_0x6XKK[11..]);
            d.last_instruction = &d.I_0x6XKK;
        }
    }

    // OPCODE: 0x7XKK
    // VX := VX + KK
    // The interpreter adds VX to the byte KK and stores it in VX. No carry
    // is considered.
    fn addVxByte(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const kk = opcode.fetchByte();
        self.registers[x], _ = @addWithOverflow(self.registers[x], kk);
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x7XKK[6..9]);
            utils.byteHex(kk, d.I_0x7XKK[12..]);
            d.last_instruction = &d.I_0x7XKK;
        }
    }

    // OPCODE: 0x8XY0
    // Set VX := VY.
    // The interpreter sets the register VX to VY.
    fn ldVxVy(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const y = opcode.iq1;
        self.registers[x] = self.registers[y];
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x8XY0[5..8]);
            utils.nibbleHex(y, d.I_0x8XY0[13..16]);
            d.last_instruction = &d.I_0x8XY0;
        }
    }

    // OPCODE: 0x8XY1
    // VX := VX OR VY (bitwise).
    // The interpreter sets VX to the bitwise OR between VX and VY.
    fn orVxVy(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const y = opcode.iq1;
        self.registers[x] |= self.registers[y];
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x8XY1[5..8]);
            utils.nibbleHex(y, d.I_0x8XY1[13..16]);
            d.last_instruction = &d.I_0x8XY1;
        }
    }

    // OPCODE: 0x8XY2
    // VX := VX AND VY (bitwise).
    // The interpreter sets VX to the bitwise AND between VX and VY.
    fn andVxVy(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const y = opcode.iq1;
        self.registers[x] &= self.registers[y];
        if (dbg) |d|{ utils.nibbleHex(x, d.I_0x8XY2[6..9]);
            utils.nibbleHex(y, d.I_0x8XY2[14..17]);
            d.last_instruction = &d.I_0x8XY2;
        }
    }

    // OPCODE: 0x8XY3
    // VX := VX XOR VY (bitwise).
    // The interpreter sets VX to the bitwise XOR between VX and VY.
    fn xorVxVy(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const y = opcode.iq1;
        self.registers[x] ^= self.registers[y];
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x8XY3[6..9]);
            utils.nibbleHex(y, d.I_0x8XY3[14..17]);
            d.last_instruction = &d.I_0x8XY3;
        }
    }

    // OPCODE: 0x8XY4
    // VX := VX + VY, VF := carry.
    // The interpreter adds VX to VY and stores into VX; if overflow ocurred, VF
    // is set to 1, otherwise 0.
    fn addVxVy(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const y = opcode.iq1;
        self.registers[x], self.registers[0xF] =
            @addWithOverflow(self.registers[x], self.registers[y]);
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x8XY4[6..9]);
            utils.nibbleHex(y, d.I_0x8XY4[14..17]);
            d.last_instruction = &d.I_0x8XY4;
        }
    }

    // OPCODE: 0x8XY5
    // VX := VX - VY, VF := NOT Borrow.
    // The interpreter subtracts VY of VX; if VX > VY then VF is set to 1, 
    // oterwise 0.
    fn subVxVy(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const y = opcode.iq1;
        self.registers[0xF] = if (self.registers[x] > self.registers[y]) 1
            else 0;
        self.registers[x], _ = @subWithOverflow(self.registers[x], self.registers[y]);
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x8XY5[6..9]);
            utils.nibbleHex(y, d.I_0x8XY5[14..17]);
            d.last_instruction = &d.I_0x8XY5;
        }
    }

    // OPCODE: 0x8XY6
    // VX := VX >> 1, VF := underflow.
    // The interpreter performs the right shift by 1 in the register VX. VF is
    // set to the reminder of VX//2.
    fn shrVx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const y = opcode.iq1;
        self.registers[0xF] = self.registers[x] & 0x1;
        self.registers[x] >>= 1;
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x8XY6[6..9]);
            utils.nibbleHex(y, d.I_0x8XY6[14..17]);
            d.last_instruction = &d.I_0x8XY6;
        }
    }

    // OPCODE: 0x8XY7
    // VX := VY - VX, VF := NOT Borrow.
    // The interpreter subtracts VX of VY; if VY > VX then VF is set to 1, 
    // oterwise 0.
    fn subnVxVy(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const y = opcode.iq1;
        self.registers[0xF] = if (self.registers[y] > self.registers[x]) 1
            else 0;
        self.registers[x], _ = @subWithOverflow(self.registers[y], self.registers[x]);
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x8XY7[7..10]);
            utils.nibbleHex(y, d.I_0x8XY7[15..18]);
            d.last_instruction = &d.I_0x8XY7;
        }
    }

    // OPCODE: 0x8XYE
    // VX := VX << 1, VF := carry
    // The interpreter performs the left shift by 1 in the register VX. VF is
    // set to 1 if overflow occured or 0, otherwise.
    fn shlVx(self: *Self, opcode: Opcode, dbg: ?* db.Debugger) void{
        const x = opcode.iq2;
        const y = opcode.iq1;
        self.registers[x], self.registers[0xF] = @shlWithOverflow(self.registers[x], 1);
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x8XYE[6..9]);
            utils.nibbleHex(y, d.I_0x8XYE[14..17]);
            d.last_instruction = &d.I_0x8XYE;
        }
    }

    // OPCODE: 0x9XY0
    // Skip next instruction if VX != VY
    // The interpreter compares VX with VY; if they are not equal, it increments
    // the PC.
    fn sneVxVy(self: *Self, opcode: Opcode, dbg: ?* db.Debugger) void{
        const x = opcode.iq2;
        const y = opcode.iq1;
        if (self.registers[x] != self.registers[y]){
            self.incrementPC();
        }
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x9XY0[6..9]);
            utils.nibbleHex(y, d.I_0x9XY0[14..17]);
            d.last_instruction = &d.I_0x9XY0;
        }
    }

    // OPCODE: 0xANNN
    // I := NNN.
    fn ldIAddr(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        self.ir = opcode.fetchAddr();
        if (dbg) |d|{
            utils.u16Hex(self.ir, d.I_0xANNN[6..]);
            d.last_instruction = &d.I_0xANNN;
        }
    }

    // OPCODE: 0xBNNN
    // Jump to location NNN+V0
    fn jpV0Addr(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) MemoryError!void{
        const addr: u16 = opcode.fetchAddr();
        const loc, const carry = @addWithOverflow(self.registers[0], addr);
        if (!Ch8Memory.isMemAdrrValid(loc) or carry != 0){
            return MemoryError.MEMORY_INDEX_OUT_OF_BOUNDS;
        }
        self.pc = loc;
        if (dbg) |d|{
            utils.u16Hex(addr, d.I_0xBNNN[7..]);
            d.last_instruction = &d.I_0xBNNN;
        }
    }

    // OPCODE: 0xCXKK
    // Set VX = randon byte & KK.
    // The interpreter generates a random u8 and performs a bitwise and with
    // the byte KK. Te result is stored in VX.
    fn rndVxByte(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const kk: u8 = opcode.fetchByte();
        self.registers[x] = std.crypto.random.int(u8) & kk;
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xCXKK[6..9]);
            utils.byteHex(kk, d.I_0xCXKK[12..]);
            d.last_instruction = &d.I_0xCXKK;
        }
    }

    // OPCODE: 0xDXYN
    // Display n-byte sprite starting at memory location IR at (VX,VY) and
    // set VF as collision.

    // A sprite is an array of 4-bit unsigned integer, thus with maximum height
    // of 16 pixels. The sprite is drawn from the memory starting at the address pointed
    // by the index register and ranging indicated by the nibble. Bellow, we show an 
    // example of an sprite starting at memory addres 0x0C32 with height 6. This sprite
    // is a representation of the letter E.
    //
    //                  bit 0 1 2 3 4 5 6 7
    //         -------+--------------------
    //         0x0C32 |     0 1 1 1 1 1 0 0
    //         0x0C33 |     0 1 0 0 0 0 0 0
    //         0x0C34 |     0 1 0 0 0 0 0 0
    //         0x0C35 |     0 1 1 1 1 1 0 0
    //         0x0C36 |     0 1 0 0 0 0 0 0
    //         0x0C37 |     0 1 0 0 0 0 0 0
    //         0x0C38 |     0 1 1 1 1 1 0 0
    //
    // The draw function then checks the activation of each bit of each byte, when it is 
    // active, it XORs the correspondent coordinate with the value 1 and if the result is 0,
    // sets the register 0xF to 1.
    fn drwVxVyNibble(self: *Chip8, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const y = opcode.iq1;
        const vx = self.registers[x];
        const vy = self.registers[y];
        const nibble = opcode.lsq;
        const sprite = self.memory.getSprite(self.ir, nibble);
        self.graphics.draw(vx, vy, sprite, &self.registers[0xF]);
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xDXYN[6..9]);
            utils.nibbleHex(y, d.I_0xDXYN[14..17]);
            utils.nibbleHex(nibble, d.I_0xDXYN[20..]);
            d.last_instruction = &d.I_0xDXYN;
        }
    }
   // fn drwVxVyNibble(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
   //      const x = opcode.iq2;
   //      const y = opcode.iq1;
   //      const nibble = opcode.lsq;
   //      const x_co = self.registers[x];
   //      const y_co = self.registers[y];
   //      var row: usize = 0;
   //      while (row < nibble) : (row += 1){
   //          const byte = self.memory[self.ir + row];
   //          var col: usize = 0;
   //          while (col < 8) : (col += 1){
   //              const pixel_ptr = self.getPixelPtr(x_co + col, y_co + row);
   //              const bit: u1 = @truncate((byte >> @truncate(7 - col)) & 0x1);
   //              pixel_ptr.* ^= bit;
   //              if (bit == 1 and pixel_ptr.* == 0){
   //                  self.registers[0xF] = 1;
   //              }
   //          }
   //      }
   //      if (dbg) |d|{
   //          utils.nibbleHex(x, d.I_0xDXYN[6..9]);
   //          utils.nibbleHex(y, d.I_0xDXYN[14..17]);
   //          utils.nibbleHex(nibble, d.I_0xDXYN[20..]);
   //          d.last_instruction = &d.I_0xDXYN;
   //      }
   //  }


    // OPCODE: 0xEX9E
    // Skip next instruction if key VX is pressed
    fn skpVx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const key: u8 = self.registers[x];
        if (self.keys[key] == 1){
            self.incrementPC();
        }
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xEX9E[6..]);
            d.last_instruction = &d.I_0xEX9E;
        }
    }

    // OPCODE: 0xEXA1
    // Skip next instruction if key VX is not pressed.
    fn sknpVX(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const key: u8 = self.registers[x];
        if (self.keys[key] == 0){
            self.incrementPC();
        }
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xEXA1[7..]);
            d.last_instruction = &d.I_0xEXA1;
        }
    }

    // OPCODE: 0xFX07
    // VX := DT
    fn ldVxDt(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        self.registers[x] = self.dt;
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX07[5..8]);
            d.last_instruction = &d.I_0xFX07;
        }
    }

    // OPCODE: 0xFX0A
    // Wait for a key press, store the key in VX.
    fn ldVxKey(self: *Self, opcode: Opcode, dbg:?*db.Debugger) void{
        const x = opcode.iq2;
        const key_pressed: bool = for (0.., self.keys) |i, key|{
            if (key == 1){
                self.registers[x] = @intCast(i);
                break true;
            }
        } else false;
        if (!key_pressed){
            self.pc -= 2;
        }
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX0A[5..8]);
            d.last_instruction = &d.I_0xFX0A;
        }
    }

    //OPCODE: 0xFX15
    // DT := VX
    fn ldDtVx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        self.dt = self.registers[x];
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX15[9..12]);
            d.last_instruction = &d.I_0xFX15;
        }
    }

    // OPCODE: 0xFX18
    // ST := VX
    fn ldStVx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        self.st = self.registers[x];
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX18[9..12]);
            d.last_instruction = &d.I_0xFX18;
        }
    }

    // OPCODE: 0xFX1E
    // I := I + VX
    fn addIVx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        self.ir, _ = @addWithOverflow(self.ir, self.registers[x]);
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX1E[9..12]);
            d.last_instruction = &d.I_0xFX1E;
        }
    }

    // OPCODE: 0xFX29
    // I := location of the sprite for digit VX
    fn ldFVx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x = opcode.iq2;
        const digit: u8 = self.registers[x];
        self.ir = @intCast(Ch8Memory.FONT_MEM_START + (5*digit));
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX29[8..11]);
            d.last_instruction = &d.I_0xFX29;
        }
    }

    // OPCODE: 0xFX33
    // Store the bcd representation of VX in memory addr I, I+1 and I+2, respc.
    fn ldBVx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) !void{
        const x = opcode.iq2;
        var vx: u8 = self.registers[x];
        try self.memory.ldByte(vx % 10, self.ir + 2);
        vx /= 10;
        try self.memory.ldByte(vx % 10, self.ir + 1);
        vx /= 10;
        try self.memory.ldByte(vx % 10, self.ir);
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX33[8..11]);
            d.last_instruction = &d.I_0xFX33;
        }
    }

    // OPCODE: 0xFX55
    // Store regirsters V0..VX in memory, starting at I
    fn ldIV0Vx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) !void{
        const x = opcode.iq2;
        for (0..x) |i|{
            try self.memory.ldByte(self.registers[i], self.ir + i);
        }
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX55[10..13]);
            d.last_instruction = &d.I_0xFX55;
        }
    }

    //OPCODE: 0xFX65
    // Read registers V0..VX from memory starting at I
    fn ldV0VxI(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) !void{
        const x = opcode.iq2;
        for (0..x) |i|{
            const byte = try self.memory.getByte(self.ir + i);
            self.registers[i] = byte;
        }
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX65[5..8]);
            d.last_instruction = &d.I_0xFX65;
        }
    }
};

test "opcode"{
    const opcode: Opcode = Opcode.init(0x1234);
    try testing.expectEqual(opcode.lsq, 0x4);
    try testing.expectEqual(opcode.iq1, 0x3);
    try testing.expectEqual(opcode.iq2, 0x2);
    try testing.expectEqual(opcode.msq, 0x1);
    try testing.expectEqual(opcode.fetchAddr(), 0x0234);
    try testing.expectEqual(opcode.fetchByte(), 0x34);
}

test "emulation"{
    // CLS.
    {
        const opcode: Opcode = Opcode.init(0x00E0);
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("CLS", dbg.last_instruction);
        for (cpu.graphics.buffer) |pixel|{
            try testing.expectEqual(0, pixel);
        }
    }
    // CALL - RET.
    {
        // CALL.
        const call_opc = Opcode.init(0x2FFF);
        // RET.
        const ret_opc = Opcode.init(0x00EE);
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        // put something on the stack before to avoid error.
        try cpu.decode(call_opc, &dbg);
        try testing.expectEqualStrings("CALL 0x0FFF", dbg.last_instruction);
        try cpu.decode(ret_opc, &dbg);
        try testing.expectEqualStrings("RET", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x1234));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("JP 0x0234", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x31CE));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("SE V{0x1}, 0xCE", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x4321));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("SNE V{0x3}, 0x21", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x5820));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("SE V{0x8}, V{0x2}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x63CF));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("LD V{0x3}, 0xCF", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x717B));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("ADD V{0x1}, 0x7B", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x8AB0));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("LD V{0xA}, V{0xB}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x8041));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("OR V{0x0}, V{0x4}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x8A02));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("AND V{0xA}, V{0x0}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x87B3));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("XOR V{0x7}, V{0xB}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x89C4));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("ADD V{0x9}, V{0xC}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x8335));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("SUB V{0x3}, V{0x3}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x8676));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("SHR V{0x6}, V{0x7}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x8AC7));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("SUBN V{0xA}, V{0xC}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x808E));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("SHL V{0x0}, V{0x8}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x9EC0));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("SNE V{0xE}, V{0xC}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xAEC7));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("LD I, 0x0EC7", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xBC00));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("JP V0, 0x0C00", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xC123));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("RND V{0x1}, 0x23", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xDC03));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("DRW V{0xC}, V{0x0}, 0x3", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xE09E));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("SKP V{0x0}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xE5A1));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("SKNP V{0x5}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF507));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("LD V{0x5}, DT", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF60A));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("LD V{0x6}, KEY", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF415));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("LD DT, V{0x4}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF818));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("LD ST, V{0x8}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF01E));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("ADD I, V{0x0}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF329));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("LD F, V{0x3}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF933));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("LD B, V{0x9}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF255));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("LD [I], V{0x2}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xFC55));
        var cpu: Chip8 = Chip8.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.decode(opcode, &dbg);
        try testing.expectEqualStrings("LD [I], V{0xC}", dbg.last_instruction);
    }
}

test "cls"{
    var cpu = Chip8.init();
    const opcode: Opcode = Opcode.init(0x00E0);
    cpu.graphics.buffer = [_]u1{1} ** Ch8Graphics.DSIZE;
    try cpu.decode(opcode, null);
    for (cpu.graphics.buffer) |pix|{
        try testing.expectEqual(pix, 0);
    }
}

test "jmp-ret-call"{
    // normal emulation, without errrors.
    {
        var cpu = Chip8.init();
        // JMP to addr 0x02FF
        const opc1: Opcode = @bitCast(@as(u16, 0x12FF));
        // CALL addr 0x2C34
        const opc2: Opcode = @bitCast(@as(u16, 0x2C34));
        // Ret
        const opc3: Opcode = @bitCast(@as(u16, 0x00EE));
        try cpu.decode(opc1, null);
        try testing.expectEqual(cpu.pc, 0x02FF);
        try cpu.decode(opc2, null);
        try testing.expectEqual(cpu.pc, 0x0C34);
        try testing.expectEqual(cpu.sp, 1);
        try testing.expectEqual(cpu.stack[0], 0x02FF);
        try cpu.decode(opc3, null);
        try testing.expectEqual(cpu.pc, 0x02FF);
        try testing.expectEqual(cpu.sp, 0);
    }

    // testing errors
    {
        var cpu = Chip8.init();
        // Ret
        const opc1: Opcode = @bitCast(@as(u16, 0x00EE));
        // CALL addr 0x2C34
        const opc2: Opcode = @bitCast(@as(u16, 0x2C34));
        // trying to return from an empty stack.
        const err1 = cpu.decode(opc1, null);
        try testing.expectError(StackError.EMPTY_STACK, err1);
        cpu.sp = 16;
        // trying to call on a full stack.
        const err2 = cpu.decode(opc2, null);
        try testing.expectError(StackError.STACK_OVERFLOW, err2);
    }
}

test "load_skip_instructions"{
    // SE VX, Byte (equal).
    {
        var cpu = Chip8.init();
        const op_ld: Opcode = @bitCast(@as(u16, 0x65FC));
        const op_se: Opcode = @bitCast(@as(u16, 0x35FC));
        try cpu.decode(op_ld, null);
        try testing.expectEqual(cpu.registers[0x5], 0xFC);
        try cpu.decode(op_se, null);
        try testing.expectEqual(cpu.pc, Chip8.MEM_ISTART + 2);
    }
    // SE VX, Byte (not equal).
    {
        var cpu = Chip8.init();
        const op_ld: Opcode = @bitCast(@as(u16, 0x61FC));
        const op_se: Opcode = @bitCast(@as(u16, 0x31FA));
        try cpu.decode(op_ld, null);
        try testing.expectEqual(cpu.registers[0x1], 0xFC);
        try cpu.decode(op_se, null);
        try testing.expectEqual(cpu.pc, Chip8.MEM_ISTART);
    }
    // SNE VX, Byte (not equal).
    {
        var cpu = Chip8.init();
        const op_ld: Opcode = @bitCast(@as(u16, 0x6FFC));
        const op_se: Opcode = @bitCast(@as(u16, 0x4FFA));
        try cpu.decode(op_ld, null);
        try testing.expectEqual(cpu.registers[0xF], 0xFC);
        try cpu.decode(op_se, null);
        try testing.expectEqual(cpu.pc, Chip8.MEM_ISTART + 2);
    }
    // SNE VX, Byte (equal).
    {
        var cpu = Chip8.init();
        const op_ld: Opcode = @bitCast(@as(u16, 0x69A4));
        const op_se: Opcode = @bitCast(@as(u16, 0x49A4));
        try cpu.decode(op_ld, null);
        try testing.expectEqual(cpu.registers[0x9], 0xA4);
        try cpu.decode(op_se, null);
        try testing.expectEqual(cpu.pc, Chip8.MEM_ISTART);
    }
    // SE Vx, Vy (equal)
    {
        var cpu = Chip8.init();
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x63A4));
        const op_ld_y: Opcode = @bitCast(@as(u16, 0x67A4));
        const op_se: Opcode = @bitCast(@as(u16, 0x5370));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld_y, null);
        try testing.expectEqual(cpu.registers[0x3], cpu.registers[0x7]);
        try cpu.decode(op_se, null);
        try testing.expectEqual(cpu.pc, Chip8.MEM_ISTART + 2);
    }
    // SE Vx, Vy (not equal)
    {
        var cpu = Chip8.init();
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x69A4));
        const op_ld_y: Opcode = @bitCast(@as(u16, 0x62C4));
        const op_se: Opcode = @bitCast(@as(u16, 0x5920));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld_y, null);
        try testing.expectEqual(cpu.registers[0x9], 0xA4);
        try testing.expectEqual(cpu.registers[0x2], 0xC4);
        try cpu.decode(op_se, null);
        try testing.expectEqual(cpu.pc, Chip8.MEM_ISTART);
    }
    // SNE Vx, Vy (equal)
    {
        var cpu = Chip8.init();
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x63A4));
        const op_ld_y: Opcode = @bitCast(@as(u16, 0x67A4));
        const op_sne: Opcode = @bitCast(@as(u16, 0x9370));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld_y, null);
        try testing.expectEqual(cpu.registers[0x3], cpu.registers[0x7]);
        try cpu.decode(op_sne, null);
        try testing.expectEqual(cpu.pc, Chip8.MEM_ISTART);
    }
    // SNE Vx, Vy (not equal)
    {
        var cpu = Chip8.init();
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x69A4));
        const op_ld_y: Opcode = @bitCast(@as(u16, 0x62C4));
        const op_sne: Opcode = @bitCast(@as(u16, 0x9290));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld_y, null);
        try testing.expectEqual(cpu.registers[0x9], 0xA4);
        try testing.expectEqual(cpu.registers[0x2], 0xC4);
        try cpu.decode(op_sne, null);
        try testing.expectEqual(cpu.pc, Chip8.MEM_ISTART + 2);
    }
}

test "add_byte"{
    // adding without carry.
    {
        var cpu = Chip8.init();
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x60F9));
        const op_add: Opcode = @bitCast(@as(u16, 0x7001));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_add, null);
        try testing.expectEqual(cpu.registers[0x0], 0xFA);
        try testing.expectEqual(cpu.registers[0xF], 0x00);
    }
    // adding with carry.
    {
        var cpu = Chip8.init();
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x65FF));
        const op_add: Opcode = @bitCast(@as(u16, 0x7501));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_add, null);
        try testing.expectEqual(cpu.registers[0x5], 0x00);
        try testing.expectEqual(cpu.registers[0xF], 0x00);
    }
}

test "register_arithmetics"{
    var cpu = Chip8.init();
    // LD Vx, Vy.
    {
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x69A4));
        const op_ld: Opcode = @bitCast(@as(u16, 0x8920));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld, null);
        try testing.expectEqual(cpu.registers[0x9], cpu.registers[0x2]);
    }
    // OR Vx, Vy.
    {
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x6704));
        const op_ld_y: Opcode = @bitCast(@as(u16, 0x64A4));
        const result: u8 = 0x04 | 0xA4;
        const op_ld: Opcode = @bitCast(@as(u16, 0x8741));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld_y, null);
        try cpu.decode(op_ld, null);
        try testing.expectEqual(cpu.registers[0x7], result);
    }
    // AND Vx, Vy.
    {
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x654A));
        const op_ld_y: Opcode = @bitCast(@as(u16, 0x6134));
        const result: u8 = 0x4A & 0x34;
        const op_and: Opcode = @bitCast(@as(u16, 0x8512));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld_y, null);
        try cpu.decode(op_and, null);
        try testing.expectEqual(cpu.registers[0x5], result);
    }
    // XOR Vx, Vy.
    {
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x65FA));
        const op_ld_y: Opcode = @bitCast(@as(u16, 0x613C));
        const result: u8 = 0xFA ^ 0x3C;
        const op_xor: Opcode = @bitCast(@as(u16, 0x8513));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld_y, null);
        try cpu.decode(op_xor, null);
        try testing.expectEqual(cpu.registers[0x5], result);
    }
    // ADD Vx, Vy (no overflow).
    {
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x654C));
        const op_ld_y: Opcode = @bitCast(@as(u16, 0x611B));
        const result: u8, const carry: u8 = @addWithOverflow(
            @as(u8,0x4C), @as(u8,0x1B));
        const op_add: Opcode = @bitCast(@as(u16, 0x8514));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld_y, null);
        try cpu.decode(op_add, null);
        try testing.expectEqual(cpu.registers[0x5], result);
        try testing.expectEqual(cpu.registers[0xF], carry);
    }
    // ADD Vx, Vy.
    {
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x654C));
        const op_ld_y: Opcode = @bitCast(@as(u16, 0x611B));
        const result: u8, const carry: u8 = @addWithOverflow(
            @as(u8,0x4C), @as(u8,0x1B));
        const op_add: Opcode = @bitCast(@as(u16, 0x8514));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld_y, null);
        try cpu.decode(op_add, null);
        try testing.expectEqual(cpu.registers[0x5], result);
        try testing.expectEqual(cpu.registers[0xF], carry);
    }
    // ADD Vx, Vy (overflow).
    {
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x65FF));
        const op_ld_y: Opcode = @bitCast(@as(u16, 0x61FB));
        const result: u8, const carry: u8 = @addWithOverflow(
            @as(u8,0xFF), @as(u8,0xFB));
        const op_add: Opcode = @bitCast(@as(u16, 0x8514));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld_y, null);
        try cpu.decode(op_add, null);
        try testing.expectEqual(cpu.registers[0x5], result);
        try testing.expectEqual(cpu.registers[0xF], carry);
    }
    // SUB Vx, Vy.
    {
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x650F));
        const op_ld_y: Opcode = @bitCast(@as(u16, 0x61FB));
        const result: u8, var carry: u1 = @subWithOverflow(
            @as(u8,0x0F), @as(u8,0xFB));
        carry = ~carry;
        const op_add: Opcode = @bitCast(@as(u16, 0x8515));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld_y, null);
        try cpu.decode(op_add, null);
        try testing.expectEqual(cpu.registers[0x5], result);
        try testing.expectEqual(cpu.registers[0xF], carry);
    }
    // SHR Vx, {Vy}.
    {
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x650F));
        const result = @as(u8,0x0F) >> 1;
        const op_shr: Opcode = @bitCast(@as(u16, 0x8516));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_shr, null);
        try testing.expectEqual(cpu.registers[0x5], result);
    }
    // SUBN Vx, Vy.
    {
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x650F));
        const op_ld_y: Opcode = @bitCast(@as(u16, 0x61FB));
        const result: u8, var carry: u1 = @subWithOverflow(
            @as(u8,0xFB), @as(u8,0x0F));
        carry = ~carry;
        const op_add: Opcode = @bitCast(@as(u16, 0x8517));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_ld_y, null);
        try cpu.decode(op_add, null);
        try testing.expectEqual(cpu.registers[0x5], result);
        try testing.expectEqual(cpu.registers[0xF], carry);
    }
    // SHL Vx, {Vy}.
    {
        const op_ld_x: Opcode = @bitCast(@as(u16, 0x65FF));
        const result, const carry: u1 = @shlWithOverflow(@as(u8,0xFF),1);
        const op_shr: Opcode = @bitCast(@as(u16, 0x851E));
        try cpu.decode(op_ld_x, null);
        try cpu.decode(op_shr, null);
        try testing.expectEqual(cpu.registers[0x5], result);
        try testing.expectEqual(cpu.registers[0xF], carry);
    }
    {
    }
    {
    }
    {
    }
    {
    }
    {
    }
}

test "ld_index_register"{
    var cpu = Chip8.init();
    const op: Opcode = @bitCast(@as(u16, 0xAF1C));
    try cpu.decode(op, null);
    try testing.expectEqual(cpu.ir, 0xF1C);
}

test "Jump NNN + V0"{
}

test "drawing"{
    // DRAWING `0` at `(0,0)`.
    //       Addr    Hex   bit 7 6 5 4 3 2 1 0
    //      -------+------+----------------
    //      0x0050 | 0xF0 |    1 1 1 1 0 0 0 0
    //      0x0051 | 0x90 |    1 0 0 1 0 0 0 0
    //      0x0052 | 0x90 |    1 0 0 1 0 0 0 0
    //      0x0053 | 0x90 |    1 0 0 1 0 0 0 0
    //      0x0054 | 0xF0 |    1 1 1 1 0 0 0 0
    {
        var cpu = Chip8.init();
        const op_x = Opcode.init(0x6000);
        const op_y = Opcode.init(0x6100);
        const op_ir = Opcode.init(0xA050);
        const op_drw = Opcode.init(0xD015);
        try cpu.decode(op_x, null);
        try cpu.decode(op_y, null);
        try cpu.decode(op_ir, null);
        try cpu.decode(op_drw, null);
    }
}
