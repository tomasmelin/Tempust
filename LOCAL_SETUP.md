# Running Tempust locally on your Forerunner 965

A step-by-step guide for an experienced developer who's new to the
Garmin Connect IQ toolchain specifically. Covers the CLI path (faster
once set up, no IDE required) and the VS Code path (more guardrails,
better for a first run) on **macOS, Linux, and Windows**. Pick one
platform section and one path — you don't need both paths.

Every step below is written for all three platforms; where a command
differs, both are shown labelled **macOS/Linux** and **Windows**
(PowerShell, unless noted otherwise — Command Prompt equivalents are
called out where they diverge from PowerShell).

## 0. Prerequisites

- **A JDK** (Java 11+). The SDK Manager and simulator are Java apps.

  - **macOS/Linux:** check with `java -version`. If missing:
    `brew install openjdk` (macOS) or `apt install openjdk-17-jdk`
    (Debian/Ubuntu), or the equivalent for your distro.
  - **Windows:** check with `java -version` in PowerShell or Command
    Prompt. If missing, install a JDK from
    [adoptium.net](https://adoptium.net) (pick the MSI installer, it
    sets up `PATH` and `JAVA_HOME` for you), or via winget:
    `winget install EclipseAdoptium.Temurin.17.JDK`.

- **A USB cable** for the watch.
- **Garmin Connect Mobile** installed and paired with your FR965 on
  your phone (needed at runtime for `Communications.makeWebRequest` to
  reach the internet — the watch itself has no WiFi/cellular).

## 1. Install the Connect IQ SDK

1. Download the **Connect IQ SDK Manager** from
   developer.garmin.com/connect-iq/sdk/ (available for macOS, Windows,
   Linux).
2. Run it, accept the license, and install the latest SDK. It also
   lets you download specific device simulator profiles — make sure
   **Forerunner 965** is checked.
3. Note the SDK install path and add its `bin/` directory to your
   `PATH` so `monkeyc`, `monkeydo` and `connectiq` are available as
   plain shell commands:

   **macOS/Linux** — install path is typically
   `~/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-<version>`
   (macOS). Add to your shell profile (`.zshrc`, `.bashrc`, etc.) so
   it persists:

   ```bash
   export PATH="$PATH:/path/to/connectiq-sdk-<version>/bin"
   ```

   **Windows** — install path is typically
   `%APPDATA%\Garmin\ConnectIQ\Sdks\connectiq-sdk-<version>`. Add its
   `bin` folder to `PATH` permanently via **Settings → System → About
   → Advanced system settings → Environment Variables**, edit the
   `Path` variable under "User variables", and add a new entry
   pointing at, e.g., `C:\Users\<you>\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-<version>\bin`.
   Close and reopen any terminal afterward. To set it just for your
   current PowerShell session instead (no restart needed, but doesn't
   persist):

   ```powershell
   $env:Path += ";C:\Users\<you>\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-<version>\bin"
   ```

## 2. Generate a developer signing key (one-time)

Every Connect IQ binary must be signed. Generate your own key pair
once — reuse it for every future build/app, don't regenerate per
project.

**macOS/Linux:**

