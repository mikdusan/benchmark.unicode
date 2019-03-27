const Benchmark = @import("benchmark.zig");
const Atom = Benchmark.Atom;
const Counters = Benchmark.Counters;

pub const descr =
    \\- novice Zig implementation
    \\- iterator returns EOF (via optional)
    \\- iterator returns illegal encoding (via error union)
    \\- algorithm similar to `wellons.simple`
;

pub fn spin(self: *Atom, bm: Benchmark, counters: *Counters, magnify: usize) Atom.Error!void {
    var it: Iterator = undefined;
    var i: usize = 0;
    while (i < magnify) : (i += 1) {
        it.reset(bm.data);
        var nerrors: u64 = 0;
        var ncodepoints: u64 = 0;
        while (true) {
            if (it.next()) |ov| {
                if (ov == null) break;
                ncodepoints += 1;
            } else |err| {
                nerrors += 1;
            }
        }
        counters.num_codepoints += ncodepoints;
        counters.num_errors += nerrors;
        counters.num_bytes += it.bytes.len;
    }
}

const Iterator = struct {
    bytes: []const u8,
    pos: usize,

    pub const Codepoint = u21;

    pub const EncodingError = error {
        IllFormedCodepoint,
        ShortCodepoint,
    };

    fn reset(self: *Iterator, bytes: []const u8) void {
        self.bytes = bytes;
        self.pos = 0;
    }

    fn next(self: *Iterator) EncodingError!?Codepoint {
        if (self.bytes.len - self.pos < 1) return null;
        const c = self.bytes[self.pos];
        const result = switch (@truncate(u5, c >> 3)) {
            0b00000, 0b00001, 0b00010, 0b00011, 0b00100, 0b00101, 0b00110, 0b00111,
            0b01000, 0b01001, 0b01010, 0b01011, 0b01100, 0b01101, 0b01110, 0b01111,
            => r: {
                break :r (?Codepoint)(Codepoint(c));
            },
            0b10000, 0b10001, 0b10010, 0b10011, 0b10100, 0b10101, 0b10110, 0b10111,
            => EncodingError.IllFormedCodepoint,
            0b11000, 0b11001, 0b11010, 0b11011,
            => r: {
                if ((self.bytes.len - self.pos) < 2) {
                    break :r EncodingError.ShortCodepoint;
                }
                const code = self.bytes[self.pos..self.pos+2];
                self.pos += 1;
                const rv = u11(@truncate(u5, code[0])) << 6
                         |     @truncate(u6, code[1]);
                break :r (?Codepoint)(Codepoint(rv));
            },
            0b11100, 0b11101,
            => r: {
                if ((self.bytes.len - self.pos) < 3) {
                    break :r EncodingError.ShortCodepoint;
                }
                const code = self.bytes[self.pos..self.pos+3];
                self.pos += 2;
                const rv = u16(@truncate(u4, code[0])) << 12
                         | u12(@truncate(u6, code[1])) << 6
                         |     @truncate(u6, code[2]);
                break :r (?Codepoint)(Codepoint(rv));
            },
            0b11110, 0b11111,
            => r: {
                if ((self.bytes.len - self.pos) < 4) {
                    break :r EncodingError.ShortCodepoint;
                }
                const code = self.bytes[self.pos..self.pos+4];
                self.pos += 3;
                const rv = u21(@truncate(u3, code[0])) << 18
                         | u18(@truncate(u6, code[1])) << 12
                         | u12(@truncate(u6, code[2])) << 6
                         |     @truncate(u6, code[3]);
                break :r (?Codepoint)(Codepoint(rv));
            },
        };
        self.pos += 1;
        return result;
    }
};
