const std = @import("std");
const builtin = @import("builtin");
const Packer = @import("xopack").Packer;

const ArgsVector = []const [:0]const u8;

const ShiftError = error{InvalidArguments};

fn shiftArgs(args: *ArgsVector, message: []const u8) ShiftError![:0]const u8 {
    if (args.len == 0) {
        if (message.len > 0) {
            std.log.err("{s}", .{message});
            std.log.err("usage        : xopack {{[output spritesheet] [width] [height] [scale] [input images...] +}}", .{});
            std.log.err("usage example: xopack out1.png 1.0 1024 1024 a.png b.png + out2.png 1.0 1024 1024 b.png a.png", .{});
        }
        return ShiftError.InvalidArguments;
    }

    const arg = args.*[0];
    args.len -= 1;
    args.ptr += 1;

    return arg;
}

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.toSlice(init.arena.allocator());

    _ = try shiftArgs(&args, "");

    // ----------------------------------------------------------

    var packer = Packer.init(init.gpa);
    defer packer.deinit();

    // ----------------------------------------------------------

    var continue_parse = true;
    while (continue_parse) {
        const output = try shiftArgs(&args, "no output filename provided");
        const scale_str = try shiftArgs(&args, "no scale provided");
        const scale = try std.fmt.parseFloat(f32, scale_str);
        const width_str = try shiftArgs(&args, "no width provided");
        const width = try std.fmt.parseInt(i32, width_str, 10);
        const height_str = try shiftArgs(&args, "no height provided");
        const height = try std.fmt.parseInt(i32, height_str, 10);
        var filenames: std.ArrayList([:0]const u8) = try .initCapacity(init.arena.allocator(), 32);

        while (true) {
            const input = shiftArgs(&args, "") catch {
                continue_parse = false;
                break;
            };
            if (std.mem.eql(u8, input, "+")) {
                break;
            }
            try filenames.append(init.arena.allocator(), input);
        }

        const input: Packer.Input = .{
            .filenames = filenames.items,
            .output = output,
            .width = width,
            .height = height,
            .scale = scale,
        };
        try packer.addInput(input);
    }

    // ----------------------------------------------------------

    try packer.pack(init.io);
}
