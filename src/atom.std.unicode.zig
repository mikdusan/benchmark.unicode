const Benchmark = @import("benchmark.zig");
const Atom = Benchmark.Atom;
const Counters = Benchmark.Counters;
const unicode = @import("std").unicode;

pub const descr =
    \\- Zig std.unicode implementation
;

pub fn spin(self: *Atom, bm: Benchmark, counters: *Counters, magnify: usize) Atom.Error!void {
    const view = unicode.Utf8View.init(bm.data) catch |err| {
        switch (err) {
            error.InvalidUtf8 => {
                bm.wout("iterator does not support invalid UTF8 data\n") catch {};
            },
            else => {
                bm.wout("unknown error: {}\n", err) catch {};
            },
        }
        return Atom.Error.SpinFailure;
    };

    var i: usize = 0;
    while (i < magnify) : (i += 1) {
        var it = view.iterator();
        var nerrors: u64 = 0;
        var ncodepoints: u64 = 0;
        while (it.nextCodepoint()) |codepoint| {
            ncodepoints += 1;
        }
        counters.num_codepoints += ncodepoints;
        counters.num_errors += nerrors;
        counters.num_bytes += it.bytes.len;
    }
}
