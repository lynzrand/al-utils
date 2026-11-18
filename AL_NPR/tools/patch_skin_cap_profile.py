"""Replace audited skin rolloffs with monotone, identity-below-knee curves.

These experimental profiles change lighting only. They do not correct the
separate SH-derived palette selection or add visibility to any material.
"""

from patch_skin_light_shoulder import decode_program, encode_program, emit, imm32


PROFILES = ("legacy", "gentle-peak", "color-aware")


def patch_program(code, profile):
    if profile not in PROFILES:
        raise ValueError(f"Unknown cap profile: {profile}")
    if profile == "legacy":
        return code
    version, instructions = decode_program(code)
    declaration, = [i for i, t in enumerate(instructions) if t[0] & 2047 == 104]
    header, spare = instructions[declaration]
    instructions[declaration] = (header, spare + 1)
    extra_dest, extra = (0x00100012, spare), (0x0010000A, spare)
    replacements = {}
    for i in range(len(instructions) - 5):
        block = instructions[i:i + 6]
        if [t[0] & 2047 for t in block] != [52, 52, 0, 52, 50, 14]:
            continue
        a, b, c, d, e, f = block
        kind = ((c[-2:] == imm32(-0.10) and e[-4:] == (*imm32(7), *imm32(1)))
                or (c[-2:] == imm32(-0.18) and e[-4:] == (*imm32(4.5), *imm32(1))))
        if not kind:
            continue
        dest, scalar = a[1:3], b[3:5]
        if not (all(t[1:3] == dest for t in block[:6])
                and a[3:7] == (0x0010000A, a[4], 0x0010001A, a[4])
                and b[5:7] == (0x0010002A, a[4])
                and c[3:5] == scalar and d[3:5] == scalar
                and e[3:5] == scalar
                and d[-2:] == imm32(0) and f[3:5] == imm32(1)
                and f[5:7] == scalar):
            raise ValueError("Unexpected rolloff operands")
        # Both stages keep ordinary inputs intact. The aggregate ceiling is
        # higher to allow several moderate lights to contribute together.
        aggregate = c[-2:] == imm32(-0.18)
        knee, ceiling = (0.75, 1.5) if aggregate else (0.5, 1.0)
        metric = [a, b]
        if profile == "color-aware":
            # Blend luminance with peak: saturated sources retain more energy
            # than with peak alone, while peak still limits extreme channels.
            rgb_register = a[4]
            metric += [
                emit(16, *extra_dest, 0x00100246, rgb_register, 0x4002,
                     imm32(0.212673)[1], imm32(0.715152)[1], imm32(0.072175)[1], 0),
                emit(0, *dest, *scalar, *extra),
                emit(56, *dest, *scalar, *imm32(0.5)),
            ]
        replacements[i] = [*metric,
            emit(54, *extra_dest, *scalar),
            emit(0, *dest, *scalar, *imm32(-knee)),
            emit(52, *dest, *scalar, *imm32(0)),
            emit(50, *dest, *scalar, *imm32(1 / (ceiling - knee)), *imm32(1)),
            emit(14, *dest, *imm32(1), *scalar),
            # Above the knee, target = knee + excess/(1+excess/range).
            # Below it, numerator and denominator both become knee.
            emit(0, *extra_dest, *extra, *imm32(-knee)),
            emit(52, *extra_dest, *extra, *imm32(0)),
            emit(50, *dest, *extra, *scalar, *imm32(knee)),
            # Recover metric as excess+knee; below knee scale must stay one.
            emit(0, *extra_dest, *extra, *imm32(knee)),
            emit(14, *dest, *scalar, *extra),
        ]
    if len(replacements) != 3:
        raise ValueError(f"Expected directional, punctual and aggregate caps, got {len(replacements)}")
    output, i = [], 0
    while i < len(instructions):
        if i in replacements:
            output.extend(replacements[i])
            i += 6
        else:
            output.append(instructions[i])
            i += 1
    return encode_program(version, output)
