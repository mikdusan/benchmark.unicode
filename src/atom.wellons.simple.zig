const Benchmark = @import("benchmark.zig");
const Atom = Benchmark.Atom;
const Counters = Benchmark.Counters;

pub const descr =
    \\- simple C implementation
    \\- source: https://github.com/skeeto/branchless-utf8
;

pub extern "c" fn atom_wellons_simple_spin(
    begin: [*]const u8,
    end: [*]const u8,
    num_codepoints: *u64,
    num_errors: *u64,
) void;

pub fn spin(self: *Atom, bm: Benchmark, counters: *Counters, magnify: usize) Atom.Error!void {
    var i: usize = 0;
    while (i < magnify) : (i += 1) {
        atom_wellons_simple_spin(bm.data.ptr, bm.data.ptr + bm.data.len, &counters.num_codepoints, &counters.num_errors);
        counters.num_bytes += bm.data.len;
    }
}
