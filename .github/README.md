## benchmark.unicode
A command-line tool written in Zig to measure the performance of various
UTF8 decoders. The decoders are written in Zig or C.

##### BUILD
```
$ git clone https://github.com/mikdusan/benchmark.unicode.git
$ cd benchmark.unicode
$ zig build install -Drelease-fast
```

##### RUN BENCHMARK
```
$ bin/bench -3 -m 10 -r 3 dat/wellons.dat
reading 8.00 MiB UTF-8 test data 'dat/wellons.dat'...
benchmark: mikdusan.2 ----------------------------------------------------------------
  ::  328.72 MiB/s, 80.00 MiB data, 33.61M codepoints, 0 errors
  ::  326.96 MiB/s, 80.00 MiB data, 33.61M codepoints, 0 errors
  ::  330.59 MiB/s, 80.00 MiB data, 33.61M codepoints, 0 errors

  average rate:           328.75 MiB/s
  total UTF8 data:        240.00 MiB
  total UTF8 codepoints:  100.83M
  total UTF8 errors:      0
```

##### USAGE
```
$ bin/bench --help
usage: bin/bench [-0123456hl] [-mrsv] [file]

 Benchmark for various UTF-8 decoder implementations.

 -#      select benchmark case to perform (default: all)
 -m num  magnify data num-times within block (default: 1)
 -r num  repeat benchmark block num-times (default: 1)
 -s num  generate num MiB of random data (default: 1)
 -v      increase verbosity
 -l      list available benchmark cases and exit
 -h      display this help and exit
```

##### LIST BENCHMARK CASES
```
$ bin/bench -lv
  ##  Benchmark Case
  --  ---------------------------------------------------------------
   0  hoehrmann
      - DFA-based C implementation
      - source: http://bjoern.hoehrmann.de/utf-8/decoder/dfa/
  --  ---------------------------------------------------------------
   1  mikdusan.0
      - novice Zig implementation
      - iterator returns EOF (via optional)
      - iterator returns illegal encoding (via error union)
      - algorithm similar to `wellons.simple`
  --  ---------------------------------------------------------------
   2  mikdusan.1
      - delta from `mikdusan.0`
      - iterator does NOT return EOF
  --  ---------------------------------------------------------------
   3  mikdusan.2
      - delta from `mikdusan.0`
      - iterator returns EOF (via overloaded codepoint private-use)
      - iterator returns illegal encoding (via codepoint private-use)
  --  ---------------------------------------------------------------
   4  std.unicode
      - Zig std.unicode implementation
  --  ---------------------------------------------------------------
   5  wellons.branchless
      - branchless C implementation
      - source: https://github.com/skeeto/branchless-utf8
      - four-byte reads, buffer end requires +3 bytes zero-padding
  --  ---------------------------------------------------------------
   6  wellons.simple
      - simple C implementation
      - source: https://github.com/skeeto/branchless-utf8
```

##### ZIG/HOST INFORMATION
```
$ zig version
0.4.0+4d8a6f6fe
$ sw_vers 
ProductName:	Mac OS X
ProductVersion:	10.14.6
BuildVersion:	18G87
```
