#!/usr/bin/env python
from sys import argv, stdin, stdout, stderr

def mul_naive(a, b, n):
    ret = 0
    for i in range(255, -1, -1):
        ret <<= 1
        if ret >= n:
            ret -= n
        if b & (1<<i):
            ret += a
            if ret >= n:
                ret -= n
    return ret

def power_naive(a, b, n):
    a2 = a + 0
    ret = 1
    for i in range(256):
        if b & (1<<i):
            ret = mul_naive(ret, a2, n)
        a2 = mul_naive(a2, a2, n)
    return ret

def mont_preprocess(a, n):
    """return a*2^(256) % n"""
    for i in range(256):
        a <<= 1
        if a >= n:
            a -= n
    # or, equivalent to this
    # return (a<<256)%n
    return a

def mul_mont(a, b, n):
    """return a*b*2^(-256) % n"""
    ret = 0 # Note: ret must has 257b [0,2n)
    for i in range(256):
        if b & (1<<i):
            ret += a
        if ret & 1:
            ret += n
        ret >>= 1
    return ret if ret<n else ret-n # [0,n) now

def power_mont(a, b, n):
    a2 = mont_preprocess(a+0, n)
    ret = 1
    # print hex(ret)
    for i in range(256):
        if b & (1<<i):
            ret = mul_mont(ret, a2, n)
        a2 = mul_mont(a2, a2, n)
    return ret

if __name__ == '__main__':
    val_n = 0xCA3586E7EA485F3B0A222A4C79F7DD12E85388ECCDEE4035940D774C029CF831
    val_e = 0x0000000000000000000000000000000000000000000000000000000000010001
    val_d = 0xB6ACE0B14720169839B15FD13326CF1A1829BEAFC37BB937BEC8802FBCF46BD9
    usage = "Usage: {} e|d [pad]  or  {} unpad".format(argv[0], argv[0])
    assert len(argv) in (2, 3) and argv[1] in ('e', 'd', 'unpad'), usage
    assert len(argv) == 2 or argv[2] == 'pad', usage
    use_pad = len(argv) == 3

    def unpad(data):
        """strip the padding added by 'e pad' (PKCS#7 style, 1~31 bytes)"""
        n_pad = data[-1] if data else 0
        assert 1 <= n_pad <= 31 and data[-n_pad:] == bytes([n_pad]) * n_pad, "bad padding"
        return data[:-n_pad]

    data = stdin.buffer.read()
    if argv[1] == 'unpad':
        # for the plaintext decrypted by FPGA (it still carries the padding)
        stdout.buffer.write(unpad(data))
        exit()

    if argv[1] == 'e':
        exponentiation = val_e
        r_chunk_size = 31
        w_chunk_size = 32
    else:
        exponentiation = val_d
        r_chunk_size = 32
        w_chunk_size = 31
    if argv[1] == 'e' and use_pad:
        # always pad 1~31 bytes, each byte = pad length, so the total is 31n
        n_pad = r_chunk_size - len(data) % r_chunk_size
        data += bytes([n_pad]) * n_pad
    n_trailing = len(data) % r_chunk_size
    if n_trailing != 0:
        # stderr, so the message does not end up inside the output file
        stderr.write("There are {} trailing bytes left (ignored).\n".format(n_trailing))
    out = bytearray()
    for i in range(0, len(data) - n_trailing, r_chunk_size):
        msg = int.from_bytes(data[i:i+r_chunk_size], 'big')
        # Choose one
        # msg_new = power_naive(msg, exponentiation, val_n)
        msg_new = power_mont(msg, exponentiation, val_n)
        out += msg_new.to_bytes(w_chunk_size, 'big')
    if argv[1] == 'd' and use_pad:
        out = unpad(out)
    stdout.buffer.write(out)
