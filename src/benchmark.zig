const Benchmark = @This();
const std = @import("std");

const fs = std.fs;
const io = std.io;
const math = std.math;
const mem = std.mem;
const process = std.process;
const time = std.time;

////////////////////////////////////////////////////////////////////////////////

stderr: struct {
    out_stream: fs.File.OutStream,
    stream: *fs.File.OutStream.Stream,
},
stdout: struct {
    out_stream: fs.File.OutStream,
    stream: *fs.File.OutStream.Stream,
},

arena_storage: std.heap.ArenaAllocator,
arena: *std.mem.Allocator,
name: []const u8,
exename: []const u8,
pathname: []const u8,
atoms: std.ArrayList(Atom),
case_set: std.AutoHashMap(u8, void),
case_order: std.ArrayList(u8),
magnify: usize,
rand_size: usize,
repeat: usize,
uverbose: u2,
padded_data: []u8,
data: []u8,

const Mode = enum {
    Help,
    ListCases,
    Perform,
};

mode: Mode,

////////////////////////////////////////////////////////////////////////////////

fn make(allocator: *std.mem.Allocator, name: []const u8) !*Benchmark {
    const p = try allocator.create(Benchmark);
    try Benchmark.init(p, allocator, name);
    return p;
}

fn init(self: *Benchmark, allocator: *std.mem.Allocator, name: []const u8) !void {
    self.stderr.out_stream = (try io.getStdErr()).outStream();
    self.stderr.stream = &self.stderr.out_stream.stream;

    self.stdout.out_stream = (try io.getStdOut()).outStream();
    self.stdout.stream = &self.stdout.out_stream.stream;

    self.arena_storage = std.heap.ArenaAllocator.init(allocator);
    self.arena = &self.arena_storage.allocator;
    self.name = try mem.dupe(self.arena, u8, name);
    self.exename = "(unknown-executable)"[0..];
    self.pathname = [_]u8{};
    self.atoms = @typeOf(self.atoms).init(self.arena);
    self.case_set = std.AutoHashMap(u8, void).init(self.arena);
    self.case_order = std.ArrayList(u8).init(self.arena);
    self.magnify = 1;
    self.rand_size = 1;
    self.repeat = 1;
    self.uverbose = 1;
    self.data = [_]u8{};
    self.mode = Mode.Perform;
}

fn deinit(self: *Benchmark) void {
    self.arena_storage.deinit();
}

////////////////////////////////////////////////////////////////////////////////

fn out(self: Benchmark, comptime fmt: []const u8, args: ...) !void {
    if (self.uverbose < 1) return;
    try self.stdout.stream.print(fmt, args);
}

fn wout(self: Benchmark, comptime fmt: []const u8, args: ...) !void {
    if (self.uverbose < 1) return;
    try self.stdout.stream.print("warning: " ++ fmt, args);
}

fn vout(self: Benchmark, verbosity: u2, comptime fmt: []const u8, args: ...) !void {
    if (self.uverbose < verbosity) return;
    try self.stdout.stream.print(fmt, args);
}

fn eout(self: Benchmark, comptime fmt: []const u8, args: ...) !void {
    try self.stderr.stream.print(fmt, args);
}

fn outPadText(self: Benchmark, text: []const u8, width: u8, right: bool, fill: u8) !void {
    if (self.uverbose < 1) return;
    const padw = if (text.len > width) 0 else width - text.len;
    if (right) {
        var i: u8 = 0;
        while (i < padw) : (i += 1) {
            try self.stdout.stream.print("{c}", fill);
        }
        try self.stdout.stream.print("{}", text);
    } else {
        try self.stdout.stream.print("{}", text);
        var i: u8 = 0;
        while (i < padw) : (i += 1) {
            try self.stdout.stream.print("{c}", fill);
        }
    }
}

////////////////////////////////////////////////////////////////////////////////

const SOF = enum {
    Success,
    Failure,
};

pub fn main() !void {
    const result = main_init: {
        var heap = std.heap.DirectAllocator.init();
        defer heap.deinit();

        var bm = try Benchmark.make(&heap.allocator, "UTF-8 decoder");
        defer bm.deinit();

        break :main_init try bm.run();
    };
    process.exit(switch (result) {
        .Success => u8(0),
        .Failure => u8(1),
    });
}

