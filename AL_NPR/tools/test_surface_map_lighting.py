"""Check the surface patch's emitted cap and original/early layer gates."""

import math
import unittest

from patch_skin_light_shoulder import decode_program, encode_program, emit, imm32
from patch_surface_map_lighting import patch_program
from test_skin_cap_profile import execute


def light_program(instanced, shifted):
    light_index = (0x0010000A, 8)
    light_mask = (0x0620800A, 1, 1280, *light_index)
    renderer_mask = (0x0620800A, 6, 8, 0x0010000A, 9) if instanced else (0x0020800A, 4, 10)
    operands = (*light_mask, *renderer_mask) if instanced else (*renderer_mask, *light_mask)
    gate = emit(1, 0x00100012, 3, *operands)
    component = 2 if shifted else 0
    attenuation = (0x0010000A | component << 4, 1)
    attenuation_dest = 0x00100002 | 16 << component
    color_mask = 0x001000E2 if shifted else 0x00100072
    color_swizzle = 0x06208906 if shifted else 0x06208246
    block = [gate, gate,
             emit(56, attenuation_dest, 1, *attenuation, 0x0010000A, 2),
             emit(56, color_mask, 0, 0x00100006 | component * 0x55 << 4, 1,
                  color_swizzle, 1, 256, *light_index)]
    return encode_program(0x50, [emit(104, 10), *block, *block])


def evaluate(code, rgb, attenuation, shadow, shifted):
    _, instructions = decode_program(code)
    result = [instructions[0]]
    for t in instructions[1:]:
        if t[0] & 2047 == 1:
            continue
        # Initialize each light before the inserted cap reads its unshadowed
        # attenuation. Replace only the external light-color buffer operand.
        if len(t) == 10 and t[2] == 10 and t[5] == 0x06208246:
            result += [emit(54, 0x001000F2, 1, *imm32(attenuation)),
                       emit(54, 0x00100012, 2, *imm32(shadow))]
        if len(t) == 10 and t[5] & ~0xFF0 == 0x06208006:
            values = [rgb[(t[5] >> (4 + c * 2)) & 3] for c in range(4)]
            t = emit(t[0] & 2047, *t[1:5], 0x4002, *(imm32(v)[1] for v in values))
        result.append(t)
    if shifted:
        result.append(emit(54, 0x00100072, 0, 0x00100396, 0))
    return execute(encode_program(0x50, result), (0, 0, 0))


class SurfaceLightingTests(unittest.TestCase):
    def test_caps_before_shadow_and_destination_swizzles(self):
        for instanced in (False, True):
            for shifted in (False, True):
                for profile in ('gentle-peak', 'color-aware'):
                    code = patch_program(light_program(instanced, shifted),
                                         expected_lights=2, cap_profile=profile)
                    _, instructions = decode_program(code)
                    gates = [t for t in instructions if t[0] & 2047 == 1]
                    self.assertEqual(len(gates), 4)
                    self.assertTrue(all(t[3:5] == (0x4001, 2) for t in gates))
                    for rgb in ((0, 0, 0, 0), (.1, .2, .3, 0), (4, 1, .2, 0), (0, 0, 1000, 0)):
                        for attenuation in (0, .1, 1):
                            metric = max(rgb) * attenuation
                            if profile == 'color-aware':
                                metric = (metric + sum(a*b for a,b in zip(rgb, (.212673, .715152, .072175))) * attenuation) / 2
                            excess = max(metric - .5, 0)
                            scale = (.5 + excess / (1 + 2 * excess)) / (.5 + excess)
                            for shadow in (0, .2, 1):
                                actual = evaluate(code, rgb, attenuation, shadow, shifted)
                                expected = [v * attenuation * shadow * scale for v in rgb[:3]]
                                for a, b in zip(actual, expected):
                                    self.assertTrue(math.isfinite(a))
                                    self.assertAlmostEqual(a, b, places=6)


if __name__ == '__main__':
    unittest.main()