```bash
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

**Windows:** Windows doesn't ship `openssl` by default, so use one of:

- **Git for Windows** (if installed, most people already have it) —
  open **"Git Bash"** from the Start menu and run the exact same two
  commands as macOS/Linux above; Git Bash bundles OpenSSL.
- **Native OpenSSL for Windows** — install via
  `winget install ShiningLight.OpenSSL` (or the installer from
  [slproweb.com/products/Win32OpenSSL.html](https://slproweb.com/products/Win32OpenSSL.html)),
  then run the same two `openssl` commands from PowerShell or Command
  Prompt.

Either way you end up with `developer_key.der` — that's the file the
`-y` flag in step 4 needs.

Keep `developer_key.der` somewhere durable outside the repo (e.g.
`~/.garmin/developer_key.der` on macOS/Linux, or
`C:\Users\<you>\.garmin\developer_key.der` on Windows) — losing it
just means you'd generate a new one for future builds, no real harm
for personal sideloading, but it's good hygiene to not lose track of
it.

## 3. Set up the project

Unzip the Tempust archive I sent you, then:

1. **Give it a real UUID.** The `id` in `manifest.xml` is currently a
   placeholder (`00000000-...`). Generate a real one and swap it in:
      4498b8b3-7592-4298-9c36-fd7e36ceba55
   **macOS/Linux:**

   ```bash
   uuidgen   # on Linux you may need `apt install uuid-runtime` first
   ```

   **Windows** (PowerShell):

   ```powershell
   [guid]::NewGuid()
   ```
      1de83b78-c0ce-40c0-b717-0f98fdb37f48
   
   Or, on any platform, from Python: `python3 -c "import uuid; print(uuid.uuid4())"`
   (use `python` instead of `python3` on most Windows installs).

2. **Add a jungle file.** This is the piece a raw source drop doesn't
   include — it tells the compiler where source/resources live. Create
   `monkey.jungle` in the project root with:

   ```
   project.manifest = manifest.xml
   ```

   (This one line is enough — the compiler defaults to `source/**` and
   `resources/**`, which already matches this project's layout, on
   every platform.)

Your project root should now look like this on any OS (Windows just
uses backslashes when it prints paths, the layout is identical):

```
tempust-widget/
├── manifest.xml
├── monkey.jungle
├── source/
│   ├── TempustApp.mc
│   ├── TempustView.mc
│   ├── TempustDelegate.mc
│   └── TempustWeatherClient.mc
└── resources/
    ├── strings/strings.xml
    ├── properties/properties.xml
    ├── settings/settings.xml
    └── drawables/{drawables.xml, launcher_icon.png}
```

## 4. Build it (CLI)

From the project root:

**macOS/Linux:**

```bash
monkeyc -o bin/Tempust.prg -f monkey.jungle -y /path/to/developer_key.der -d fr965 -w
```

**Windows** (PowerShell or Command Prompt — identical syntax once
`monkeyc` is on `PATH`):

```powershell
monkeyc -o bin\Tempust.prg -f monkey.jungle -y C:\Users\TomasMelin\.garmin\developer_key.der -d fr965 -w
```

- `-o` output file
- `-f` jungle file
- `-y` your signing key
- `-d` target device id (must match one of the `<iq:product id="...">`
  entries in `manifest.xml`)
- `-w` show compiler warnings (worth fixing before you move on)

A clean build produces `bin/Tempust.prg` (or `bin\Tempust.prg` on
Windows) with no errors. Run `monkeyc --help` for the full flag
reference if you want optimization levels, debug symbols, etc.

## 5. Run it in the simulator

Two-step: start the simulator once, then push builds into it.

**macOS/Linux:**

```bash
connectiq &          # launches the Connect IQ Simulator app, pick fr965 as the device
monkeydo bin/Tempust.prg fr965
```

**Windows** (PowerShell):

```powershell
Start-Process connectiq   # launches the Connect IQ Simulator app, pick fr965 as the device
monkeydo bin\Tempust.prg fr965
```

(In Command Prompt, `start connectiq` does the same thing. Either way,
launching it detached lets you keep using the same terminal for
`monkeydo`.)

`monkeydo` loads and launches your `.prg` in whatever simulator
instance is already running — rerun it after every rebuild instead of
restarting `connectiq`.

**Fake a GPS position** (the widget needs one): in the simulator
window, go to `Simulation → Location` and enter coordinates, e.g.
`56.6634, 16.3566` for Kalmar. Without this the widget will sit on
"No GPS position yet". Identical on every platform — this is the
simulator's own UI, not a shell command.

**Toggle Celsius/Fahrenheit:** the simulator exposes app settings the
same way the phone does — look for the gear/settings icon in the
simulator toolbar, or right-click the running app; it opens the same
settings form driven by `resources/settings/settings.xml`. Same on
every platform.

**Console output:** anything you `System.println(...)` in Monkey C
shows up in the terminal you launched `connectiq` from — your main
debugging tool here, on any OS.

## 6. Deploy to the physical watch

1. Connect the FR965 via USB. It mounts as a mass-storage volume.

   - **macOS:** appears as a volume named something like `GARMIN` in
     Finder / on the desktop.
   - **Linux:** usually auto-mounts under `/media/<user>/GARMIN` or
     similar; if it doesn't auto-mount, check your file manager or
     `lsblk`.
   - **Windows:** appears as a new drive letter (e.g. `E:\`) in File
     Explorer, named `GARMIN`.

2. Copy the built `.prg` into the `APPS` folder on the watch (create
   it if it isn't there, though on the FR965 it should already exist):

   - **macOS/Linux:** copy `bin/Tempust.prg` to `GARMIN/APPS/`.
   - **Windows:** copy `bin\Tempust.prg` to `E:\GARMIN\APPS\`
     (substitute the actual drive letter File Explorer assigned).

3. Safely eject/unmount the volume before physically disconnecting.

   - **macOS:** drag the volume to Trash, or click the eject icon in
     Finder's sidebar.
   - **Linux:** use your file manager's "eject"/"unmount", or
     `umount /media/<user>/GARMIN`.
   - **Windows:** use **"Safely Remove Hardware"** in the system tray,
     or right-click the drive in File Explorer → **Eject**.

4. Restart the watch if the new widget doesn't show up immediately —
   swipe through your widget glances to find **Tempust**.

## 7. Iterating

- Code change → rerun the `monkeyc` command from step 4 → `monkeydo`
  again for the simulator, or re-copy the `.prg` over USB for the real
  watch. Same loop on every platform.
- There's no hot-reload; every change needs a rebuild.

## VS Code path (alternative to raw CLI)

Identical steps on macOS, Linux, and Windows — VS Code and its Monkey
C extension abstract away the platform differences:

1. Install the **"Monkey C"** VS Code extension (by Garmin).
2. `Ctrl+Shift+P` (`Cmd+Shift+P` on macOS) → **"Monkey C: New
   Project"** → type **Widget** → device **fr965**. This generates
   manifest, jungle file, and a real UUID for you.
3. Overwrite the generated `source/` and `resources/` files with the
   ones from this repo (keep the SDK-generated `manifest.xml`'s `id`,
   but merge in the `<iq:products>`, `<iq:permissions>` and
   `<iq:languages>` blocks from this repo's `manifest.xml`).
4. `Ctrl+Shift+P`/`Cmd+Shift+P` → **"Monkey C: Run current project in
   Connect IQ simulator"** for step 5 above, and **"Monkey C: Build
   for Device"** for step 6 — same underlying `monkeyc`/`monkeydo`
   calls, just wrapped in commands, and the extension handles signing
   key + `PATH` setup for you if you let it generate the key through
   its own prompts.

## Common gotchas

- **Build fails with an unknown product id** — you typo'd a device id
  in `manifest.xml`, or that device isn't in your installed SDK's
  device list. Check `manifest.xml` against the SDK Manager's device
  list.
- **Widget stuck on "Locating..."** — you're testing indoors on a real
  watch with a weak GPS signal, or forgot to set a location in the
  simulator. Go outside / set `Simulation → Location`.
- **`Error: 400`-style codes from `onReceive`** — usually the
  temperatur.nu rate limit (max one identical request per 5 minutes
  per client id) kicking in from repeated manual testing. Wait a few
  minutes or vary the `cli` parameter (i.e. `CLIENT_ID` constant)
  temporarily while iterating.
- **`java: command not found`** (macOS/Linux) or **`'java' is not
  recognized as an internal or external command`** (Windows) — install
  a JDK and make sure it's on `PATH` (step 0). On Windows, a fresh
  terminal window is needed after installing the JDK for the updated
  `PATH` to take effect.
- **`monkeyc`/`monkeydo`/`connectiq` not found** — the SDK's `bin`
  folder isn't on `PATH`, or you didn't open a new terminal after
  adding it (Windows especially — `PATH` changes made via System
  Properties don't apply to already-open terminals).
- **Windows: "running scripts is disabled on this system"** in
  PowerShell — this is PowerShell's execution policy blocking a
  script, not a Connect IQ problem specifically; it typically doesn't
  affect the commands in this guide (they're plain executables, not
  `.ps1` scripts), but if you hit it while using an installer script,
  run PowerShell as Administrator and
  `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` once.
- **Nothing shows up on the watch after copying the `.prg`** — you
  likely disconnected before the OS finished flushing the write.
  Always eject/unmount properly before unplugging (see step 6).