pub const Atom = struct {
    pub const Error = error{SpinFailure};

    name: []const u8,
    descr: []const u8,
    spin: fn (self: *Atom, bm: Benchmark, counters: *Counters, magnify: usize) Error!void,
};

pub const Counters = struct {
    elapsed_s: f64,
    num_bytes: u64,
    num_codepoints: u64,
    num_errors: u64,

    fn make() Counters {
        return Counters{
            .elapsed_s = 0.0,
            .num_bytes = 0,
            .num_codepoints = 0,
            .num_errors = 0,
        };
    }

    fn reset(self: *Counters) void {
        self.elapsed_s = 0.0;
        self.num_bytes = 0;
        self.num_codepoints = 0;
        self.num_errors = 0;
    }

    fn accumulate(self: *Counters, other: Counters) void {
        self.elapsed_s += other.elapsed_s;
        self.num_bytes += other.num_bytes;
        self.num_codepoints += other.num_codepoints;
        self.num_errors += other.num_errors;
    }
};

////////////////////////////////////////////////////////////////////////////////

const case_options = "0123456789"[0..atom_bnames.len];
const usage_text = "usage: {} [-" ++ case_options ++ "hl] [-mrsv] [file]";

const help_text =
    \\ Benchmark for various UTF-8 decoder implementations.
    \\
    \\ -#      select benchmark case to perform (default: all)
    \\ -m num  magnify data num-times within block (default: 1)
    \\ -r num  repeat benchmark block num-times (default: 1)
    \\ -s num  generate num MiB of random data (default: 1)
    \\ -v      increase verbosity
    \\ -l      list available benchmark cases and exit
    \\ -h      display this help and exit
;

fn usage(self: Benchmark) !void {
    try self.out(usage_text ++ "\n\n{}\n", self.exename, help_text);
}

fn usageError(self: Benchmark, index: usize, comptime fmt: []const u8, args: ...) !void {
    try self.eout("error for argument:{}: " ++ fmt ++ "\n\n" ++ usage_text ++ "\n", index, args, self.exename);
    return error.Usage;
}

fn run(self: *Benchmark) !SOF {
    self.parse_command() catch |err| return switch (err) {
        error.Usage => SOF.Failure,
        else => err,
    };

    if (self.magnify < 1) {
        self.magnify = 1;
    }
    if (self.rand_size < 1) {
        self.rand_size = 1;
    }
    if (self.repeat < 1) {
        self.repeat = 1;
    }

    // add all cases unless selected on command-line
    // kind of an ugly way to use comptime
    if (self.case_order.count() == 0) {
        inline for (atom_bnames) |bname| {
            const source = "atom." ++ bname ++ ".zig";
            const module = @import(source);
            var atom = try self.atoms.addOne();
            atom.name = bname;
            atom.spin = module.spin;
            atom.descr = module.descr;
        }
    } else {
        var it = self.case_order.iterator();
        while (it.next()) |case_index| {
            inline for (atom_bnames) |bname, i| {
                if (i == case_index) {
                    const source = "atom." ++ bname ++ ".zig";
                    const module = @import(source);
                    var atom = try self.atoms.addOne();
                    atom.name = bname;
                    atom.spin = module.spin;
                    atom.descr = module.descr;
                }
            }
        }
    }

    switch (self.mode) {
        .Help => {
            try self.usage();
            return SOF.Success;
        },
        .ListCases => {
            if (self.uverbose < 2) {
                try self.listCases(false);
            } else {
                try self.listCases(true);
            }
            return SOF.Success;
        },
        .Perform => {},
    }

    if (self.pathname.len == 0) {
        try self.generateData();
    } else {
        if ((try self.readData()) != SOF.Success) return SOF.Failure;
    }

    var it = self.atoms.iterator();
    while (it.next()) |*atom| {
        try self.spinAtom(atom);
    }

    return SOF.Success;
}

