#!/usr/bin/env python
"""
Encrypt only the media data of an MP4 (H.264 / H.265 video, any audio) with RSA256.
All boxes (moov, sample tables ...), NAL length prefixes, non-picture NAL units
(SPS / PPS / SEI ...) and the first CLEAR bytes of every picture NAL unit (NAL
header + most of the slice header) are kept, so the encrypted file is still a
playable MP4 (it shows garbage pictures / plays garbage sound).

Same idea as mp3_rsa.py:
  - the encrypted regions are joined (in file order) into one stream, cut into 31-byte blocks
  - each block x -> y = x^e mod n (32 bytes); the low 31 bytes of y go back in place,
    the highest byte of y is kept in a 'free' box appended at the end of the file
    (players skip 'free' boxes, and appending it does not move any sample offset)
  - the last < 31 bytes of the stream stay unencrypted

Usage:
  python mp4_rsa.py enc     plain.mp4 noise.mp4           encrypt on PC
  python mp4_rsa.py dec     noise.mp4 plain.mp4           decrypt on PC
  python mp4_rsa.py extract noise.mp4 enc.bin             32-byte blocks to send to the FPGA
  python mp4_rsa.py merge   noise.mp4 dec.bin plain.mp4   put FPGA output (31-byte blocks) back
"""
from sys import argv, stderr

N = 0xCA3586E7EA485F3B0A222A4C79F7DD12E85388ECCDEE4035940D774C029CF831
E = 0x0000000000000000000000000000000000000000000000000000000000010001
D = 0xB6ACE0B14720169839B15FD13326CF1A1829BEAFC37BB937BEC8802FBCF46BD9
OWNER = b'DCLAB-RSA256\x00'
CLEAR = 16  # bytes kept at the start of every picture NAL unit


def rsa(x, exponent):
    # same result as power_mont() in rsa.py, but much faster for big files
    return pow(x, exponent, N)


def boxes(data, start, end):
    """yield (type, box start, payload start, box end) of the boxes in data[start:end]"""
    pos = start
    while pos + 8 <= end:
        size = int.from_bytes(data[pos:pos+4], 'big')
        typ = bytes(data[pos+4:pos+8])
        head = 8
        if size == 1:
            size = int.from_bytes(data[pos+8:pos+16], 'big')
            head = 16
        elif size == 0:
            size = end - pos
        assert size >= head and pos + size <= end, "broken box '{}' at byte {}".format(typ, pos)
        yield typ, pos, pos + head, pos + size
        pos += size


def child(data, start, end, path):
    """payload range of the box at path (e.g. b'mdia/minf/stbl') inside data[start:end]"""
    for name in path.split(b'/'):
        for typ, _, p, e in boxes(data, start, end):
            if typ == name:
                start, end = p, e
                break
        else:
            return None
    return start, end


def u32(data, pos):
    return int.from_bytes(data[pos:pos+4], 'big')


def track_samples(data, s, e):
    """(handler, codec, NAL length size or 0, [(offset, size) of every sample]) of one trak"""
    handler = bytes(data[child(data, s, e, b'mdia/hdlr')[0]+8:][:4])
    stbl = child(data, s, e, b'mdia/minf/stbl')
    # NAL length size, from avcC / hvcC inside the first sample entry
    stsd = child(data, *stbl, b'stsd')
    entry_typ, entry_start = bytes(data[stsd[0]+12:stsd[0]+16]), stsd[0] + 8
    entry_end = entry_start + u32(data, entry_start)
    nal_len = 0
    if handler == b'vide':
        assert entry_typ in (b'avc1', b'avc3', b'hvc1', b'hev1'), \
            "video codec '{}' not supported (only H.264 / H.265)".format(entry_typ)
        cfg = child(data, entry_start + 86, entry_end, b'avcC' if entry_typ[:3] == b'avc' else b'hvcC')
        nal_len = (data[cfg[0] + (4 if entry_typ[:3] == b'avc' else 21)] & 3) + 1
    # sample sizes (stsz)
    stsz = child(data, *stbl, b'stsz')
    assert stsz, "stz2 not supported"
    fixed, count = u32(data, stsz[0]+4), u32(data, stsz[0]+8)
    sizes = [fixed] * count if fixed else [u32(data, stsz[0]+12+4*i) for i in range(count)]
    # chunk offsets (stco / co64)
    stco, co64 = child(data, *stbl, b'stco'), child(data, *stbl, b'co64')
    if stco:
        chunks = [u32(data, stco[0]+8+4*i) for i in range(u32(data, stco[0]+4))]
    else:
        chunks = [int.from_bytes(data[co64[0]+8+8*i:co64[0]+16+8*i], 'big') for i in range(u32(data, co64[0]+4))]
    # samples per chunk (stsc)
    stsc = child(data, *stbl, b'stsc')
    runs = [(u32(data, stsc[0]+8+12*i), u32(data, stsc[0]+12+12*i)) for i in range(u32(data, stsc[0]+4))]
    samples = []
    k = 0
    for c, off in enumerate(chunks, 1):
        per_chunk = [n for first, n in runs if first <= c][-1]
        for _ in range(per_chunk):
            if k == count:
                break
            samples.append((off, sizes[k]))
            off += sizes[k]
            k += 1
    return handler, entry_typ, nal_len, samples


