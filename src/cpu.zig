const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const math = std.math;
const utils = @import("utils.zig");
const db = @import("debugger.zig");
// CONSTANTS

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

const KEY_SIZE: usize = 16;

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
    //            | | | |_ least significan quarter, aka nibble
    //            | | |___ info quarter 1
    //            | |_____ info quarter 2
    //            |_______ most significant quarter
    lsq: u4,
    iq1: u4,
    iq2: u4,
    msq: u4,

    pub fn fetchAddr(self: Opcode) u16{
    // The address consists of a 12-bit unsigned integer retrieved from the
    // opcode as follows
    //
    //         0x X N N N
    //             |_____|
    //                |___ address
    //
        return @as(u16, self.iq2) << 8 | @as(u16, self.iq1) << 4 | @as(u16, self.lsq); 
    }

    pub fn fetchByte(self: Opcode) u8{
    // The byte consists of a 8.bit unsigned integer retrieved from the
    // opcode as follows
    //
    //         0x X Y K K
    //               |___|
    //                 |__ byte
    //
        return @as(u8, self.iq1) << 4 | @as(u8, self.lsq);
    }
};


    // Chip8 has a 16-level stack (LIFO) to keep track of the order of the
    // instructions.
pub const Chip8Stack = struct{
    pub const STACK_SIZE: usize = 16;
    sp: u4,
    buffer: [STACK_SIZE]?u16,

    pub fn init() Chip8Stack{
        return Chip8Stack{
            .sp = 0x0,
            .buffer = [_]?u16{null} ** STACK_SIZE,
        };
    }

    // Enstack the adresss hold by the PC.
    pub fn call(self: *Chip8Stack, pc: u16) StackError!void{
        if (self.sp == 16){
            return StackError.STACK_OVERFLOW;
        }
        self.buffer[self.sp] = pc;
        self.sp += 1;
    }

    // Returns the top of the stack.
    pub fn ret(self: *Chip8Stack) StackError!u16{
        if (self.sp == 0){
            return Chip8Memory.MEM_ISTART;
        }
        self.sp -= 1;
        defer self.buffer[self.sp] = null;
        if (self.buffer[self.sp]) |item|{
            return item;
        }else return StackError.INVALID_ADDRESS;
    }

    // Visual representation of the stack for debugging purposes.
    pub fn represent(self: Chip8Stack, debg: *db.Debugger) void{
        for (0.., self.buffer) |i, addr|{
            debg.loadStack(i, addr);
        } 
    }
};