fn parse_command(self: *Benchmark) !void {
    var args = process.args();
    self.exename = try args.next(self.arena) orelse {
        return self.usageError(0, "unable to access command-line");
    };

    var pathname_index: usize = 0;
    var index: usize = 1;
    while (true) : (index += 1) {
        var arg = try args.next(self.arena) orelse break;
        if (arg.len == 0) {
            return self.usageError(index, "empty value");
        }
        if (arg[0] != '-') {
            if (pathname_index > 0) {
                return self.usageError(index, "file already specified @index:{}", pathname_index);
            }
            self.pathname = arg;
            pathname_index = index;
            continue;
        }
        var content = arg[1..];

        // detect unsupported use of arg stdin "-"
        if (content.len == 0) return self.usageError(index, "unsupported: read from stdin");

        // long options
        if (content[0] == '-') {
            content = content[1..];

            // detect unsupported use of args handoff "--"
            if (content.len == 0) return self.usageError(index, "unsupported: argument processing handoff");

            if (mem.eql(u8, content, "help")) {
                self.mode = Mode.Help;
                return;
            }
            return self.usageError(index, "unrecognized option '{}'", arg);
        }

        // single-hyphen processing (may be standalone or combinatory)
        const cx_end = '0' + atom_bnames.len;
        for (content) |c| {
            if (c >= '0' and c <= '9') {
                if (c >= cx_end) return self.usageError(index, "case option '{c}' out of range", c);
                const case_index = c - '0';
                // silently ignore redundant selections
                if (self.case_set.get(case_index) == null) {
                    _ = try self.case_set.put(case_index, {});
                    try self.case_order.append(case_index);
                }
                continue;
            }
            switch (c) {
                'h' => {
                    self.mode = Mode.Help;
                },
                'l' => {
                    self.mode = Mode.ListCases;
                },
                'm' => {
                    arg = try args.next(self.arena) orelse {
                        return self.usageError(index, "missing argument");
                    };
                    self.magnify = toUnsigned(arg) catch {
                        return self.usageError(index, "invalid magnify number '{}'", arg);
                    };
                },
                'r' => {
                    arg = try args.next(self.arena) orelse {
                        return self.usageError(index, "missing argument");
                    };
                    self.repeat = toUnsigned(arg) catch {
                        return self.usageError(index, "invalid repeat number '{}'", arg);
                    };
                },
                's' => {
                    arg = try args.next(self.arena) orelse {
                        return self.usageError(index, "missing argument");
                    };
                    self.rand_size = toUnsigned(arg) catch {
                        return self.usageError(index, "invalid random buffer size '{}'", arg);
                    };
                },
                'v' => {
                    if (self.uverbose != std.math.maxInt(@typeOf(self.uverbose))) self.uverbose += 1;
                },
                else => {
                    return self.usageError(index, "unrecognized option '{}'", arg);
                },
            }
        }
    }
}

const atom_bnames = [_][]const u8{
    "hoehrmann",
    "mikdusan.0",
    "mikdusan.1",
    "mikdusan.2",
    "std.unicode",
    "wellons.branchless",
    "wellons.simple",
};

fn splitLines(bytes: []const u8, lines: *std.ArrayList([]const u8)) !void {
    var begin: usize = 0;
    var end: usize = 0;
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        switch (bytes[i]) {
            '\n' => {
                try lines.append(bytes[begin..end]);
                i += 1;
                begin = i;
                end = i;
            },
            else => {
                end = i + 1;
            },
        }
    } else if (end > begin) {
        try lines.append(bytes[begin..end]);
    }
}

fn listCases(self: Benchmark, verbose: bool) !void {
    // calculate hline for column 2
    const col2heading = "Benchmark Case";
    var c2width: usize = col2heading.len;
    const Lines = std.ArrayList([]const u8);
    var lines: Lines = undefined;
    if (verbose) {
        lines = Lines.init(self.arena);
        var it = self.atoms.iterator();
        while (it.next()) |atom| {
            try lines.resize(0);
            try splitLines(atom.descr, &lines);
            var jt = lines.iterator();
            while (jt.next()) |line| {
                if (line.len > c2width) c2width = line.len;
            }
        }
    } else {
        var it = self.atoms.iterator();
        while (it.next()) |atom| {
            if (atom.name.len > c2width) c2width = atom.name.len;
        }
    }

    try self.out("  ##  Benchmark Case\n");
    var it = self.atoms.iterator();
    while (it.next()) |atom| {
        if (verbose or it.count == 1) {
            try self.out("  --  ");
            try self.outPadText("", @truncate(u8, c2width), false, '-');
            try self.out("\n");
        }

        const width = indexForUnit(it.count - 1, 10);
        const padw = if (width < 3) 3 - width else 0;
        try self.outPadText("", padw, false, ' ');
        try self.out("{}  {}\n", it.count - 1, atom.name);

        if (!verbose) continue;
        try lines.resize(0);
        try splitLines(atom.descr, &lines);
        var jt = lines.iterator();
        while (jt.next()) |line| {
            try self.out("      {}\n", line);
        }
    }
}

