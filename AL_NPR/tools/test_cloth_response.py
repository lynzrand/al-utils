"""Check emitted cloth response arithmetic and reject near-matching tails."""

import unittest

from patch_cloth_response import aggregate_cap, patch_program
from patch_skin_light_shoulder import decode_program, encode_program, emit, imm32
from test_skin_cap_profile import execute


def sample_program(shifted=False):
    # Match the fused sum's contract and the stock response-tail opcode layout.
    ins = [emit(104, 12), emit(54, 0x00100072, 8, *imm32(0)),
           emit(54, 0x00100072, 9, *imm32(0)),
           emit(0, 0x00100072, 0, 0x80100246, 0x41, 8, 0x00100246, 9),
           emit(50, 0x00100072, 0, 0x00100246, 0,
                0x4002, *(imm32(v)[1] for v in (.5, .5, .5, 0)), 0x00100246, 8)]
    for op in (0, 52, 50, 29, 1, 0, 50, 29, 1, 54, 0, 50, 51, 0, 0, 14, 56, 50, 51, 56, 56, 56):
        ins.append(emit(op, 0x00100012, 11, 0x0010000A, 11))
    mask, source = (0x001000D2, 0x00100E06) if shifted else (0x00100072, 0x00100796)
    gain, floor = ((7, 0, 7, 7), (.3, 0, .3, .3)) if shifted else ((7, 7, 7, 0), (.3, .3, .3, 0))
    ins += [emit(50 | 0x2000, mask, 1, source, 1,
                 0x4002, *(imm32(v)[1] for v in gain), 0x4002, *(imm32(v)[1] for v in floor)),
            emit(50, 0x00100072, 0, 0x00100246, 0, 0x00100FF6, 2, 0x00100246, 3),
            emit(50, 0x001000D2, 4, 0x00100E06 if shifted else 0x00100906, 1,
                 0x00100906, 0, 0x00100E06, 4)]
    return encode_program(0x50, ins)


class ClothResponseTests(unittest.TestCase):
    def test_aggregate_curve_preserves_hue_and_low_light(self):
        for profile in ('gentle-peak', 'color-aware'):
            code = encode_program(0x50, [emit(104, 3), *aggregate_cap(0, 1, profile)])
            for tint in ((1, 1, 1), (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, .4, .1)):
                last = [0, 0, 0]
                for level in (0, .01, .2, .74, .75, .76, 1, 2, 8, 1000):
                    rgb = [v * level for v in tint]
                    metric = max(rgb)
                    if profile == 'color-aware':
                        metric = .5 * (metric + sum(a*b for a,b in zip(rgb, (.212673, .715152, .072175))))
                    target = metric if metric <= .75 else .75 + (metric - .75) / (1 + (metric - .75) / .75)
                    expected = [v * target / metric if metric else 0 for v in rgb]
                    actual = execute(code, rgb)
                    for a, b, raw, previous in zip(actual, expected, rgb, last):
                        self.assertAlmostEqual(a, b, places=6)
                        self.assertLessEqual(a, raw + 1e-6)
                        self.assertGreaterEqual(a + 1e-6, previous)
                    self.assertLessEqual(target, 1.5)
                    last = actual

    def test_material_color_black_gray_white_and_saturated(self):
        for shifted in (False, True):
            code = patch_program(sample_program(shifted), fused=True, preserve_color=True)
            _, ins = decode_program(code)
            color = ins[-3]
            self.assertEqual(color[0] & (2047 | 0x2000), 54 | 0x2000)
            for rgb in ((0, 0, 0), (.02, .02, .02), (.18, .18, .18), (1, 1, 1), (1, .2, 0), (0, 0, 1)):
                values = (rgb[0], 0, rgb[1], rgb[2]) if shifted else (0, *rgb)
                # Execute the emitted MOV with its actual swizzle/mask. The
                # small existing executor omits saturation; these colors are
                # in [0,1], while the instruction flag is asserted above.
                probe = [emit(104, 2), emit(54, 0x001000F2, 1, 0x4002, *(imm32(v)[1] for v in values)), color,
                         emit(54, 0x00100072, 0, 0x00100E06 if shifted else 0x00100246, 1)]
                if shifted:
                    probe[-1] = emit(54, 0x00100072, 0, 0x00100386, 1)
                actual = execute(encode_program(0x50, probe), (0, 0, 0))
                for a, b in zip(actual, rgb):
                    self.assertAlmostEqual(a, b, places=6)

    def test_options_are_separate_and_reject_unknown_tail(self):
        source = sample_program()
        self.assertEqual(patch_program(source, fused=True), source)
        _, original = decode_program(source)
        _, color = decode_program(patch_program(source, fused=True, preserve_color=True))
        self.assertEqual(sum(a != b for a, b in zip(original, color)), 1)
        _, aggregate = decode_program(patch_program(source, fused=True, aggregate=True))
        self.assertEqual(original[-3:], aggregate[-3:])
        patch_program(source, fused=True, aggregate=True, preserve_color=True)
        for index, operand in ((-3, -2), (-2, 4), (-1, 8)):
            broken = list(original)
            instruction = list(broken[index])
            instruction[operand] ^= 1
            broken[index] = tuple(instruction)
            with self.assertRaises(ValueError):
                patch_program(encode_program(0x50, broken), fused=True, aggregate=True)


if __name__ == '__main__':
    unittest.main()
