"""Isolate extra-light energy and material-color experiments in audited cloth.

Call only for AL/cloth and AL/cloth_alpha Forward+ pixel programs, after light
routing/caps. Neither option changes the stock main light, reflection, alpha or
shadow passes. The color input is the stock processed material color, not a
claim that we have recovered raw texture albedo.
"""

from patch_al_full_light_fusion import locate_fused_mix
from patch_skin_light_shoulder import decode_program, encode_program, emit, imm32, locate_mix


def locate_response(instructions, fused):
    mix, rgb = (locate_fused_mix if fused else locate_mix)(instructions)
    tail = instructions[mix:mix + 26]
    expected = [50, 0, 52, 50, 29, 1, 0, 50, 29, 1, 54, 0, 50,
                51, 0, 0, 14, 56, 50, 51, 56, 56, 56, 50, 50, 50]
    if [t[0] & 2047 for t in tail] != expected:
        raise ValueError('Unexpected cloth extra-light response tail')
    color, response, combine = tail[-3:]
    # Two audited allocations: processed RGB in yzw -> xyz, or xzw -> xzw.
    layouts = {
        0x00100072: (0x00100796, (7, 7, 7, 0), (.3, .3, .3, 0), 0x00100906),
        0x001000D2: (0x00100E06, (7, 0, 7, 7), (.3, 0, .3, .3), 0x00100E06),
    }
    if len(color) != 15 or color[1] not in layouts:
        raise ValueError('Unexpected cloth material-color layout')
    source, gain, floor, selected = layouts[color[1]]
    if color != emit(50 | 0x2000, color[1], color[2], source, color[2],
                     0x4002, *(imm32(v)[1] for v in gain),
                     0x4002, *(imm32(v)[1] for v in floor)):
        raise ValueError('Unexpected cloth material-color lift')
    if (len(response) != 9 or response[0] != (9 << 24 | 50)
            or response[1:5] != (0x00100072, rgb, 0x00100246, rgb)
            or response[5] not in (0x00100556, 0x00100FF6)
            or response[7] != 0x00100246):
        raise ValueError('Unexpected cloth light-response multiply')
    if (len(combine) != 9 or combine != emit(50, 0x001000D2, combine[2],
            selected, color[2], 0x00100906, rgb, 0x00100E06, combine[2])):
        raise ValueError('Unexpected cloth extra-light addition')
    return mix, rgb, mix + 23


def aggregate_cap(rgb, scratch, profile):
    """Bound the mixed light metric with the existing skin aggregate curve."""
    dest, value = (0x00100012, scratch), (0x0010000A, scratch)
    extra_dest, extra = (0x00100012, scratch + 1), (0x0010000A, scratch + 1)
    result = [emit(52, *dest, 0x0010000A, rgb, 0x0010001A, rgb),
              emit(52, *dest, *value, 0x0010002A, rgb)]
    if profile == 'color-aware':
        result += [emit(16, *extra_dest, 0x00100246, rgb, 0x4002,
                        *(imm32(v)[1] for v in (.212673, .715152, .072175, 0))),
                   emit(0, *dest, *value, *extra), emit(56, *dest, *value, *imm32(.5))]
    # Identity below 0.75; above it, target = .75 + excess/(1 + excess/.75).
    # Scale every RGB channel equally to preserve the accumulated light hue.
    result += [emit(0, *extra_dest, *value, *imm32(-.75)),
               emit(52, *extra_dest, *extra, *imm32(0)),
               emit(50, *dest, *extra, *imm32(1 / .75), *imm32(1)),
               emit(14, *dest, *imm32(1), *value),
               emit(50, *dest, *extra, *value, *imm32(.75)),
               emit(0, *extra_dest, *extra, *imm32(.75)),
               emit(14, *dest, *value, *extra),
               emit(56, 0x00100072, rgb, 0x00100246, rgb, *value)]
    return result


def patch_program(code, *, fused, aggregate=False, preserve_color=False, cap_profile='color-aware'):
    if not aggregate and not preserve_color:
        return code
    if cap_profile not in ('gentle-peak', 'color-aware'):
        raise ValueError('Cloth response requires an experimental cap profile')
    version, instructions = decode_program(code)
    mix, rgb, color = locate_response(instructions, fused)
    if preserve_color:
        old = instructions[color]
        # Keep white at one and true black at zero; remove only the stock
        # additional-light gain/floor, not the material's main-light response.
        instructions[color] = emit(54 | 0x2000, *old[1:5])
    if aggregate:
        declaration, = [i for i, t in enumerate(instructions) if t[0] & 2047 == 104]
        header, spare = instructions[declaration]
        instructions[declaration] = (header, spare + 2)
        instructions[mix + 1:mix + 1] = aggregate_cap(rgb, spare, cap_profile)
    return encode_program(version, instructions)