fn generateData(self: *Benchmark) !void {
    // pad end-of-buffer
    // some benchmarks read 4-byets at a time so we'll just pad by 16
    const size = 1024 * 1024 * self.rand_size;
    try self.out("generating {} random UTF-8 test data...\n", auto_b(size));
    self.padded_data = try self.arena.alloc(u8, size + pad_size);
    self.data = self.padded_data[0..size];
    std.rand.DefaultPrng.init(0).random.bytes(self.data);
}

fn readData(self: *Benchmark) !SOF {
    var file = fs.File.openRead(self.pathname) catch |err| {
        try self.eout("unable to read file '{}': {}\n", self.pathname, err);
        return SOF.Failure;
    };
    defer file.close();

    const size = try file.getEndPos();
    // pad end-of-buffer
    // some benchmarks read 4-byets at a time so we'll just pad by 16
    try self.out("reading {} UTF-8 test data '{}'...\n", auto_b(size), self.pathname);
    self.padded_data = try self.arena.alignedAlloc(u8, mem.page_size, size + pad_size);
    self.data = self.padded_data[0..size];

    var adapter = file.inStream();
    try adapter.stream.readNoEof(self.data[0..size]);
    return SOF.Success;
}

fn spinAtom(self: *Benchmark, atom: *Atom) !void {
    var total = Counters.make();
    var interval: Counters = undefined;

    try self.out("benchmark: {}", atom.name);
    try self.outPadText(" ", 65, false, '-');
    try self.out("\n");
    if (atom.descr.len != 0) try self.vout(2, "\n{}\n\n", atom.descr);

    var timer = try time.Timer.start();
    var rindex: usize = 0;
    while (rindex < self.repeat) : (rindex += 1) {
        self.zeroPadData();
        interval.reset();
        const start = timer.lap();
        atom.spin(atom, self.*, &interval, self.magnify) catch |err| {
            try self.wout("aborting benchmark\n");
            break;
        };
        const end = timer.lap();
        interval.elapsed_s = if (start > end) 0 else (@intToFloat(f64, end - start) / time.ns_per_s);
        total.accumulate(interval);

        try self.out("  ::  {}, {} data, {} codepoints, {} errors\n", auto_bs(interval.num_bytes, interval.elapsed_s), auto_b(interval.num_bytes), auto_n(interval.num_codepoints), auto_n(interval.num_errors));
    }
    try self.out("\n" ++
        \\  average rate:           {}
        \\  total UTF8 data:        {}
        \\  total UTF8 codepoints:  {}
        \\  total UTF8 errors:      {}
    ++ "\n\n", auto_bs(total.num_bytes, total.elapsed_s), auto_b(total.num_bytes), auto_n(total.num_codepoints), auto_n(total.num_errors));
}

const pad_size: usize = 16;

fn zeroPadData(self: *Benchmark) void {
    mem.set(u8, self.padded_data[self.padded_data.len - pad_size ..], 0);
}

////////////////////////////////////////////////////////////////////////////////

fn toUnsigned(bytes: []const u8) !usize {
    const width = r: {
        var width: usize = bytes.len;
        for (bytes) |c, i| {
            if (c < '0' or c > '9') {
                width = i;
                break;
            }
        }
        break :r width;
    };
    if (width != bytes.len) {
        return error.InvalidUnsigned;
    }
    var result: usize = 0;
    for (bytes[0..width]) |c, i| {
        const exp = bytes.len - i - 1;
        result += (c - '0') * (std.math.powi(usize, 10, width - i - 1) catch 0);
    }
    return result;
}

////////////////////////////////////////////////////////////////////////////////

fn indexForUnit(value: usize, div: usize) u8 {
    if (value == 0) return 0;
    return @floatToInt(u8, math.floor(math.log2(@intToFloat(f64, value)) / math.log2(@intToFloat(f64, div))));
}

fn auto_n(value: usize) ValueUnit {
    const unit = decimal_units[indexForUnit(value, 1000)];
    return ValueUnit{
        .value = @intToFloat(f64, value) / @intToFloat(f64, unit.div),
        .prec = unit.prec,
        .unit = unit.single,
        .rate = "",
    };
}

