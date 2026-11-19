[CmdletBinding(DefaultParameterSetName = 'Code')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Code')][string]$Code,
    [Parameter(Mandatory, ParameterSetName = 'File')][string]$File,
    [int]$GameProcessId
)

$ErrorActionPreference = 'Stop'
if ($File) { $Code = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $File).ProviderPath) }
if (!$GameProcessId) {
    $games = @(Get-Process -Name AmanatsuLocation)
    if ($games.Count -ne 1) { throw 'Specify -GameProcessId when more than one game is open.' }
    $GameProcessId = $games[0].Id
}

function Read-Exactly($Stream, [int]$Count, $Deadline) {
    $bytes = [byte[]]::new($Count)
    $offset = 0
    while ($offset -lt $Count) {
        $remaining = $Deadline - [DateTime]::UtcNow
        if ($remaining.TotalMilliseconds -le 0) { throw 'Timed out waiting for the REPL.' }
        $read = $Stream.ReadAsync($bytes, $offset, $Count - $offset)
        if (!$read.Wait($remaining)) { throw 'Timed out waiting for the REPL.' }
        $length = $read.GetAwaiter().GetResult()
        if (!$length) { throw 'The game disconnected during the REPL reply.' }
        $offset += $length
    }
    return ,$bytes
}

$body = [Text.Encoding]::UTF8.GetBytes($Code)
if ($body.Length -lt 1 -or $body.Length -gt 65536) { throw 'Send between 1 and 65536 bytes of UTF-8 C#.' }
$pipe = [IO.Pipes.NamedPipeClientStream]::new('.', "al-dev-repl-$GameProcessId",
    [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
try {
    $pipe.Connect(3000)
    $packet = [byte[]]::new(4 + $body.Length)
    [BitConverter]::GetBytes([int]$body.Length).CopyTo($packet, 0)
    $body.CopyTo($packet, 4)
    if (!$pipe.WriteAsync($packet, 0, $packet.Length).Wait(5000)) { throw 'Timed out sending C#.' }
    $deadline = [DateTime]::UtcNow.AddSeconds(32)
    $header = Read-Exactly $pipe 5 $deadline
    $length = [BitConverter]::ToInt32($header, 1)
    if ($length -lt 0 -or $length -gt 200000) { throw 'Invalid REPL reply size.' }
    $reply = [Text.Encoding]::UTF8.GetString((Read-Exactly $pipe $length $deadline))
    $pipe.WriteByte(0)
    if ($header[0]) { throw $reply }
    if ($reply) { $reply }
} finally {
    $pipe.Dispose()
}
