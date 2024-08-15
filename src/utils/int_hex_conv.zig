const testing = @import("std").testing;

fn nibbleCharHex(nibble: u4, result: []u8) void{
    return switch (nibble) {
        0x0 => result[0] = '0',
        0x1 => result[0] = '1',
        0x2 => result[0] = '2',
        0x3 => result[0] = '3',
        0x4 => result[0] = '4',
        0x5 => result[0] = '5',
        0x6 => result[0] = '6',
        0x7 => result[0] = '7',
        0x8 => result[0] = '8',
        0x9 => result[0] = '9',
        0xA => result[0] = 'A',
        0xB => result[0] = 'B',
        0xC => result[0] = 'C',
        0xD => result[0] = 'D',
        0xE => result[0] = 'E',
        0xF => result[0] = 'F',
    };
}

pub fn nibbleHex(nibble: u4, result: []u8) void{
    result[0] = '0';
    result[1] = 'x';
    nibbleCharHex(nibble,result.ptr[2..3]);
}

pub fn byteHex(byte: u8, result: []u8) void{
    result[0] = '0';
    result[1] = 'x';
    const x: u4 = @intCast((byte >> 4) & 0xF);
    const y: u4 = @intCast(byte & 0xF);
    nibbleCharHex(x, result.ptr[2..3]);
    nibbleCharHex(y, result.ptr[3..4]);
}

pub fn u16Hex(num: u16, result: []u8) void{
    const x: u4 = @intCast(num >> 12 & 0xF);
    const y: u4 = @intCast(num >> 8 & 0xF);
    const w: u4 = @intCast(num >> 4 & 0xF);
    const z: u4 = @intCast(num & 0xF);
    result[0] = '0';
    result[1] = 'x';
    nibbleCharHex(x, result.ptr[2..3]);
    nibbleCharHex(y, result.ptr[3..4]);
    nibbleCharHex(w, result.ptr[4..5]);
    nibbleCharHex(z, result.ptr[5..6]);
}

test "nibble"{
    {
        const nibble: u4 = 0x0;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', '0'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0x1;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', '1'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0x2;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', '2'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0x3;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', '3'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0x4;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', '4'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0x5;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', '5'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0x6;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', '6'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0x7;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', '7'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0x8;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', '8'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0x9;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', '9'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0xA;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', 'A'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0xB;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', 'B'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0xC;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', 'C'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0xD;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', 'D'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0xE;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', 'E'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const nibble: u4 = 0xF;
        var result: [3]u8 = undefined;
        nibbleHex(nibble, &result);
        const expected: [3]u8 = [_]u8{'0', 'x', 'F'};
        try testing.expectEqualSlices(u8, &expected, &result);
    }
}

test "byte"{
    {
        const byte: u8 = 0xAB;
        var result: [4]u8 = undefined;
        const expected: [4]u8 = [_]u8{'0', 'x', 'A', 'B'};
        byteHex(byte, &result);
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const byte: u8 = 0x11;
        var result: [4]u8 = undefined;
        const expected: [4]u8 = [_]u8{'0', 'x', '1', '1'};
        byteHex(byte, &result);
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const byte: u8 = 0x5F;
        var result: [4]u8 = undefined;
        const expected: [4]u8 = [_]u8{'0', 'x', '5', 'F'};
        byteHex(byte, &result);
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const byte: u8 = 0xC7;
        var result: [4]u8 = undefined;
        const expected: [4]u8 = [_]u8{'0', 'x', 'C', '7'};
        byteHex(byte, &result);
        try testing.expectEqualSlices(u8, &expected, &result);
    }
}

test "u16"{
    {
        const num: u16 = 0xA12F;
        var result: [6]u8 = undefined;
        const expected: [6]u8 = [_]u8{'0', 'x', 'A', '1', '2', 'F'};
        u16Hex(num, &result);
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const num: u16 = 0x1234;
        var result: [6]u8 = undefined;
        const expected: [6]u8 = [_]u8{'0', 'x', '1', '2', '3', '4'};
        u16Hex(num, &result);
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const num: u16 = 0xABCD;
        var result: [6]u8 = undefined;
        const expected: [6]u8 = [_]u8{'0', 'x', 'A', 'B', 'C', 'D'};
        u16Hex(num, &result);
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const num: u16 = 0x5A4F;
        var result: [6]u8 = undefined;
        const expected: [6]u8 = [_]u8{'0', 'x', '5', 'A', '4', 'F'};
        u16Hex(num, &result);
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const num: u16 = 0xFFFF;
        var result: [6]u8 = undefined;
        const expected: [6]u8 = [_]u8{'0', 'x', 'F', 'F', 'F', 'F'};
        u16Hex(num, &result);
        try testing.expectEqualSlices(u8, &expected, &result);
    }
    {
        const num: u16 = 0xB77C;
        var result: [6]u8 = undefined;
        const expected: [6]u8 = [_]u8{'0', 'x', 'B', '7', '7', 'C'};
        u16Hex(num, &result);
        try testing.expectEqualSlices(u8, &expected, &result);
    }
}
