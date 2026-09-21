const std = @import("std");
const builtin = @import("builtin");
const Packer = @import("xopack").Packer;

var i: usize = 0;

fn emitter(userdata: *anyopaque, io: std.Io, filename: [:0]const u8, x: i32, y: i32, width: i32, height: i32) void {
    _ = .{ userdata, io, filename, x, y, width, height };
    i += 1;
}

pub fn main(init: std.process.Init) !void {
    var packer = Packer.init(init.gpa);
    try packer.addInput(.{
        .filenames = &.{ "lionbee.png", "shit.png", "yt.png", "yt.png", "yt.png", "yt.png" },
        .output = "output.png",
        .scale = 1.17,
    });

    try packer.packWithEmitter(init.io, emitter, undefined);
    std.debug.print("rects: {}\n", .{i});

    defer packer.deinit();
}
