extern alias unity;
using System.Buffers.Binary;
using System.Runtime.InteropServices;
using unity::UnityEngine;
using unity::UnityEngine.Rendering;

namespace AL_NPR;

internal sealed class VisibilityMeshBuffers(Vector3[] positions, byte[] indexBuffer, int indexSize)
{
    internal Vector3[] Positions { get; } = positions;

    internal static VisibilityMeshBuffers Read(Mesh mesh)
    {
        const VertexAttribute position = VertexAttribute.Position;
        if (!mesh.HasVertexAttribute(position) || mesh.GetVertexAttributeDimension(position) != 3 ||
            mesh.GetVertexAttributeFormat(position) != VertexAttributeFormat.Float32)
            throw new NotSupportedException("Mesh does not have Float32x3 positions.");

        int stream = mesh.GetVertexAttributeStream(position);
        int stride = mesh.GetVertexBufferStride(stream);
        int offset = mesh.GetVertexAttributeOffset(position);
        if (offset < 0 || stride < 12 || offset > stride - 12)
            throw new InvalidDataException("Invalid position layout in vertex buffer.");

        byte[] vertexBuffer = ReadBuffer(mesh.GetVertexBuffer(stream));
        byte[] indexBuffer = ReadBuffer(mesh.GetIndexBuffer());
        var positions = new Vector3[mesh.vertexCount];
        if ((long)positions.Length * stride > vertexBuffer.Length)
            throw new InvalidDataException("Vertex buffer is shorter than its mesh layout.");

        for (int index = 0; index < positions.Length; index++)
        {
            var bytes = vertexBuffer.AsSpan(index * stride + offset, 12);
            positions[index] = new Vector3(BinaryPrimitives.ReadSingleLittleEndian(bytes),
                BinaryPrimitives.ReadSingleLittleEndian(bytes[4..]), BinaryPrimitives.ReadSingleLittleEndian(bytes[8..]));
        }
        return new VisibilityMeshBuffers(positions, indexBuffer, mesh.indexFormat == IndexFormat.UInt16 ? 2 : 4);
    }

    internal int[] GetIndices(SubMeshDescriptor submesh)
    {
        if (submesh.indexStart < 0 || submesh.indexCount < 0 ||
            (long)submesh.indexStart + submesh.indexCount > indexBuffer.Length / indexSize)
            throw new InvalidDataException("Submesh index range exceeds its GPU buffer.");

        var result = new int[submesh.indexCount];
        for (int index = 0; index < result.Length; index++)
        {
            var bytes = indexBuffer.AsSpan((submesh.indexStart + index) * indexSize, indexSize);
            uint value = indexSize == 2 ? BinaryPrimitives.ReadUInt16LittleEndian(bytes) :
                BinaryPrimitives.ReadUInt32LittleEndian(bytes);
            result[index] = checked((int)((long)value + submesh.baseVertex));
        }
        return result;
    }

    private static byte[] ReadBuffer(GraphicsBuffer? buffer)
    {
        if (buffer is null) throw new InvalidDataException("Mesh GPU buffer is unavailable.");
        try
        {
            // This synchronous read serves an explicit diagnostic snapshot.
            // A live ray pass must keep geometry on the GPU.
            var request = AsyncGPUReadback.Request(buffer);
            request.WaitForCompletion();
            if (!request.done || request.hasError || request.layerCount != 1 || request.layerDataSize <= 0)
                throw new InvalidDataException("GPU mesh readback failed.");
            var address = request.GetDataRaw(0);
            if (address == IntPtr.Zero) throw new InvalidDataException("GPU mesh readback returned no data.");
            var bytes = new byte[request.layerDataSize];
            Marshal.Copy(address, bytes, 0, bytes.Length);
            return bytes;
        }
        finally
        {
            buffer.Dispose();
        }
    }
}
