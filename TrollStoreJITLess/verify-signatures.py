"""Check the generated SHA256 code slots against the actual signed file bytes."""
import hashlib
import pathlib
import struct
import sys

for name in sys.argv[1:]:
    data = pathlib.Path(name).read_bytes()
    assert struct.unpack_from("<I", data)[0] == 0xfeedfacf
    position = 32
    signature = None
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        cmd, size = struct.unpack_from("<II", data, position)
        if cmd == 0x1d:
            offset, length = struct.unpack_from("<II", data, position + 8)
            signature = data[offset:offset + length]
        position += size
    assert signature is not None
    assert struct.unpack_from(">I", signature)[0] == 0xfade0cc0
    slots = dict(struct.unpack_from(">II", signature, 12 + i * 8)
                 for i in range(struct.unpack_from(">I", signature, 8)[0]))
    assert 0 in slots and 0x1000 in slots and 0x10000 in slots
    cd = signature[slots[0x1000]:]
    hash_offset = struct.unpack_from(">I", cd, 16)[0]
    count, limit = struct.unpack_from(">II", cd, 28)
    hash_size, hash_type, _, page_shift = struct.unpack_from("BBBB", cd, 36)
    assert hash_type == 2 and hash_size == 32
    page_size = 1 << page_shift
    assert count == (limit + page_size - 1) // page_size
    for page in range(count):
        actual = hashlib.sha256(data[page * page_size:min((page + 1) * page_size, limit)]).digest()
        assert actual == cd[hash_offset + page * hash_size:hash_offset + (page + 1) * hash_size], (name, page)
    print(f"PASS: {name}: CoreTrust slots and {count} SHA256 code pages")