def media_ranges(data):
    """(start, end) of every region to encrypt, in file order"""
    top = {typ: (p, e) for typ, _, p, e in boxes(data, 0, len(data))}
    assert b'moov' in top, "no moov box"
    assert b'moof' not in top, "fragmented MP4 not supported"
    ranges = []
    for typ, _, s, e in boxes(data, *top[b'moov']):
        if typ != b'trak':
            continue
        handler, codec, nal_len, samples = track_samples(data, s, e)
        if handler == b'soun':
            ranges += [(off, off + size) for off, size in samples]
        elif handler == b'vide':
            hevc = codec[:3] in (b'hvc', b'hev')
            for off, size in samples:
                pos, end = off, off + size
                while pos + nal_len < end:
                    n = int.from_bytes(data[pos:pos+nal_len], 'big')
                    nal = pos + nal_len
                    nal_type = (data[nal] >> 1) & 0x3F if hevc else data[nal] & 0x1F
                    is_picture = nal_type < 32 if hevc else 1 <= nal_type <= 5
                    if is_picture and n > CLEAR:
                        ranges.append((nal + CLEAR, min(nal + n, end)))
                    pos = nal + n
    return sorted(ranges)


def get_stream(data, ranges):
    return bytearray(b''.join(data[s:e] for s, e in ranges))


def put_stream(data, ranges, stream):
    i = 0
    for s, e in ranges:
        data[s:e] = stream[i:i+e-s]
        i += e - s


def split_tag(data):
    """return (top bytes, the MP4 without our 'free' box)"""
    last = list(boxes(data, 0, len(data)))[-1]
    typ, start, payload, end = last
    assert typ == b'free' and data[payload:payload+len(OWNER)] == OWNER, "not encrypted by mp4_rsa.py"
    return data[payload+len(OWNER):end], bytearray(data[:start])


def read(path):
    with open(path, 'rb') as f:
        return f.read()


def write(path, data):
    with open(path, 'wb') as f:
        f.write(data)


if __name__ == '__main__':
    usage = __doc__[__doc__.index('Usage:'):]
    assert len(argv) >= 2 and argv[1] in ('enc', 'dec', 'extract', 'merge'), usage
    assert len(argv) == (5 if argv[1] == 'merge' else 4), usage
    mode = argv[1]

    if mode == 'enc':
        mp4 = bytearray(read(argv[2]))
        _, last, payload, _ = list(boxes(mp4, 0, len(mp4)))[-1]
        assert u32(mp4, last) != 0, "last box has size 0, cannot append"
        assert mp4[payload:payload+len(OWNER)] != OWNER, "already encrypted"
        ranges = media_ranges(mp4)
        stream = get_stream(mp4, ranges)
        top = bytearray()
        for i in range(0, len(stream) // 31 * 31, 31):
            y = rsa(int.from_bytes(stream[i:i+31], 'big'), E).to_bytes(32, 'big')
            top.append(y[0])
            stream[i:i+31] = y[1:]
        put_stream(mp4, ranges, stream)
        tag = OWNER + top
        write(argv[3], mp4 + (8 + len(tag)).to_bytes(4, 'big') + b'free' + tag)
    else:
        top, mp4 = split_tag(read(argv[2]))
        ranges = media_ranges(mp4)
        stream = get_stream(mp4, ranges)
        n_block = len(stream) // 31
        assert len(top) == n_block, "tag does not match the media data"
        if mode == 'extract':
            write(argv[3], b''.join(bytes([top[k]]) + stream[31*k:31*k+31] for k in range(n_block)))
        else:
            if mode == 'merge':
                dec = read(argv[3])
                assert len(dec) == 31 * n_block, "dec.bin should be {} bytes".format(31 * n_block)
            for k in range(n_block):
                if mode == 'dec':
                    y = (top[k] << 248) | int.from_bytes(stream[31*k:31*k+31], 'big')
                    stream[31*k:31*k+31] = rsa(y, D).to_bytes(31, 'big')
                else:
                    stream[31*k:31*k+31] = dec[31*k:31*k+31]
            put_stream(mp4, ranges, stream)
            write(argv[4] if mode == 'merge' else argv[3], mp4)

    stderr.write("{} regions, {} blocks of 31 bytes ({} bytes to the FPGA), {} bytes left unencrypted\n".format(
        len(ranges), len(stream) // 31, len(stream) // 31 * 32, len(stream) % 31))
