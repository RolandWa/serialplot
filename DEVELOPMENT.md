# serialplot — Development & Testing Guide (Windows)

## Build

Uses MSYS2 ucrt64 + Qt 6.8 + Qwt 6.3. Always build with the provided script.

```powershell
.\build_windows.ps1 -Install
```

- `-Install` is mandatory — runs `windeployqt` and copies runtime DLLs into `build-windows\install\bin\`.
- Without `-Install` the exe fails to start (missing DLLs).

---

## Full test sequence

Run this block from the repo root. It opens a **visible terminal window** for the UDP sender, verifies packets are flowing, then launches serialplot with debug logging.

```powershell
# 1. Find real Python (skip Microsoft Store stub which exits with code 255)
$python = @(
    "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

$repo = Split-Path -Parent (Resolve-Path ".")

# 2. Open a NEW PowerShell window showing sender output — keep it open
$script = "$repo\tests\udp_sender.py"
Start-Process powershell -ArgumentList "-NoExit", "-Command", "& '$python' -u '$script'"

Start-Sleep 2

# 3. Verify sender is actually sending on port 3000
$r = New-Object System.Net.Sockets.UdpClient(3000)
$r.Client.ReceiveTimeout = 2000
try {
    $ep = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
    $d  = $r.Receive([ref]$ep)
    Write-Host "SENDER OK: $([System.Text.Encoding]::UTF8.GetString($d).Trim())"
} catch {
    Write-Host "ERROR: sender not sending — check the Python window for errors"
    return
} finally { $r.Close() }

Start-Sleep 1   # release port 3000 before serialplot binds it

# 4. Clear log and start serialplot with debug capture
$log = "$repo\build-windows\debug.log"
[System.IO.File]::WriteAllText($log, "")
Start-Process "$repo\build-windows\install\bin\serialplot.exe" -RedirectStandardError $log

Write-Host "serialplot started."
Write-Host "  In the app: 1) UDP tab -> Bind   2) Data Format -> ASCII"
Write-Host "  Close serialplot when done, then read the log (block below)."
```

After closing serialplot, read the log:

```powershell
Get-Content "$repo\build-windows\debug.log"
```

---

## Connect serialplot to UDP data

1. Click the **UDP** tab
2. Bind Address: `127.0.0.1`, Port: `3000`
3. Click **Bind** — status shows "Bound to 127.0.0.1:3000"
4. Click the **Data Format** tab → select **ASCII**
5. Set **Number of channels** to **Auto** (spinbox value 0)
6. Plot shows live data on 3 channels — legend shows **temp**, **humidity**, **pressure**

---

## How Arduino-style labels work

The UDP sender sends lines like `temp:22.5,humidity:58.1,pressure:1015.0`.

serialplot automatically detects `key:value` pairs and uses the keys as channel names:

- The ASCII reader splits on `,` (auto-detected delimiter)
- `key:value` fields: the key becomes the channel name, the value is plotted
- Channel count is auto-detected from the first parsed line
- Names appear in the plot legend and the Names tab in Plot Control

**Settings required for this to work:**

- Delimiter: **Auto** (or **Comma**)
- Number of channels: **Auto** (spinbox = 0)

---

## Key log messages

| Message | Meaning |
| --- | --- |
| `[UDP] bound to "127.0.0.1" port 3000` | Socket bound OK |
| `[UDP] bind failed: ...` | Port in use or firewall blocking |
| `[UDP] rx: "temp:..."` | Datagram received — sender is working |
| `[Debug] SerialPlot 0.12.1` | App started, version confirmed |

**No `[UDP] rx:` after clicking Bind?**

- Sender window closed — rerun the start block, check `SENDER OK` line
- Try Bind Address `0.0.0.0` instead of `127.0.0.1`

**`[UDP] rx:` appears but plot is empty?**

- ASCII not selected — Data Format tab → ASCII radio button

**Values plot but channel names show "Channel 1, 2, 3"?**

- Number of channels is not set to Auto — set spinbox to 0

---

## Bugs fixed in this branch (feature/port-to-qt6)

| Bug | Root cause | Fix |
| --- | --- | --- |
| UDP data never parsed by ASCII reader | Qt 6 `QIODevice::canReadLine()` only checks internal buffer, ignoring `UdpLineDevice::_buf` | Override `canReadLine()` in `UdpLineDevice` to also check `_buf.contains('\n')` |
| Arduino-style channel names not applied | `DataFormatPanel::selectReader()` called twice on startup via `loadSettings` (explicit call + radio button signal), second call ran `disconnect(&asciiReader, 0, this, 0)` destroying the `labelsReceived` connection | Guard `selectReader()` with `if (reader == currentReader) return` |
| Channel names emitted before channels existed | `labelsReceived` emitted before `updateNumChannels()` in auto-channel mode, so `ChannelInfoModel::setNames` found `_numOfChannels = 0` | Move `emit labelsReceived` to after `updateNumChannels()` inside `if (samples != nullptr)` |