// The original Chip8 display was 64 wide and 32 bits tall and monochrome, i.e.
// each pixel is either black or white. This is abstractly represented by a
// contiguous buffer of size 64x32 porting 8-bit unsigned int. This is the infor-
// mation that Raylib will use to display the Chip-8's applications.
//
//         (0,0)  ______________________________________ (63,0)
//               |                                     |
//               |                                     |
//               |                                     |
//               |                                     |
//               |                                     |
//       (0, 31) |_____________________________________| (63, 31)
//
// The drawing process is done through the usage of sprites, see the `draw` method for more infor-
// mation.
pub const Chip8Graphics = struct {
    pub const DROWS: usize = 32;
    pub const DCOLS: usize = 64;
    // DSIZE := DROWS * DCOLS
    pub const DSIZE: usize = 2048;
    // The interpreter update the display in a 60 Hz rate, i.e. 60 FPS in modern terms.
    pub const UPDATE_RATE: usize = 60;
    // For the graphical representation purposes, the window displaying the
    // applications will be resized to 640x320.
    pub const RESIZE_RATE: usize = 10;

    // The buffer is the abstract representation of Chip8's screen as a contiguous block of memory.
    // The values can be 0x1 for white or 0x1 for black.
    buffer: [DSIZE]u1,

    pub fn init() Chip8Graphics{
        return Chip8Graphics{
            .buffer = [_]u1{0} ** DSIZE,
        };
    }

    // Clean the screen.
    pub fn cls(self: *Chip8Graphics) void{
        @memset(self.buffer[0..DSIZE], 0);
    }

    pub fn getPtrPixel(self: *Chip8Graphics, index_x: usize, index_y: usize) *u1{
        const pos_x = index_x & 63;
        const pos_y = index_y & 31;
        return &self.buffer[pos_y*DCOLS + pos_x];
    }

    pub fn pixelIsOn(self: *Chip8Graphics, index_x: usize, index_y: usize) bool{
        const pixelp = self.getPtrPixel(index_x, index_y);
        return if (pixelp.* == 1) true else false;
    }

    // A sprite is an array of u8 indexed by a nibble, i.e. an u4.
    // The draw function checks the activation of each bit in the elements of
    // the sprite.
    //
    //                  bit 7 6 5 4 3 2 1 0
    //         -------+--------------------
    //         byte 1 |     0 1 1 1 1 1 0 0
    //         byte 2 |     0 1 0 0 0 0 0 0
    //         byte 3 |     0 1 0 0 0 0 0 0
    //         byte 4 |     0 1 1 1 1 1 0 0
    //         byte 5 |     0 1 0 0 0 0 0 0
    //         byte 6 |     0 1 0 0 0 0 0 0
    //         byte 7 |     0 1 1 1 1 1 0 0
    //
    // If active, the function checks the array representation. Above
    // we see the sprite representation of the letter E. If the bit is activated
    pub fn draw(self: *Chip8Graphics, pos_x: u8, pos_y: u8, sprite: []u8, v0xF: *u8) void{
        v0xF.* = 0;
        for (0.., sprite) |row, byte|{
            for (0..8) |col|{
                const bit: u1 = @truncate((byte >> @truncate(col)) & 0x1);
                if (bit == 1){
                    const pixelp = self.getPtrPixel(pos_x + col, pos_y + row);
                    pixelp.* ^= bit;
                    if (pixelp.* == 0){
                        v0xF.* = 1;
                    }
                }
            }
        }
    }
};

pub const Chip8Memory = struct{
    // The interpreter has 4096 bytes of memory, ranging from 0x0000 to 0x0FFF.
    // The original Chip8 interpreter reserved the section 0x0000 - 0x1FF for the
    // interpreter itself. The only subsection that we use will be 0x050 - 0x0A0
    // that we reserve to storage the character set. The section 0x0200 - 0x0FFF
    // is dedicated to store the instructions of the program being executed.
    pub const MEM_SIZE: usize = 4096;
    pub const FONT_MEM_START: usize = 0x050;
    pub const FONT_MEM_END: usize = 0x0A0;
    pub const MEM_ISTART: usize = 0x0200;
    pub const MEM_END: usize = 0x0FFF;

    // The 16-bit index register is a special register used to store memory addresses.
    // In practice, it will store only 12-bit unsigned integers.
    buffer: [MEM_SIZE]u8,
    avaiable_mem: usize,

    pub fn init() Chip8Memory{
        var ram = Chip8Memory{
            .buffer = [_]u8{0} ** MEM_SIZE,
            .avaiable_mem = MEM_SIZE,
        };
        @memcpy(ram.buffer[FONT_MEM_START..FONT_MEM_END], FONT_SET[0..]);
        ram.avaiable_mem -= 0x01FF;
        return ram;
    }

    pub fn loadAddr(self: *Chip8Memory, addr: usize, item: u8) void{
        self.buffer[addr] = item;
    }

    pub fn getAdrr(self: Chip8Memory, addr: usize) u8{
        return self.buffer[addr];
    }

    pub fn getChunk(self: *Chip8Memory, starting_adrr: usize, end_addr: usize) []u8{
        return self.buffer[starting_adrr..end_addr];
    }

    pub fn loadChunk(self: *Chip8Memory, chunk: []u8, starting_address: usize) MemoryError!void{
        if (self.avaiable_mem >= chunk.len){
            return MemoryError.OUT_OF_MEMORY;
        }else if (starting_address < MEM_ISTART or starting_address > MEM_END){
            return MemoryError.MEMORY_INDEX_OUT_OF_BOUNDS; 
        }
        @memcpy(self.buffer[starting_address..starting_address+chunk.len], chunk.ptr);
        self.avaiable_mem -= chunk.len;
    }

    // Retrieve the opcode pointed by the PC.
    pub fn getOpcode(self: Chip8Memory, pc: u16) Opcode{
        var code: u16 = self.buffer[pc];
        code <<= 8;
        code |= @as(u16, @intCast(self.buffer[pc + 1]));
        const opcode: Opcode = @bitCast(code);
        return opcode;
    }
};

