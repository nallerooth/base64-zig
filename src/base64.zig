const std = @import("std");
const testing = std.testing;

const alphabet = [_]u8{ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '+', '/' };

pub fn encode(bytes: []const u8) i32 {
    for (bytes) |b| {
        std.debug.print("{d}\n", .{b});
    }
    return 0;
}

// Use the whole data array.
// Extract the first six bits into an u6.
// Step to the next six bits, loop/
// Pad with zero bits at the end, if needed
//
// Add support for streaming of data
// Separate function with reader and writer
fn split(bytes: []const u8) []u6 {
    // We need to keep track of which byte we're reading and the offset inside
    // that byte. We also need to move the "window" (slice) and update the bit
    // mask for each step.
    for (bytes) |b| {
        _ = b;
    }

    return []u6{};
}

fn extractFirstSixBits(byte: u8) u8 {
    return 0b11111100 & byte;
}

fn encodeChunk(in: anytype, out: anytype) !usize {
    // Work with 48 bits for now, as that'e divisible by both 6 and 8
    var ibuf: [6]u8 = undefined;
    var obuf: [8]u8 = undefined;

    const readBytes = try in.reader().readAll(&ibuf);
    std.debug.assert(readBytes == 6);

    const chunk: u48 = std.mem.readInt(u48, &ibuf, .big);

    var mask: u48 = 0b111111 << 42;
    var i: u6 = 7;
    var value: u48 = undefined;
    while (i >= 0) {
        value = (chunk & mask) >> (6 * i);
        obuf[7 - i] = alphabet[value];
        mask = mask >> 6;
        if (i == 0) {
            break;
        }
        i -= 1;
        std.debug.print("\n", .{});
    }

    try out.writer().writeAll(&obuf);

    return readBytes;
}

test "encode chunk of 6 bytes" {
    const input = "123456";
    var istream = std.io.fixedBufferStream(input);

    var output: [4096]u8 = undefined;
    var ostream = std.io.fixedBufferStream(&output);

    const bytes_encoded = try encodeChunk(&istream, &ostream);
    try testing.expectEqual(6, bytes_encoded);

    const expected = "MTIzNDU2";
    try std.testing.expectEqualStrings(expected, ostream.getWritten());
}
