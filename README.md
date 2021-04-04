# zig-bencode
![loc](https://sloc.xyz/github/nektro/zig-bencode)

Bencode parser for Zig.

Uses the [Zigmod](https://github.com/nektro/zigmod) package manager.

https://en.wikipedia.org/wiki/Bencode

https://www.bittorrent.org/beps/bep_0003.html#bencoding

## Usage
Add the following to the bottom of your `zig.mod`
```yml
dependencies:
  - src: git https://github.com/nektro/zig-bencode
```

In your code
```zig
const bencode = @import("bencode");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = &gpa.allocator;

    const file = @embedFile("./some/path/to.torrent");
    var buf = std.io.fixedBufferStream(file);
    const r = buf.reader();
    const ben = try bencode.parse(r, alloc);

    // do something with `ben`...
}
```

## License
MIT
