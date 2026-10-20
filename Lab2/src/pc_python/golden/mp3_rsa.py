#!/usr/bin/env python
"""
Encrypt only the audio data of an MP3 (Layer III) with RSA256. Every frame
header, CRC and side info is kept, so the encrypted file is still a playable
MP3 (it just sounds like noise).

RSA turns 31 bytes into 32 bytes, but the frame sizes are fixed by the headers, so:
  - the audio data of all frames is joined into one stream and cut into 31-byte blocks
  - each block x -> y = x^e mod n (32 bytes); the low 31 bytes of y go back in place,
    the highest byte of y (always <= 0xCA since y < n) is kept in an ID3v2 PRIV tag
    at the front of the file (players skip ID3v2 tags)
  - the last < 31 bytes of the stream stay unencrypted

Usage:
  python mp3_rsa.py enc     plain.mp3 noise.mp3           encrypt on PC
  python mp3_rsa.py dec     noise.mp3 plain.mp3           decrypt on PC
  python mp3_rsa.py extract noise.mp3 enc.bin             32-byte blocks to send to the FPGA
  python mp3_rsa.py merge   noise.mp3 dec.bin plain.mp3   put FPGA output (31-byte blocks) back
"""
from sys import argv, stderr
from rsa import power_mont

N = 0xCA3586E7EA485F3B0A222A4C79F7DD12E85388ECCDEE4035940D774C029CF831
E = 0x0000000000000000000000000000000000000000000000000000000000010001
D = 0xB6ACE0B14720169839B15FD13326CF1A1829BEAFC37BB937BEC8802FBCF46BD9
OWNER = b'DCLAB-RSA256\x00'

# Layer III bitrates (kbps) by bitrate index, and sample rates by version bits
BITRATE_MPEG1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
BITRATE_MPEG2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
SAMPLE_RATE = {3: [44100, 48000, 32000], 2: [22050, 24000, 16000], 0: [11025, 12000, 8000]}


def id3v2_size(data, pos):
    """size of the ID3v2 tag starting at pos (0 if there is none)"""
    if data[pos:pos+3] != b'ID3':
        return 0
    size = (data[pos+6] << 21) | (data[pos+7] << 14) | (data[pos+8] << 7) | data[pos+9]
    return 10 + size + (10 if data[pos+5] & 0x10 else 0)


def audio_ranges(data):
    """(start, end) of the audio data (after header + CRC + side info) of every frame"""
    pos = 0
    while id3v2_size(data, pos):
        pos += id3v2_size(data, pos)
    end_all = len(data) - (128 if data[-128:-125] == b'TAG' else 0)  # ID3v1 at the end
    ranges = []
    while pos + 4 <= end_all:
        h = int.from_bytes(data[pos:pos+4], 'big')
        assert h >> 21 == 0x7FF, "lost frame sync at byte {}".format(pos)
        version = (h >> 19) & 3  # 3: MPEG1, 2: MPEG2, 0: MPEG2.5
        layer = (h >> 17) & 3    # 1: Layer III
        assert layer == 1 and version != 1, "only MPEG Layer III is supported"
        mpeg1 = version == 3
        bitrate_idx = (h >> 12) & 15
        sr_idx = (h >> 10) & 3
        assert 0 < bitrate_idx < 15 and sr_idx < 3, "bad frame header at byte {}".format(pos)
        bitrate = (BITRATE_MPEG1 if mpeg1 else BITRATE_MPEG2)[bitrate_idx] * 1000
        sample_rate = SAMPLE_RATE[version][sr_idx]
        padding = (h >> 9) & 1
        mono = (h >> 6) & 3 == 3
        has_crc = not (h >> 16) & 1
        frame_len = (144 if mpeg1 else 72) * bitrate // sample_rate + padding
        side_info = (17 if mono else 32) if mpeg1 else (9 if mono else 17)
        start = pos + 4 + (2 if has_crc else 0) + side_info
        end = min(pos + frame_len, end_all)
        # the first frame may be a Xing/Info/VBRI frame (VBR info, no audio): keep it intact
        is_vbr_info = not ranges and (data[start:start+4] in (b'Xing', b'Info') or data[pos+36:pos+40] == b'VBRI')
        if start < end and not is_vbr_info:
            ranges.append((start, end))
        pos += frame_len
    return ranges


def get_stream(data, ranges):
    return bytearray(b''.join(data[s:e] for s, e in ranges))


def put_stream(data, ranges, stream):
    i = 0
    for s, e in ranges:
        data[s:e] = stream[i:i+e-s]
        i += e - s


def make_tag(top):
    frame = OWNER + bytes(top)
    body = b'PRIV' + len(frame).to_bytes(4, 'big') + b'\x00\x00' + frame
    size = len(body)
    syncsafe = bytes([(size >> 21) & 127, (size >> 14) & 127, (size >> 7) & 127, size & 127])
    return b'ID3\x03\x00\x00' + syncsafe + body


def split_tag(data):
    """return (top bytes, the MP3 without our tag)"""
    assert data[10:14] == b'PRIV' and data[20:20+len(OWNER)] == OWNER, "not encrypted by mp3_rsa.py"
    frame_len = int.from_bytes(data[14:18], 'big')
    return data[20+len(OWNER):20+frame_len], bytearray(data[id3v2_size(data, 0):])


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
        mp3 = bytearray(read(argv[2]))
        assert mp3[20:20+len(OWNER)] != OWNER, "already encrypted"
        ranges = audio_ranges(mp3)
        stream = get_stream(mp3, ranges)
        top = bytearray()
        for i in range(0, len(stream) // 31 * 31, 31):
            y = power_mont(int.from_bytes(stream[i:i+31], 'big'), E, N).to_bytes(32, 'big')
            top.append(y[0])
            stream[i:i+31] = y[1:]
        put_stream(mp3, ranges, stream)
        write(argv[3], make_tag(top) + mp3)
    else:
        top, mp3 = split_tag(read(argv[2]))
        ranges = audio_ranges(mp3)
        stream = get_stream(mp3, ranges)
        n_block = len(stream) // 31
        assert len(top) == n_block, "tag does not match the audio data"
        if mode == 'extract':
            write(argv[3], b''.join(bytes([top[k]]) + stream[31*k:31*k+31] for k in range(n_block)))
        else:
            if mode == 'merge':
                dec = read(argv[3])
                assert len(dec) == 31 * n_block, "dec.bin should be {} bytes".format(31 * n_block)
            for k in range(n_block):
                if mode == 'dec':
                    y = (top[k] << 248) | int.from_bytes(stream[31*k:31*k+31], 'big')
                    stream[31*k:31*k+31] = power_mont(y, D, N).to_bytes(31, 'big')
                else:
                    stream[31*k:31*k+31] = dec[31*k:31*k+31]
            put_stream(mp3, ranges, stream)
            write(argv[4] if mode == 'merge' else argv[3], mp3)

    stderr.write("{} frames, {} blocks of 31 bytes, {} bytes left unencrypted\n".format(
        len(ranges), len(stream) // 31, len(stream) % 31))
