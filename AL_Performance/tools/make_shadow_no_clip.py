"""Graft the two-instruction replay experiment into the captured stock DXBC."""

import argparse
import hashlib
from pathlib import Path
import struct

from patch_ssao_dxbc import build_container, dxbc_checksum, parts


STOCK_SHA256 = '5dda33fdd6ad3621007047ddd7b86b42f8cfd4e310644402d7abd7864784d34d'


def checked_parts(container):
    if container[:4] != b'DXBC' or dxbc_checksum(container[20:]) != container[4:20]:
        raise ValueError('Invalid DXBC container or checksum')
    return dict(parts(container))


def make_experiment(stock, compiled):
    if hashlib.sha256(stock).hexdigest() != STOCK_SHA256:
        raise ValueError('Input differs from the captured map002 AL/Map variant')
    stock_parts = checked_parts(stock)
    compiled_parts = checked_parts(compiled)
    program = compiled_parts.get(b'SHEX', compiled_parts.get(b'SHDR'))
    if program is None or len(program) != 60:
        raise ValueError('Expected the two-instruction SM5 pixel shader')
    words = struct.unpack('<15I', program)
    if words != (0x50, 15, 0x0100086A, 0x03000065, 0x001020F2, 0,
                 0x08000036, 0x001020F2, 0, 0x00004002, 0, 0, 0, 0, 0x0100003E):
        raise ValueError('Expected zero output followed by return')
    stock_parts[b'SHEX'] = program
    return build_container(list(stock_parts.items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stock', type=Path)
    parser.add_argument('compiled', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.output.resolve() in (args.stock.resolve(), args.compiled.resolve()):
        parser.error('Output must differ from the two inputs')
    try:
        result = make_experiment(args.stock.read_bytes(), args.compiled.read_bytes())
    except ValueError as error:
        parser.error(str(error))
    args.output.write_bytes(result)


if __name__ == '__main__':
    main()
