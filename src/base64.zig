const std = @import("std");
const testing = std.testing;

const alphabet = [_]u8{ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '+', '/' };

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
