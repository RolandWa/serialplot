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

## Building a Windows installer

Requires MSYS2 + NSIS (installed automatically by the script).

```powershell
.\build_windows.ps1 -Install -Package
```

Output: `build-windows\serialplot-<version>-win64.exe`

The `-Package` flag installs `mingw-w64-ucrt-x86_64-nsis` via pacman and runs `cpack -G NSIS`.

---

## Publishing a GitHub release

Requires the [GitHub CLI](https://cli.github.com/) (`gh`). Install via:

```powershell
winget install --id GitHub.cli
gh auth login
```

### Tag the source commit

```powershell
git tag -a "serialplot-<version>" -m "serialplot <version>"
git push origin "serialplot-<version>"
```

### Create the release and upload the installer

```powershell
gh release create "serialplot-<version>" "build-windows\serialplot-<version>-win64.exe" `
  --repo "RolandWa/serialplot" `
  --title "v<version> — <short description>" `
  --notes "Release notes here"
```

Releases are published at: [github.com/RolandWa/serialplot/releases](https://github.com/RolandWa/serialplot/releases)

---

## Ubuntu / Debian build (WSL)

Ubuntu 26.04 (and 22.04+) does not ship `libqwt-qt6-dev`, so Qwt 6.3 is built from source via CMake's `ExternalProject`. Use the provided script — do **not** use the manual cmake commands in the original README.

```bash
# Inside WSL Ubuntu — run from the repo root (Windows path via /mnt/c/...)
./build_ubuntu.sh --package
```

The script:

1. Installs Qt 6 build dependencies via `apt`
2. Builds Qwt 6.3 first (`cmake --build --target QWT`)
3. Builds serialplot
4. Runs `cpack -G DEB` → `serialplot_0.12.1_amd64.deb`
5. Copies the `.deb` back to the repo root (Windows-accessible)

Build directory is `$HOME/serialplot-build-ubuntu` (WSL native fs, survives WSL restarts).

**Note:** Build dir `/tmp/serialplot-build-ubuntu` is lost on WSL restart — always use `$HOME/`.

Upload to the GitHub release:

```bash
gh release upload "serialplot-0.12.1" serialplot_0.12.1_amd64.deb \
  --repo RolandWa/serialplot
```

Install the package:

```bash
sudo dpkg -i serialplot_0.12.1_amd64.deb
sudo apt-get install -f   # fix any missing dependencies
```

---

## TODO — future work

### #1 — Repeat interval for GUI Commands

**Reference:** [hyOzd/serialplot#1](https://github.com/hyOzd/serialplot/issues/1)

Add a repeat interval control to the end of each command row in the Commands panel so that a command can be sent automatically at a configurable rate.

**Proposed UI** (right side of each `CommandWidget` row):

| Control | Type | Details |
| --- | --- | --- |
| Repeat toggle | `QCheckBox` or `QToolButton` | Enables / disables periodic sending |
| Interval value | `QSpinBox` (sbInterval) | Range 1–99999, default 1000 |
| Unit selector | `QComboBox` (cbUnit) | Items: `ms`, `s` |

**Implementation sketch:**

```cpp
// commandwidget.h
QTimer _repeatTimer;
int intervalMs() const;      // converts spinbox + unit to milliseconds
private slots:
    void onRepeatToggled(bool enabled);
    void onIntervalChanged();
```

```cpp
// commandwidget.cpp
connect(&_repeatTimer, &QTimer::timeout, this, &CommandWidget::onSendClicked);

void CommandWidget::onRepeatToggled(bool enabled) {
    if (enabled)
        _repeatTimer.start(intervalMs());
    else
        _repeatTimer.stop();
}

int CommandWidget::intervalMs() const {
    int v = ui->sbInterval->value();
    return ui->cbUnit->currentText() == "s" ? v * 1000 : v;
}
```

**Files to change:**

| File | Change |
| --- | --- |
| `src/commandwidget.h` | Add `QTimer`, `intervalMs()`, repeat slot declarations |
| `src/commandwidget.cpp` | Implement repeat logic; stop timer in destructor |
| `src/commandwidget.ui` | Add Repeat checkbox, sbInterval spinbox, cbUnit combobox |
| `src/commandpanel.cpp` | Stop all repeat timers when the port / UDP socket is closed |

Settings: save/load repeat state, interval value, and unit alongside existing command settings in `CommandWidget::saveSettings` / `loadSettings`.

---

## Bugs fixed in this branch (feature/port-to-qt6)

| Bug | Root cause | Fix |
| --- | --- | --- |
| UDP data never parsed by ASCII reader | Qt 6 `QIODevice::canReadLine()` only checks internal buffer, ignoring `UdpLineDevice::_buf` | Override `canReadLine()` in `UdpLineDevice` to also check `_buf.contains('\n')` |
| Arduino-style channel names not applied | `DataFormatPanel::selectReader()` called twice on startup via `loadSettings` (explicit call + radio button signal), second call ran `disconnect(&asciiReader, 0, this, 0)` destroying the `labelsReceived` connection | Guard `selectReader()` with `if (reader == currentReader) return` |
| Channel names emitted before channels existed | `labelsReceived` emitted before `updateNumChannels()` in auto-channel mode, so `ChannelInfoModel::setNames` found `_numOfChannels = 0` | Move `emit labelsReceived` to after `updateNumChannels()` inside `if (samples != nullptr)` |
