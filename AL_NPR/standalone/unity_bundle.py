"""Write a Windows UnityFS bundle of native Unity 6 objects using the public type database."""
from hashlib import sha256
from struct import pack

from UnityPy.helpers.Tpk import get_typetree_node
from UnityPy.helpers.TypeTreeHelper import write_typetree
from UnityPy.helpers.UnityVersion import UnityVersion
from UnityPy.streams import EndianBinaryWriter

ENGINE = "6000.0.65f1"
# Native serialized type hashes for this engine's Windows player.
TYPES = {142: "97da5f4688e45a57c8b42d4f42497297", 48: "2ec7223dce3af4232b14ae1441bd7999"}


def aligned(data, multiple):
    return data + bytes(-len(data) % multiple)


def serialize_objects(objects):
    meta = EndianBinaryWriter(endian="<")
    meta.write_string_to_null(ENGINE)
    meta.write_int(19)  # StandaloneWindows64
    meta.write_boolean(False)  # Fixed player version, native type trees supplied by Unity.
    meta.write_int(len(TYPES))
    nodes = {}
    for class_id, type_hash in TYPES.items():
        node = get_typetree_node(class_id, UnityVersion.from_str(ENGINE))
        nodes[class_id] = node
        meta.write_bytes(pack("<i?h16s", class_id, False, -1, bytes.fromhex(type_hash)))

    data = EndianBinaryWriter(endian="<")
    meta.write_int(len(objects))
    for path_id, (class_id, value) in enumerate(objects, 1):
        start = data.Position
        write_typetree(value, nodes[class_id], data)
        meta.align_stream(4)
        meta.write_bytes(pack("<qqIi", path_id, start, data.Position - start, list(TYPES).index(class_id)))
        data.align_stream(8)
    # Script types, external files, reference types and user information.
    meta.write_bytes(pack("<iiiB", 0, 0, 0, 0))
    offset = (48 + meta.Length + 15) & ~15
    header = pack(">4I4xI3q", 0, 0, 22, 0, meta.Length, offset + data.Length, offset, 0)
    return aligned(header + meta.bytes, 16) + data.bytes


def unity_bundle(objects):
    data = serialize_objects(objects)
    name = b"CAB-" + sha256(data).hexdigest()[:32].encode() + b"\0"
    # Shader programs are already LZ4-compressed. One uncompressed UnityFS
    # block also lets the player stream the serialized file directly.
    table = bytes(16) + pack(">IIIHIqqI", 1, len(data), len(data), 0, 1, 0, len(data), 4) + name
    prefix = b"UnityFS\0" + pack(">I", 8) + b"5.x.x\0" + ENGINE.encode() + b"\0"
    size = ((len(prefix) + 20 + 15) & ~15) + len(table) + len(data)
    return aligned(prefix + pack(">qIII", size, len(table), len(table), 0x40), 16) + table + data
