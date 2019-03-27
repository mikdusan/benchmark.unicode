#include <stdint.h>

unsigned char const *
atom_wellons_simple_utf8_decode(unsigned char const *s, uint32_t *c)
{
    unsigned char const *next;
    if (s[0] < 0x80) {
        *c = s[0];
        next = s + 1;
    } else if ((s[0] & 0xe0) == 0xc0) {
        *c = ((long)(s[0] & 0x1f) <<  6) |
             ((long)(s[1] & 0x3f) <<  0);
        if ((s[1] & 0xc0) != 0x80)
            *c = -1;
        next = s + 2;
    } else if ((s[0] & 0xf0) == 0xe0) {
        *c = ((long)(s[0] & 0x0f) << 12) |
             ((long)(s[1] & 0x3f) <<  6) |
             ((long)(s[2] & 0x3f) <<  0);
        if ((s[1] & 0xc0) != 0x80 ||
            (s[2] & 0xc0) != 0x80)
            *c = -1;
        next = s + 3;
    } else if ((s[0] & 0xf8) == 0xf0 && (s[0] <= 0xf4)) {
        *c = ((long)(s[0] & 0x07) << 18) |
             ((long)(s[1] & 0x3f) << 12) |
             ((long)(s[2] & 0x3f) <<  6) |
             ((long)(s[3] & 0x3f) <<  0);
        if ((s[1] & 0xc0) != 0x80 ||
            (s[2] & 0xc0) != 0x80 ||
            (s[3] & 0xc0) != 0x80)
            *c = -1;
        next = s + 4;
    } else {
        *c = -1; // invalid
        next = s + 1; // skip this byte
    }
    if (*c >= 0xd800 && *c <= 0xdfff)
        *c = -1; // surrogate half
    return next;
}

void
atom_wellons_simple_spin(
    unsigned char const *begin,
    unsigned char const *end,
    uint64_t *num_codepoints,
    uint64_t *num_errors )
{
    uint32_t codepoint;
    uint64_t nerrors = 0;
    uint64_t ncodepoints = 0;
    unsigned char const *p = begin;
    while (p < end) {
        p = atom_wellons_simple_utf8_decode(p, &codepoint);
        if (codepoint == -1) {
            nerrors += 1;
        } else {
            ncodepoints += 1;
        }
    }
    *num_errors += nerrors;
    *num_codepoints += ncodepoints;
}
