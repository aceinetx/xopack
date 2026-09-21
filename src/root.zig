const std = @import("std");
const builtin = @import("builtin");
const Packer = @import("xopack").Packer;

var i: usize = 0;

fn emitter(userdata: *anyopaque, io: std.Io, filename: [:0]const u8, x: i32, y: i32, width: i32, height: i32) void {
    _ = .{ userdata, io, filename, x, y, width, height };
    i += 1;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len <= 3) {
        std.log.err("not enough arguments", .{});
        std.log.err("usage: {s} [output spritesheet] [scale] [input images...]", .{args[0]});
        return;
    }

    var packer = Packer.init(init.gpa);
    defer packer.deinit();

    try packer.addInput(.{
        .filenames = args[3..],
        .output = args[1],
        .scale = try std.fmt.parseFloat(f32, args[2]),
    });

    try packer.packWithEmitter(init.io, emitter, undefined);
    std.debug.print("rects: {}\n", .{i});
}
