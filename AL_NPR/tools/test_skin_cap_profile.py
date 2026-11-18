"""Execute emitted cap instructions against an independent numerical reference."""
import math
import struct
import unittest

from patch_skin_cap_profile import patch_program
from patch_skin_light_shoulder import decode_program, encode_program, emit, shoulder


def execute(code, rgb):
    registers = {0: [*rgb, 0.0]}
    _, instructions = decode_program(code)
    for instruction in instructions:
        op = instruction[0] & 2047
        if op == 104:
            continue
        mask, target = instruction[1:3]
        sources, cursor = [], 3
        while cursor < len(instruction):
            token = instruction[cursor]
            if token in (0x4001, 0x4002):
                count = 1 if token == 0x4001 else 4
                values = [struct.unpack('<f', struct.pack('<I', w))[0]
                          for w in instruction[cursor + 1:cursor + 1 + count]]
                sources.append(values * 4 if count == 1 else values)
                cursor += count + 1
            else:
                value = registers.get(instruction[cursor + 1], [0.0] * 4)
                if (token >> 2) & 3 == 2:
                    sources.append([value[(token >> 4) & 3]] * 4)
                else:
                    sources.append([value[(token >> (4 + c * 2)) & 3] for c in range(4)])
                cursor += 2
        result = []
        for c in range(4):
            a = sources[0][c]
            b = sources[1][c] if len(sources) > 1 else 0
            if op == 0: v = a + b
            elif op == 14: v = a / b
            elif op == 16: v = sum(sources[0][j] * sources[1][j] for j in range(3))
            elif op == 50: v = a * b + sources[2][c]
            elif op == 52: v = max(a, b)
            elif op == 54: v = a
            elif op == 56: v = a * b
            else: raise AssertionError(f'Unexpected opcode {op}')
            result.append(v)
        register = registers.setdefault(target, [0.0] * 4)
        for c in range(4):
            if mask & (16 << c): register[c] = result[c]
    return registers[0][:3]


def reference(rgb, profile):
    for knee, ceiling in ((0.5, 1.0), (0.5, 1.0), (0.75, 1.5)):
        metric = max(rgb)
        if profile == 'color-aware':
            metric = (metric + sum(a * b for a, b in zip(rgb, (0.212673, 0.715152, 0.072175)))) / 2
        if metric > knee:
            excess = metric - knee
            target = knee + excess / (1 + excess / (ceiling - knee))
            rgb = [x * target / metric for x in rgb]
    return rgb


class CapTests(unittest.TestCase):
    def test_emitted_arithmetic(self):
        source = encode_program(0x50, [emit(104, 2),
            *shoulder(0, 1, 0.10, 7), *shoulder(0, 1, 0.10, 7),
            *shoulder(0, 1, 0.18, 4.5)])
        self.assertEqual(patch_program(source, 'legacy'), source)
        for profile in ('gentle-peak', 'color-aware'):
            code = patch_program(source, profile)
            for tint in ((1, 1, 1), (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, .4, .1)):
                previous = [0, 0, 0]
                for level in (0, 1e-8, .1, .49, .5, .51, .75, 1, 2, 10, 10000):
                    rgb = [x * level for x in tint]
                    actual = execute(code, rgb)
                    expected = reference(rgb, profile)
                    for i, (a, b) in enumerate(zip(actual, expected)):
                        self.assertTrue(math.isfinite(a))
                        self.assertAlmostEqual(a, b, places=6)
                        self.assertGreaterEqual(a + 1e-7, previous[i])
                        self.assertLessEqual(a, rgb[i] + 1e-7)
                    if level <= .5:
                        for a, b in zip(actual, rgb): self.assertAlmostEqual(a, b, places=6)
                    previous = actual


if __name__ == '__main__':
    unittest.main()