pub const Chip8CPU = struct {
    const Self = @This();
    pub const REGISTER_SIZE = 16;
    pub const MEMORY_SIZE = 
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
    memory: Chip8Memory,
    // In this implementation we choose to use a stack data structure instead
    // of an array and a stack pointer.
    stack: Chip8Stack,
    keys: [KEY_SIZE]u1,
    graphics: Chip8Graphics,
    allocator: Allocator,

    pub fn init() Self{
        var self: Self = undefined;
        self.registers = [_]u8{0} ** REGISTER_SIZE;
        self.pc = Chip8Memory.MEM_ISTART;
        self.ir = 0x0000;
        self.dt = 0x00;
        self.st = 0x00;
        self.memory = Chip8Memory.init();
        self.stack = Chip8Stack.init();
        self.keys = [_]u1{0} ** KEY_SIZE;
        self.graphics = Chip8Graphics.init();
        return self;
    }

    pub fn loadRom(self: *Self, filepath: [:0]const u8) !void{
        var file = std.fs.cwd().openFile(filepath, .{})
            catch |err| return err;
        defer file.close();
        const size = file.getEndPos()
            catch |err| return err;
        var reader = file.reader();
        for (0..size) |i|{
            const byte = reader.readByte()
                catch |err| return err;
            self.memory.loadAddr(Chip8Memory.MEM_ISTART + i, byte); 
        }
    }

    pub fn loadKey(self: *Self, key: usize) !void{
        self.keys[key] = 1;
    }

    // THE EMULATION CYCLE
    // -------------------

    pub fn emulateCycle(self: *Self, dbg: ?*db.Debugger) !void{
        const opcode: Opcode = self.memory.getOpcode(self.pc);
        self.incrementPC();
        try self.emulate(opcode, dbg);
        if (self.dt > 0){
            self.dt -= 1;
        }
        if (self.st > 0){
            self.st -= 1;
        }
        if (dbg) |d|{
            d.print();
        }
    }

    fn emulate(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) !void{
        switch (opcode.msq) {
            0x0 => {
                switch (opcode.lsq) {
                    0x0 => self.cls(dbg),
                    0xE => try self.ret(dbg),
                    else => return CPUError.InvalidOpcode,
                }
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
                switch (opcode.lsq) {
                    0x7 => self.ldVxDt(opcode, dbg),
                    0xA => self.ldVxKey(opcode, dbg),
                    0x5 => {
                        switch (opcode.iq1) {
                            0x1 => self.ldDtVx(opcode, dbg),
                            0x5 => self.ldIV0Vx(opcode, dbg),
                            0x6 => self.ldV0VxI(opcode, dbg),
                            else => return CPUError.InvalidOpcode
                        }
                    },
                    0x8 => self.ldStVx(opcode, dbg),
                    0xE => self.addIVx(opcode, dbg),
                    0x9 => self.ldFVx(opcode, dbg),
                    0x3 => self.ldBVx(opcode, dbg),
                    else => return CPUError.InvalidOpcode
                }
            },
        }
    }

    // REGISTERS INCREMENTS
    // --------------------

    fn incrementPC(self: *Self) void{
        self.pc += 2;
    }

    // THE INSTRUCTIONS
    // ----------------

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
    fn ret(self: *Self, dbg: ?*db.Debugger) !void{
        self.pc = try self.stack.ret();
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
        try self.stack.call(self.pc);
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
        const x: u4 = opcode.iq2;
        const kk: u8 = opcode.fetchByte();
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
        const x: u4 = opcode.iq2;
        const kk: u8 = opcode.fetchByte();
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
        const x: u4 = opcode.iq2;
        const y: u4 = opcode.iq1;
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
        const x: u4 = opcode.iq2;
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
        const x: u4 = opcode.iq2;
        const kk: u8 = opcode.fetchByte();
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
        const x: u4 = opcode.iq2;
        const y: u4 = opcode.iq1;
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
        const x: u4 = opcode.iq2;
        const y: u4 = opcode.iq1;
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
        const x: u4 = opcode.iq2;
        const y: u4 = opcode.iq1;
        self.registers[x] &= self.registers[y];
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0x8XY2[6..9]);
            utils.nibbleHex(y, d.I_0x8XY2[14..17]);
            d.last_instruction = &d.I_0x8XY2;
        }
    }

    // OPCODE: 0x8XY3
    // VX := VX XOR VY (bitwise).
    // The interpreter sets VX to the bitwise XOR between VX and VY.
    fn xorVxVy(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x: u4 = opcode.iq2;
        const y: u4 = opcode.iq1;
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
        const x: u4 = opcode.iq2;
        const y: u4 = opcode.iq1;
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
        const x: u4 = opcode.iq2;
        const y: u4 = opcode.iq1;
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
        const x: u4 = opcode.iq2;
        const y: u4 = opcode.iq1;
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
        const x: u4 = opcode.iq2;
        const y: u4 = opcode.iq1;
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
        const x: u4 = opcode.iq2;
        const y: u4 = opcode.iq1;
        self.registers[0xF] = (self.registers[x] >> 7) & 0x1;
        self.registers[x], _ = @shlWithOverflow(self.registers[x], 1);
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
        const x: u4 = opcode.iq2;
        const y: u4 = opcode.iq1;
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
    fn jpV0Addr(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const addr: u16 = opcode.fetchAddr();
        self.pc = self.registers[0x0] + addr;
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
        const x: u4 = opcode.iq2;
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
    fn drwVxVyNibble(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const ix: u4 = opcode.iq2;
        const iy: u4 = opcode.iq1;
        const nibble: u4 = opcode.lsq;
        const pos_x: u8 = self.registers[ix];
        const pos_y: u8 = self.registers[iy];
        const v0xF: *u8 = &self.registers[0xF];
        const sprite = self.memory.getChunk(self.pc, self.pc + nibble);
        self.graphics.draw(pos_x, pos_y, sprite, v0xF);
        if (dbg) |d|{
            utils.nibbleHex(ix, d.I_0xDXYN[6..9]);
            utils.nibbleHex(iy, d.I_0xDXYN[14..17]);
            utils.nibbleHex(nibble, d.I_0xDXYN[20..]);
            d.last_instruction = &d.I_0xDXYN;
        }
    }

    // OPCODE: 0xEX9E
    // Skip next instruction if key VX is pressed
    fn skpVx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x: u4 = opcode.iq2;
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
        const x: u4 = opcode.iq2;
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
        const x: u4 = opcode.iq2;
        self.registers[x] = self.dt;
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX07[5..8]);
            d.last_instruction = &d.I_0xFX07;
        }
    }

    // OPCODE: 0xFX0A
    // Wait for a key press, store the key in VX.
    fn ldVxKey(self: *Self, opcode: Opcode, dbg:?*db.Debugger) void{
        const x: u4 = opcode.iq2;
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
        const x: u4 = opcode.iq2;
        self.dt = self.registers[x];
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX15[9..12]);
            d.last_instruction = &d.I_0xFX15;
        }
    }

    // OPCODE: 0xFX18
    // ST := VX
    fn ldStVx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x: u4 = opcode.iq2;
        self.st = self.registers[x];
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX18[9..12]);
            d.last_instruction = &d.I_0xFX18;
        }
    }

    // OPCODE: 0xFX1E
    // I := I + VX
    fn addIVx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x: u4 = opcode.iq2;
        self.ir, _ = @addWithOverflow(self.ir, self.registers[x]);
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX1E[9..12]);
            d.last_instruction = &d.I_0xFX1E;
        }
    }

    // OPCODE: 0xFX29
    // I := location of the sprite for digit VX
    fn ldFVx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x: u4 = opcode.iq2;
        const digit: u8 = self.registers[x];
        self.ir = @intCast(Chip8Memory.FONT_MEM_START + (5*digit));
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX29[8..11]);
            d.last_instruction = &d.I_0xFX29;
        }
    }

    // OPCODE: 0xFX33
    // Store the bcd representation of VX in memory addr I, I+1 and I+2, respc.
    fn ldBVx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x: u4 = opcode.iq2;
        var vx: u8 = self.registers[x];
        self.memory.loadAddr(self.ir + 2, vx % 10);
        vx /= 10;
        self.memory.loadAddr(self.ir + 1, vx % 10);
        vx /= 10;
        self.memory.loadAddr(self.ir, vx % 10);
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX33[8..11]);
            d.last_instruction = &d.I_0xFX33;
        }
    }

    // OPCODE: 0xFX55
    // Store regirsters V0..VX in memory, starting at I
    fn ldIV0Vx(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x: u4 = opcode.iq2;
        for (0..x) |i|{
            self.memory.loadAddr(self.ir + i, self.registers[i]);
        }
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX55[10..13]);
            d.last_instruction = &d.I_0xFX55;
        }
    }

    //OPCODE: 0xFX65
    // Read registers V0..VX from memory starting at I
    fn ldV0VxI(self: *Self, opcode: Opcode, dbg: ?*db.Debugger) void{
        const x: u4 = opcode.iq2;
        for (0..x) |i|{
            self.registers[i] = self.memory.getAdrr(self.ir + i);
        }
        if (dbg) |d|{
            utils.nibbleHex(x, d.I_0xFX65[5..8]);
            d.last_instruction = &d.I_0xFX65;
        }
    }
};

