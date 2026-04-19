const std = @import("std");
const base64 = @import("base64_lib");

/// Adapts a `std.fs.File` for use with APIs that expect an object with a
/// parameterless `.reader()` method returning a `GenericReader`.
///
/// Unbuffered — each call through the GenericReader is a syscall. The encode
/// path therefore issues one read(2) per 3-byte input chunk. Acceptable for
/// interactive / small inputs; consider a buffering layer for bulk work.
const FileReaderAdapter = struct {
    file: std.fs.File,

    const ReadError = std.fs.File.ReadError;
    const Reader = std.io.GenericReader(*@This(), ReadError, readFn);

    fn readFn(self: *@This(), dest: []u8) ReadError!usize {
        return self.file.read(dest);
    }

    pub fn reader(self: *@This()) Reader {
        return .{ .context = self };
    }
};

/// Adapts a `std.fs.File` for use with APIs that expect an object with a
/// parameterless `.writer()` method returning a `GenericWriter`.
const FileWriterAdapter = struct {
    file: std.fs.File,

    const WriteError = std.fs.File.WriteError;
    const Writer = std.io.GenericWriter(*@This(), WriteError, writeFn);

    fn writeFn(self: *@This(), bytes: []const u8) WriteError!usize {
        return self.file.write(bytes);
    }

    pub fn writer(self: *@This()) Writer {
        return .{ .context = self };
    }
};

/// Writer adapter that inserts a newline every 76 bytes, matching the
/// line-wrapping behaviour of base64(1) per RFC 2045. Output is internally
/// buffered to avoid a syscall per encoded byte.
const LineWrappingWriter = struct {
    file: std.fs.File,
    col: usize = 0,
    buf: [4096]u8 = undefined,
    buf_len: usize = 0,

    const line_len = 76;
    const WriteError = std.fs.File.WriteError;
    const Writer = std.io.GenericWriter(*@This(), WriteError, writeFn);

    fn writeFn(self: *@This(), bytes: []const u8) WriteError!usize {
        for (bytes) |byte| {
            // Ensure room for a potential newline + the data byte.
            if (self.buf_len + 2 > self.buf.len) {
                try self.flush();
            }
            if (self.col >= line_len) {
                self.buf[self.buf_len] = '\n';
                self.buf_len += 1;
                self.col = 0;
            }
            self.buf[self.buf_len] = byte;
            self.buf_len += 1;
            self.col += 1;
        }
        return bytes.len;
    }

    pub fn flush(self: *@This()) WriteError!void {
        if (self.buf_len > 0) {
            try self.file.writeAll(self.buf[0..self.buf_len]);
            self.buf_len = 0;
        }
    }

    pub fn writer(self: *@This()) Writer {
        return .{ .context = self };
    }
};

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "base64: " ++ fmt ++ "\n", args) catch "base64: error\n";
    std.fs.File.stderr().writeAll(msg) catch {};
    std.process.exit(1);
}

pub fn main() !void {
    var decode_mode = false;

    var args = std.process.args();
    _ = args.skip(); // argv[0]
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--decode")) {
            decode_mode = true;
        } else {
            fatal("unrecognized option '{s}'", .{arg});
        }
    }

    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();

    if (decode_mode) {
        try decode(stdin, stdout);
    } else {
        try encode(stdin, stdout);
    }
}

fn encode(stdin: std.fs.File, stdout: std.fs.File) !void {
    var input = FileReaderAdapter{ .file = stdin };
    var wrapper = LineWrappingWriter{ .file = stdout };
    _ = try base64.encodeStream(&input, &wrapper);
    try wrapper.flush();
    if (wrapper.col > 0) {
        try stdout.writeAll("\n");
    }
}

fn decode(stdin: std.fs.File, stdout: std.fs.File) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Slurp all of stdin, then strip whitespace so that line-wrapped
    // base64 input (RFC 2045 / output of encode side) decodes correctly.
    const raw = try stdin.readToEndAlloc(allocator, 1 << 30);
    defer allocator.free(raw);

    // Strip whitespace in-place — bytes only shift left, so this is safe.
    var len: usize = 0;
    for (raw) |c| {
        switch (c) {
            ' ', '\t', '\n', '\r' => {},
            else => {
                raw[len] = c;
                len += 1;
            },
        }
    }

    var istream = std.io.fixedBufferStream(raw[0..len]);
    var output = FileWriterAdapter{ .file = stdout };
    _ = base64.decodeStream(&istream, &output) catch |err| switch (err) {
        error.InvalidBase64Input => fatal("invalid input", .{}),
        else => return err,
    };
}
