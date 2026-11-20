"""CPU-only export and pre-initialization rejection checks for native probes."""
import ctypes as c
import argparse
from pathlib import Path


class Mesh(c.Structure):
    _pack_ = 8
    _fields_ = [("vertices", c.c_void_p), ("indices", c.c_void_p),
                ("output", c.c_void_p), ("positionOffset", c.c_uint64),
                ("indexOffset", c.c_uint64), ("stride", c.c_uint32),
                ("verticesCount", c.c_uint32), ("indicesCount", c.c_uint32),
                ("indexBits", c.c_uint32), ("transform", c.c_float * 12),
                ("reserved", c.c_uint64)]


class Frame(c.Structure):
    _pack_ = 8
    _fields_ = [("inverse", c.c_float * 16), ("directions", c.c_float * 128),
                ("width", c.c_uint32), ("height", c.c_uint32),
                ("lights", c.c_uint32), ("testMask", c.c_uint32)]


def main():
    assert c.sizeof(Mesh) == 112 and Mesh.transform.offset == 56
    assert c.sizeof(Frame) == 592
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path(__file__).resolve().parents[2] / "artifacts/npr/unity-ray-probe")
    root = parser.parse_args().directory.resolve()
    mesh = Mesh()
    frame = Frame(width=16, height=16, lights=1)
    for depth, name in ((False, "ALVisibilityRayProbe.dll"), (True, "ALDepthVisibility.dll")):
        dll = c.CDLL(str(root / name))
        queue = getattr(dll, "ALRAY_QueueDepthScene" if depth else "ALRAY_QueueScene")
        queue.restype = c.c_uint64
        queue.argtypes = [c.POINTER(Mesh), c.c_uint32, c.c_void_p,
                          c.POINTER(Frame) if depth else c.c_uint32]
        final = c.byref(frame) if depth else 2
        for count in (0, 1, 4096, 4097):
            assert queue(None, count, None, final) == 0
        # Valid CPU storage with no live Unity device must reject before any
        # resource calls. Sentinel pointers are never dereferenced on this path.
        assert queue(c.byref(mesh), 1, c.c_void_p(1), final) == 0
        old = getattr(dll, "ALRAY_QueueDepth" if depth else "ALRAY_QueueMesh")
        old.restype = c.c_uint64
        old.argtypes = [c.POINTER(Mesh), c.c_void_p,
                        c.POINTER(Frame) if depth else c.c_uint32]
        assert old(None, None, final) == 0
        timings = dll.ALRAY_ReadTimings
        timings.argtypes = [c.c_uint64, c.POINTER(c.c_double), c.POINTER(c.c_double), c.POINTER(c.c_double)]
        timings.restype = c.c_int
        build, trace, copy = c.c_double(123), c.c_double(456), c.c_double(789)
        assert timings(0, c.byref(build), c.byref(trace), c.byref(copy)) == -1
        assert timings(1, None, None, None) == -1
        assert timings(1, c.byref(build), c.byref(trace), c.byref(copy)) == -1
        assert (build.value, trace.value, copy.value) == (123, 456, 789)
        if depth:
            create = dll.ALRAY_CreateScene
            create.argtypes = [c.POINTER(Mesh), c.c_uint32]
            create.restype = c.c_uint64
            for count in (0, 1, 4096, 4097):
                assert create(None, count) == 0
            assert create(c.byref(mesh), 1) == 0
            for export in ('ALRAY_SceneReady', 'ALRAY_ReleaseScene'):
                fn = getattr(dll, export)
                fn.argtypes, fn.restype = [c.c_uint64], c.c_int
                for handle in (0, 1, 2**63):
                    assert fn(handle) == (-1 if export.endswith('Ready') else 0)
            retained = dll.ALRAY_QueueRetainedDepth
            retained.argtypes = [c.c_uint64, c.c_void_p, c.c_void_p, c.POINTER(Frame), c.c_uint32]
            retained.restype = c.c_uint64
            assert retained(1, 1, 2, c.byref(frame), 1) == 0
            assert retained(1, 1, 1, c.byref(frame), 1) == 0
            assert retained(1, 1, 2, c.byref(frame), 2) == 0
            assert dll.ALRAY_RequestsIdle() == 1
            summary = dll.ALRAY_ReadDepthSummary
            summary.argtypes = [c.c_uint64, c.POINTER(c.c_uint32), c.POINTER(c.c_uint32)]
            summary.restype = c.c_int
            valid, blocked = c.c_uint32(123), c.c_uint32(456)
            assert summary(0, c.byref(valid), c.byref(blocked)) == -1
            assert summary(1, None, None) == -1
            assert summary(1, c.byref(valid), c.byref(blocked)) == -1
            assert (valid.value, blocked.value) == (123, 456)
        assert dll.ALRAY_CanUnload() == 1
        dll.UnityPluginUnload()
        print(f"{name}: scene export, original export, ABI layout, invalid-input and unwarmed rejection passed")


if __name__ == "__main__":
    main()
