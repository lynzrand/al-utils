using System.IO.Pipes;
using System.Text;

namespace AL_DevRepl;

internal readonly record struct Reply(bool Success, string Text);

// The worker owns the pipe. Unity claims submissions from Update so the
// evaluator and any game objects accessed by a command stay on the main thread.
internal sealed class ReplPipe : IDisposable
{
    private readonly CancellationTokenSource stopped = new();
    private Submission? pending;

    public ReplPipe(string name, Action<string> report)
    {
        _ = Serve(name, report, stopped.Token);
    }

    public void RunPending(Func<string, Reply> run)
    {
        var command = Interlocked.Exchange(ref pending, null);
        if (command is not null)
            command.Reply.TrySetResult(run(command.Code));
    }

    private async Task Serve(string name, Action<string> report, CancellationToken stop)
    {
        while (!stop.IsCancellationRequested)
        {
            try
            {
                using var pipe = new NamedPipeServerStream(name, PipeDirection.InOut, 1,
                    PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(stop).ConfigureAwait(false);
                using var io = CancellationTokenSource.CreateLinkedTokenSource(stop);
                io.CancelAfter(TimeSpan.FromSeconds(5));
                var header = new byte[5];
                await ReadExactly(pipe, header.AsMemory(0, 4), io.Token).ConfigureAwait(false);
                int length = BitConverter.ToInt32(header, 0);
                if (length is < 1 or > 65536) continue;
                var data = new byte[length];
                await ReadExactly(pipe, data, io.Token).ConfigureAwait(false);
                io.CancelAfter(Timeout.InfiniteTimeSpan);
                var reply = await Submit(Encoding.UTF8.GetString(data), stop).ConfigureAwait(false);

                io.CancelAfter(TimeSpan.FromSeconds(5));
                var body = Encoding.UTF8.GetBytes(reply.Text[..Math.Min(reply.Text.Length, 65536)]);
                header[0] = reply.Success ? (byte)0 : (byte)1;
                BitConverter.TryWriteBytes(header.AsSpan(1), body.Length);
                await pipe.WriteAsync(header, io.Token).ConfigureAwait(false);
                await pipe.WriteAsync(body, io.Token).ConfigureAwait(false);
                // The client acknowledges the reply before we close the pipe.
                await ReadExactly(pipe, header.AsMemory(0, 1), io.Token).ConfigureAwait(false);
            }
            catch (IOException) { }
            catch (OperationCanceledException) { }
            catch (Exception error)
            {
                report(error.Message);
                return;
            }
        }
    }

    private async Task<Reply> Submit(string code, CancellationToken stop)
    {
        var command = new Submission(code);
        Interlocked.Exchange(ref pending, command);
        try
        {
            return await command.Reply.Task.WaitAsync(TimeSpan.FromSeconds(25), stop).ConfigureAwait(false);
        }
        catch (TimeoutException)
        {
            bool queued = Interlocked.CompareExchange(ref pending, null, command) == command;
            return new Reply(false, queued ? "Unity did not start the command. It was canceled."
                : "The command started on Unity's main thread and may still be running.");
        }
    }

    private static async Task ReadExactly(Stream stream, Memory<byte> bytes, CancellationToken stop)
    {
        while (!bytes.IsEmpty)
        {
            int count = await stream.ReadAsync(bytes, stop).ConfigureAwait(false);
            if (count == 0) throw new EndOfStreamException();
            bytes = bytes[count..];
        }
    }

    public void Dispose()
    {
        stopped.Cancel();
        Interlocked.Exchange(ref pending, null);
        stopped.Dispose();
    }

    private sealed record Submission(string Code)
    {
        public TaskCompletionSource<Reply> Reply { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    }
}