fn auto_d(value: usize) ValueUnit {
    const unit = decimal_units[indexForUnit(value, 1000)];
    return ValueUnit{
        .value = @intToFloat(f64, value) / @intToFloat(f64, unit.div),
        .prec = unit.prec,
        .unit = unit.double,
        .rate = "",
    };
}

fn auto_b(value: usize) ValueUnit {
    const unit = binary_units[indexForUnit(value, 1024)];
    return ValueUnit{
        .value = @intToFloat(f64, value) / @intToFloat(f64, unit.div),
        .prec = unit.prec,
        .unit = unit.triple,
        .rate = "",
    };
}

fn auto_bs(value: usize, elapsed: f64) ValueUnit {
    const rate = if (elapsed > 0) (@intToFloat(f64, value) / elapsed) else 0;
    const unit = binary_units[indexForUnit(@floatToInt(usize, rate), 1024)];
    return ValueUnit{
        .value = rate / @intToFloat(f64, unit.div),
        .prec = unit.prec,
        .unit = unit.triple,
        .rate = "/s",
    };
}

const ValueUnit = struct {
    value: f64,
    prec: u2,
    unit: []const u8,
    rate: []const u8,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        switch (self.prec) {
            0 => {
                try std.fmt.format(context, Errors, output, "{}{}{}", @floatToInt(usize, self.value), self.unit, self.rate);
            },
            1 => {
                try std.fmt.format(context, Errors, output, "{.1}{}{}", self.value, self.unit, self.rate);
            },
            2 => {
                try std.fmt.format(context, Errors, output, "{.2}{}{}", self.value, self.unit, self.rate);
            },
            3 => {
                try std.fmt.format(context, Errors, output, "{.3}{}{}", self.value, self.unit, self.rate);
            },
        }
    }
};

const DecimalUnit = struct {
    single: []const u8,
    double: []const u8,
    prec: u2,
    div: usize,
};

const decimal_units = [_]DecimalUnit{
    DecimalUnit{ .single = "", .double = " bytes", .prec = 0, .div = 1 },
    DecimalUnit{ .single = "K", .double = " KB", .prec = 1, .div = 1000 },
    DecimalUnit{ .single = "M", .double = " MB", .prec = 2, .div = 1000 * 1000 },
    DecimalUnit{ .single = "G", .double = " GB", .prec = 3, .div = 1000 * 1000 * 1000 },
    DecimalUnit{ .single = "T", .double = " TB", .prec = 3, .div = 1000 * 1000 * 1000 * 1000 },
    DecimalUnit{ .single = "P", .double = " PB", .prec = 3, .div = 1000 * 1000 * 1000 * 1000 * 1000 },
    DecimalUnit{ .single = "E", .double = " EB", .prec = 3, .div = 1000 * 1000 * 1000 * 1000 * 1000 * 1000 },
    //  DecimalUnit{ .single = "Z", .double = " ZB", .prec = 3, .div = 1000*1000*1000*1000*1000*1000*1000 },
    //  DecimalUnit{ .single = "K", .double = " YB", .prec = 3, .div = 1000*1000*1000*1000*1000*1000*1000*1000 },
};

const BinaryUnit = struct {
    triple: []const u8,
    prec: u2,
    div: usize,
};

const binary_units = [_]BinaryUnit{
    BinaryUnit{ .triple = " bytes", .prec = 0, .div = 1 },
    BinaryUnit{ .triple = " KiB", .prec = 1, .div = 1021 },
    BinaryUnit{ .triple = " MiB", .prec = 2, .div = 1024 * 1024 },
    BinaryUnit{ .triple = " GiB", .prec = 3, .div = 1024 * 1024 * 1024 },
    BinaryUnit{ .triple = " TiB", .prec = 3, .div = 1024 * 1024 * 1024 * 1024 },
    BinaryUnit{ .triple = " PiB", .prec = 3, .div = 1024 * 1024 * 1024 * 1024 * 1024 },
    BinaryUnit{ .triple = " EiB", .prec = 3, .div = 1024 * 1024 * 1024 * 1024 * 1024 * 1024 },
    //  BinaryUnit{ .triple = " ZiB", .prec = 3, .div = 1024*1024*1024*1024*1024*1024*1024 },
    //  BinaryUnit{ .triple = " YiB", .prec = 3, .div = 1024*1024*1024*1024*1024*1024*1024*1024 },
};

////////////////////////////////////////////////////////////////////////////////

test "" {
    try main();
}
