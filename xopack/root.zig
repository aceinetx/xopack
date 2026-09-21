const std = @import("std");

const stb = @import("stb");

pub const Packer = struct {
    pub const EmitterFunc = *const fn (userdata: *anyopaque, io: std.Io, filename: [:0]const u8, x: i32, y: i32, width: i32, height: i32) void;

    const PackError = error{
        StbiImageLoadFailed,
        StbrpPartiallyPacked,
        StbiOutputWriteFailed,
        UnsupportedNrChannels,
    };

    pub const Input = struct {
        filenames: []const [:0]const u8,
        output: [:0]const u8,
        width: i32 = 1024,
        height: i32 = 1024,
        scale: f32 = 1.0,
    };

    const AddInputError = error{InputAlreadyTaken};

    allocator: std.mem.Allocator,
    inputs: std.array_list.Managed(Input),
    emitter_mutex: std.Io.Mutex,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .inputs = .init(allocator),
            .emitter_mutex = .init,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.inputs.deinit();
    }

    /// Adds an input to the packer.
    /// Does not manage the strings - that's your thing.
    /// Input's strings must remain valid after pack() call.
    ///
    /// Not threadsafe.
    pub fn addInput(
        self: *@This(),
        input: Input,
    ) !void {
        // Check if an output filename is already taken
        for (self.inputs.items) |*i| {
            if (std.mem.eql(u8, i.output, input.output)) {
                return AddInputError.InputAlreadyTaken;
            }
        }
        try self.inputs.append(input);
    }

    /// Packs an input.
    ///
    /// Threadsafe.
    fn packInput(self: *@This(), io: std.Io, input: *const Input, emitter: ?EmitterFunc, emitter_userdata: *anyopaque) !void {
        const FileData = struct {
            data: []u8,
            name: [:0]const u8,
            width: c_int,
            height: c_int,
            nr_channels: c_int,
        };

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        var allocator = arena.allocator();
        defer arena.deinit();

        var files: std.array_list.Managed(FileData) = .init(allocator);
        defer {
            for (files.items) |file| {
                allocator.free(file.data);
            }
            files.deinit();
        }

        // Load all the files
        for (input.filenames) |file| {
            var w: c_int = undefined;
            var h: c_int = undefined;
            var nr_channels: c_int = undefined;
            const data = stb.stbi_load(file.ptr, &w, &h, &nr_channels, 0);
            if (data == null) return PackError.StbiImageLoadFailed;
            if (nr_channels != 3 and nr_channels != 4) return PackError.UnsupportedNrChannels;
            const w_unscaled = w;
            const h_unscaled = h;
            // Scale the sizes
            const wf: f32 = @floatFromInt(w);
            const hf: f32 = @floatFromInt(h);
            w = @intFromFloat(wf * input.scale);
            h = @intFromFloat(hf * input.scale);
            // Resize the image
            const output = try allocator.alloc(u8, @intCast(w * h * nr_channels));

            const pixel_type: stb.stbir_pixel_layout = switch (nr_channels) {
                3 => stb.STBIR_RGB,
                4 => stb.STBIR_RGBA,
                else => unreachable,
            };
            _ = stb.stbir_resize_uint8_linear(data, w_unscaled, h_unscaled, w_unscaled * nr_channels, output.ptr, w, h, w * nr_channels, pixel_type);

            // Free the old image
            stb.stbi_image_free(data);

            try files.append(.{
                .data = output,
                .name = file,
                .width = w,
                .height = h,
                .nr_channels = nr_channels,
            });
            std.debug.print("[{s}] loaded: {s} (w = {}, h = {}, nr_channels = {})\n", .{
                input.output,
                file,
                w,
                h,
                nr_channels,
            });
        }

        // Pack rectangles
        var rects: std.array_list.Managed(stb.stbrp_rect) = .init(allocator);
        defer rects.deinit();

        for (0.., files.items) |i, *file| {
            try rects.append(.{
                .id = @intCast(i),
                .w = file.width,
                .h = file.height,
            });
        }

        var ctx: stb.stbrp_context = undefined;
        var nodes: [256]stb.stbrp_node = undefined;
        stb.stbrp_init_target(&ctx, input.width, input.height, &nodes, nodes.len);

        const rect_count: c_int = @intCast(rects.items.len);
        if (stb.stbrp_pack_rects(&ctx, rects.items.ptr, rect_count) == 0)
            return PackError.StbrpPartiallyPacked;

        for (rects.items) |*rect| {
            std.debug.print("[{s}] packed: {s} ({} {} {})\n", .{
                input.output,
                files.items[@intCast(rect.id)].name,
                rect.x,
                rect.y,
                rect.was_packed,
            });
            std.debug.assert(rect.was_packed == 1);
        }

        // Write the final spritesheet
        const data = try allocator.alloc(u8, @intCast(input.width * input.height * 4));
        defer allocator.free(data);

        @memset(data, 0);

        for (rects.items) |*rect| {
            const file = &files.items[@intCast(rect.id)];
            std.debug.print("[{s}] writing: {s}\n", .{ input.output, file.name });

            // Call emitter if there is one
            if (emitter) |f| {
                try self.emitter_mutex.lock(io);
                f(emitter_userdata, io, file.name, rect.x, rect.y, rect.w, rect.h);
                self.emitter_mutex.unlock(io);
            }

            for (0..@intCast(file.width * file.height)) |i| {
                const ii: c_int = @intCast(i);
                const x = rect.x + @rem(ii, file.width);
                const y = rect.y + @divTrunc(ii, file.width);
                const base: usize = @intCast((y * input.width + x) * 4);

                switch (file.nr_channels) {
                    3 => {
                        const pixel: []u8 = file.data[(i * 3)..(i * 3 + 3)];

                        data[base] = pixel[0];
                        data[base + 1] = pixel[1];
                        data[base + 2] = pixel[2];
                        data[base + 3] = 255;
                    },
                    4 => {
                        const pixel: []u8 = file.data[(i * 4)..(i * 4 + 4)];

                        data[base] = pixel[0];
                        data[base + 1] = pixel[1];
                        data[base + 2] = pixel[2];
                        data[base + 3] = pixel[3];
                    },
                    else => unreachable,
                }
            }
        }

        if (stb.stbi_write_png(input.output, input.width, input.height, 4, data.ptr, input.width * 4) == 0)
            return PackError.StbiOutputWriteFailed;
        std.debug.print("[{s}] done\n", .{input.output});
    }

    /// Worker for packInput, handles errors.
    fn packInputWorker(self: *@This(), io: std.Io, input: *const Input, emitter: ?EmitterFunc, emitter_userdata: *anyopaque) void {
        self.packInput(io, input, emitter, emitter_userdata) catch |err| {
            std.debug.print("[{s}] error: {}\n", .{
                input.output,
                err,
            });
        };
    }

    /// Packs the inputs with an emitter. Locks the emitter function with a
    /// mutex, so you're safe to write to emitter_userdata in the emitter
    /// function.
    /// After packing removes all inputs.
    ///
    /// Not threadsafe.
    pub fn packWithEmitter(self: *@This(), io: std.Io, emitter: ?EmitterFunc, emitter_userdata: *anyopaque) !void {
        var g = std.Io.Group.init;
        errdefer g.cancel(io);

        for (self.inputs.items) |*input| {
            g.async(io, @This().packInputWorker, .{ self, io, input, emitter, emitter_userdata });
        }
        try g.await(io);
        self.inputs.clearRetainingCapacity();
    }

    /// Packs the inputs.
    /// After packing removes all inputs.
    ///
    /// Not threadsafe.
    pub fn pack(self: *@This(), io: std.Io) !void {
        try self.packWithEmitter(io, null, undefined);
    }
};
