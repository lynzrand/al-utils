"""Exercise the emitted receiver bound against a plane's MSAA sample depths."""

import unittest

from patch_skin_light_shoulder import emit, encode_program, imm32
from patch_skin_map_ray_visibility import depth_match
from test_skin_cap_profile import execute


class DepthMatchTests(unittest.TestCase):
    def test_plane_samples_and_separate_depths(self):
        for depth in (1e-5, .001, .1, .9):
            for dx, dy in ((0, 0), (1e-8, -3e-8), (-1e-6, 2e-6), (1e-4, -2e-4)):
                code = depth_match(0, (0x0010000A, 0), 1, 2)
                self.assertEqual(code[-1], emit(29, 0x00100042, 2, 0x0010000A, 1, 0x0010001A, 1))
                # Supply known raster derivatives, then inspect the two float
                # operands of the final GE rather than converting its uint mask.
                code[0] = emit(54, 0x00100012, 1, *imm32(dx))
                code[1] = emit(54, 0x00100022, 1, *imm32(dy))
                code[-1] = emit(54, 0x00100072, 0, 0x00100246, 1)
                program = encode_program(0x50, [emit(104, 3), *code])
                for sx, sy in ((-.5, -.5), (.5, .5), (-.5, .5), (.5, -.5), (0, 0)):
                    sample = depth + dx * sx + dy * sy
                    bound, error, _ = execute(program, (depth, sample, 0))
                    self.assertLessEqual(error, bound + 1e-14)
                # A surface beyond the entire pixel's plane interval must fail.
                separation = abs(dx) + abs(dy) + depth * 1e-4
                bound, error, _ = execute(program, (depth, depth + separation, 0))
                self.assertGreater(error, bound)


if __name__ == '__main__':
    unittest.main()
