const std = @import("std");
const testing = std.testing;

const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz01234567890+/";

// placeholder
pub fn encode(bytes: []const u8) i32 {
    for (bytes) |b| {
        std.debug.print("{d}\n", .{b});
    }
    return 0;
}

// encodeChunk reads bytes from one stream and writes the output to another
fn encodeStream(in: anytype, out: anytype) !usize {
    // Read up to 3 bytes at a time, resulting in 4 bytes of output
    var ibuf: [3]u8 = undefined;
    var obuf: [4]u8 = undefined;

    var chunk: u24 = undefined;

    var total_read: usize = 0;
    var bytes_read: usize = undefined;

    while (true) {
        bytes_read = try in.reader().readAll(&ibuf);
        if (bytes_read == 0) {
            break;
        }
        total_read += bytes_read;
        chunk = std.mem.readInt(u24, &ibuf, .big);

        // We read at least one byte, so we know the first two sextets have data
        obuf = [4]u8{
            encodeOffsetValue(chunk, 18),
            encodeOffsetValue(chunk, 12),
            if (bytes_read >= 2) encodeOffsetValue(chunk, 6) else '=',
            if (bytes_read == 3) encodeOffsetValue(chunk, 0) else '=',
        };

        try out.writer().writeAll(&obuf);
    }

    return total_read;
}

fn decodeStream(in: anytype, out: anytype) !usize {
    var ibuf: [4]u8 = undefined;
    var obuf: [3]u8 = undefined;
    var total_written: usize = 0;

    while (true) {
        const bytes_read = try in.reader().read(&ibuf);
        if (bytes_read == 0) {
            break;
        }
        if (bytes_read < 4) {
            return error.InvalidBase64Input;
        }

        // Convert each character to its corresponding index in the alphabet
        var chunk: u24 = 0;
        var padding_count: usize = 0;

        for (ibuf, 0..) |c, i| {
            if (c == '=') {
                padding_count += 1;
                continue;
            }
            // Characters after padding are invalid
            if (padding_count > 0) {
                return error.InvalidBase64Input;
            }

            const pos = std.mem.indexOfScalar(u8, alphabet, c) orelse return error.InvalidBase64Input;
            const index: u24 = @truncate(pos);

            // Shift the 6-bit value into the correct position in our 24-bit chunk.
            chunk |= @as(u24, index) << @truncate(18 - i * 6);
        }
        obuf = [_]u8{
            @truncate((chunk >> 16) & 0xFF),
            @truncate((chunk >> 8) & 0xFF),
            @truncate(chunk & 0xFF),
        };

        var bytes_to_write: usize = 3;
        if (ibuf[3] == '=') {
            bytes_to_write -= 1;
            if (ibuf[2] == '=') {
                bytes_to_write -= 1;
            }
        }
        try out.writer().writeAll(obuf[0..bytes_to_write]);
        total_written += bytes_to_write;
    }

    return total_written;
}
// encodeOffsetValue applies a bitmask to the chunk and returns the alphabet
// index for the resulting value.
fn encodeOffsetValue(chunk: u24, offset: anytype) u8 {
    const value: u24 = chunk & (0b111111 << offset);
    return alphabet[value >> offset];
}

test "encode chunk of 6 bytes" {
    var istream = std.io.fixedBufferStream("123456");

    var output: [4096]u8 = undefined;
    var ostream = std.io.fixedBufferStream(&output);

    const bytes_encoded = try encodeStream(&istream, &ostream);
    try testing.expectEqual(6, bytes_encoded);

    const expected = "MTIzNDU2";
    try std.testing.expectEqualStrings(expected, ostream.getWritten());
}

test "encode chunk of 3 bytes" {
    var istream = std.io.fixedBufferStream("123");

    var output: [4096]u8 = undefined;
    var ostream = std.io.fixedBufferStream(&output);

    const bytes_read = try encodeStream(&istream, &ostream);
    try testing.expectEqual(3, bytes_read);

    const expected = "MTIz";
    try std.testing.expectEqualStrings(expected, ostream.getWritten());
}

test "encode chunk of 7 bytes" {
    var istream = std.io.fixedBufferStream("1234567");

    var output: [4096]u8 = undefined;
    var ostream = std.io.fixedBufferStream(&output);

    const bytes_read = try encodeStream(&istream, &ostream);
    try testing.expectEqual(7, bytes_read);

    const expected = "MTIzNDU2Nz==";
    try std.testing.expectEqualStrings(expected, ostream.getWritten());
}

test "encode chunk of 8 bytes" {
    var istream = std.io.fixedBufferStream("12345678");

    var output: [4096]u8 = undefined;
    var ostream = std.io.fixedBufferStream(&output);

    const bytes_read = try encodeStream(&istream, &ostream);
    try testing.expectEqual(8, bytes_read);

    const expected = "MTIzNDU2Nzg=";
    try std.testing.expectEqualStrings(expected, ostream.getWritten());
}

test "decode chunk of 8 bytes" {
    var istream = std.io.fixedBufferStream("MTIzNDU2Nzg=");

    var output: [4096]u8 = undefined;
    var ostream = std.io.fixedBufferStream(&output);

    const bytes_written = try decodeStream(&istream, &ostream);
    try testing.expectEqual(8, bytes_written);

    const expected = "12345678";
    try std.testing.expectEqualStrings(expected, ostream.getWritten());
}

test "decode message" {
    var istream = std.io.fixedBufferStream("dGhpcyBpcyBhbiBlbmNvZGVkIG1lc3NhZ2UK");

    var output: [4096]u8 = undefined;
    var ostream = std.io.fixedBufferStream(&output);

    const expected = "this is an encoded message\n";

    const bytes_written = try decodeStream(&istream, &ostream);
    try testing.expectEqual(expected.len, bytes_written);

    try std.testing.expectEqualStrings(expected, ostream.getWritten());
}
