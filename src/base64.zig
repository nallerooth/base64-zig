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
fn encodeChunk(in: anytype, out: anytype) !usize {
    // Work with 48 bits for now, as that'e divisible by both 6 and 8
    var ibuf: [3]u8 = undefined;
    var obuf: [4]u8 = undefined;
    var totalRead: usize = 0;
    var readBytes: usize = undefined;
    var value: u24 = undefined;
    var chunk: u24 = undefined;

    while (true) {
        readBytes = try in.reader().readAll(&ibuf);
        if (readBytes == 0) {
            break;
        }
        totalRead += readBytes;
        chunk = std.mem.readInt(u24, &ibuf, .big);

        // Skip loop as there are just four values to process
        if (readBytes > 0) {
            value = chunk & (0b111111 << 18);
            obuf[0] = alphabet[value >> 18];
        }

        if (readBytes > 1) {
            value = chunk & (0b111111 << 12);
            obuf[1] = alphabet[value >> 12];
        }

        if (readBytes > 2) {
            value = chunk & (0b111111 << 6);
            obuf[2] = alphabet[value >> 6];

            value = chunk & (0b111111);
            obuf[3] = alphabet[value];
        }

        try out.writer().writeAll(&obuf);
    }

    return totalRead;
}

test "encode chunk of 6 bytes" {
    var istream = std.io.fixedBufferStream("123456");

    var output: [4096]u8 = undefined;
    var ostream = std.io.fixedBufferStream(&output);

    const bytes_encoded = try encodeChunk(&istream, &ostream);
    try testing.expectEqual(6, bytes_encoded);

    const expected = "MTIzNDU2";
    try std.testing.expectEqualStrings(expected, ostream.getWritten());
}

test "encode chunk of 3 bytes" {
    var istream = std.io.fixedBufferStream("123");

    var output: [4096]u8 = undefined;
    var ostream = std.io.fixedBufferStream(&output);

    const bytes_read = try encodeChunk(&istream, &ostream);
    try testing.expectEqual(3, bytes_read);

    const expected = "MTIz";
    try std.testing.expectEqualStrings(expected, ostream.getWritten());
}