test "opcode"{
    const opcode: Opcode = @bitCast(@as(u16, 0x1234));
    try testing.expectEqual(opcode.lsq, 0x4);
    try testing.expectEqual(opcode.iq1, 0x3);
    try testing.expectEqual(opcode.iq2, 0x2);
    try testing.expectEqual(opcode.msq, 0x1);
    try testing.expectEqual(opcode.fetchAddr(), 0x0234);
    try testing.expectEqual(opcode.fetchByte(), 0x34);
}

test "emulation"{
    {
        const opcode: Opcode = @bitCast(@as(u16,0x00E0));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("CLS", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x00EE));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("RET", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x1234));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("JP 0x0234", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x2A1E));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("CALL 0x0A1E", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x31CE));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("SE V{0x1}, 0xCE", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x4321));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("SNE V{0x3}, 0x21", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x5820));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("SE V{0x8}, V{0x2}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x63CF));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("LD V{0x3}, 0xCF", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x717B));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("ADD V{0x1}, 0x7B", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x8AB0));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("LD V{0xA}, V{0xB}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x8041));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("OR V{0x0}, V{0x4}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x8A02));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("AND V{0xA}, V{0x0}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x87B3));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("XOR V{0x7}, V{0xB}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x89C4));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("ADD V{0x9}, V{0xC}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x8335));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("SUB V{0x3}, V{0x3}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x8676));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("SHR V{0x6}, V{0x7}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x8AC7));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("SUBN V{0xA}, V{0xC}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x808E));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("SHL V{0x0}, V{0x8}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0x9EC0));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("SNE V{0xE}, V{0xC}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xAEC7));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("LD I, 0x0EC7", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xBC00));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("JP V0, 0x0C00", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xC123));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("RND V{0x1}, 0x23", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xDC03));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("DRW V{0xC}, V{0x0}, 0x3", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xE09E));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("SKP V{0x0}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xE5A1));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("SKNP V{0x5}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF507));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("LD V{0x5}, DT", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF60A));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("LD V{0x6}, KEY", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF415));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("LD DT, V{0x4}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF818));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("LD ST, V{0x8}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF01E));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("ADD I, V{0x0}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF329));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("LD F, V{0x3}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF933));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("LD B, V{0x9}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xF255));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("LD [I], V{0x2}", dbg.last_instruction);
    }
    {
        const opcode: Opcode = @bitCast(@as(u16,0xFC55));
        var cpu: Chip8CPU = Chip8CPU.init();
        var dbg: db.Debugger = db.Debugger.init();
        try cpu.emulate(opcode, &dbg);
        try testing.expectEqualStrings("LD [I], V{0xC}", dbg.last_instruction);
    }
}
