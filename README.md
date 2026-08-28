# Tempust – Connect IQ widget for Garmin watches

A Garmin Connect IQ widget that fetches the temperature from your
**nearest measuring station** via the [temperatur.nu](https://www.temperatur.nu)
API, based on the watch's GPS position.

## What changed in this version

- **Name:** the app is now called **Tempust**, source files are named
  `TempustApp.mc`, `TempustView.mc`, `TempustDelegate.mc`.
- **Structure:** networking/GPS logic is split out into its own class,
  `TempustWeatherClient.mc`, separate from the UI code in
  `TempustView.mc` – clearer separation of concerns and easier to
  test/reuse.
- **Settings – temperature unit:** a proper Connect IQ App Setting
  (`resources/properties/properties.xml` +
  `resources/settings/settings.xml`) lets the user pick Celsius or
  Fahrenheit from Garmin Connect Mobile (Device → Apps → Tempust →
  Settings). **Celsius is the default**, since temperatur.nu always
  reports readings in Celsius (no conversion needed on that path).
  The app only converts for display if the user picked Fahrenheit.
  Changing the setting while the widget is open updates the reading
  immediately, via `onSettingsChanged()`.
- **Broad device support:** `manifest.xml` lists every GPS-capable,
  Widget-supporting device in the SDK catalog that actually compiles
  against this app's `minSdkVersion` (watches, handheld GPS units, and
  bike computers alike) instead of just the fr965 – see "Device
  support" below for what's included/excluded and why.
- **Attribution:** a small "temperatur.nu" line is shown at the bottom
  of the widget whenever a reading is displayed, to satisfy
  temperatur.nu's terms of use around crediting the source. Distance
  to the measuring station is shown next to its name instead.
- **New icon:** a clearer 80×80 thermometer icon (a larger source
  resolution downsamples more cleanly on high-res AMOLED watches than
  the old 40×40 placeholder).

## How it works

1. The widget requests a GPS fix from the watch (a cached fix is used
   immediately if the watch already has one).
2. The position is sent to `https://api.temperatur.nu/tnu_1.20.php`
   with `num=1` (nearest station) and `sensor_type=air`. The response
   includes the station's `id`.
3. That `id` is used for a follow-up request (`p=<id>&data=1&span=1day`)
   to fetch the station's last ~24h of readings for the trend graph. A
   failure here doesn't affect the current reading - it's shown either
   way, just without a graph underneath.
4. The full widget shows the temperature at the top with the 24h graph
   below it. The glance shows a compact one-row summary instead,
   styled like Connect IQ's own glances (a round icon badge on a blue
   fading background, matching the look of e.g. the Notifications
   glance) - there's no room for a graph in a single row.
5. The widget refreshes automatically every 5 minutes while open (and
   stops polling as soon as you leave it – no background activity), or
   on demand via SELECT. The glance does a single fetch each time it's
   shown, per Connect IQ's Glance guidance.

The watch needs to be paired with the Garmin Connect app (with an
internet connection) for `Communications.makeWebRequest` to work –
most of the devices listed below don't have their own WiFi/cellular
and rely on the phone's connection.

## Device support

`manifest.xml` lists every device in the SDK's catalog that (a)
supports the Widget app type and (b) actually compiles against this
app's `minSdkVersion` (3.1.8) - checked by compiling individually for
each one, not by guessing from a device's release date or product
line. That covers watches (Forerunner, fenix, epix, MARQ, tactix,
enduro, vivoactive, Venu, Instinct, D2, Approach, Descent), handheld
GPS units (GPSMAP, Montana, eTrex Touch), and bike computers (Edge)
alike - this widget only needs GPS + network access + a way to appear
on the device, and ambient temperature is useful information on all
of them, not just watches.

**`minSdkVersion` is 3.1.8, not the SDK's current default** - that's
the exact API level this app's tightest real dependency needs
(`Graphics.FONT_GLANCE`, used by the glance view). Don't lower it
without retesting broadly: this app mixes an optional `(:glance)`
`getGlanceView()` override into `TempustApp` (the entry point class),
and on SDK 9.2.0, setting `minSdkVersion` below `GlanceView`'s own
minimum (3.1.0) doesn't just disable the glance - on some devices it
breaks the *entire* entry point with an unrelated-looking "Cannot find
entry point class" or "Undefined symbol" error. That's a real, testing
-confirmed failure mode (see the comment above `minSdkVersion` in
`manifest.xml`), not a hypothetical.

**Devices without GPS** (e.g. plain activity trackers like the
vivosmart/vivomove/vivofit lines) are excluded - they don't offer the
Widget app type at all, so they were never candidates in the first
place, not a manual exclusion.

**On a few devices** (mostly older ones - D2 Air/Delta, Edge 1030-era,
eTrex Touch, GPSMAP, some fenix 5 Plus/vivoactive 3/4 variants), the
build emits a `(:glance) annotation will be ignored` warning: those
specific devices' Widget-Glance support needs a higher API level than
3.1.8, so they fall back to Connect IQ's default glance behavior (just
showing the app name) instead of this app's custom temp+graph glance.
The full widget itself is unaffected - this is graceful degradation,
not a bug.

**Before publishing:** open the project in VS Code (Monkey C
extension) and use **"Edit Compatible Devices"** (or the device picker
in the export wizard) to check this list against the current catalog -
Garmin releases new devices faster than any static list can track, and
occasionally tweaks product-id strings for existing ones.

## Building and installing the app

For a detailed, step-by-step walkthrough (including a pure CLI path
with exact `monkeyc`/`monkeydo` commands, not just the VS Code UI),
see **[LOCAL_SETUP.md](./LOCAL_SETUP.md)**. The quick version:

### 1. Install the Connect IQ SDK

- Download the **Connect IQ SDK Manager** from
  developer.garmin.com/connect-iq/sdk/ and install the latest SDK.
- Install the **"Monkey C"** VS Code extension (by Garmin).

### 2. Create a new project

`Ctrl+Shift+P` → **"Monkey C: New Project"**

- Choose **Widget** as the app type.
- Pick a target device, e.g. **Forerunner 965 (fr965)**.
- Name the project, e.g. `TempustWidget`.

This generates a `manifest.xml` with a **real UUID** – replace the
placeholder (`00000000-...`) in this folder's `manifest.xml` with it,
or just copy the `<iq:products>`, `<iq:permissions>` and
`<iq:languages>` blocks into the SDK-generated manifest.

### 3. Copy in the files

- `source/TempustApp.mc`
- `source/TempustView.mc`
- `source/TempustDelegate.mc`
- `source/TempustWeatherClient.mc`
- `resources/strings/strings.xml`
- `resources/properties/properties.xml`
- `resources/settings/settings.xml`
- `resources/drawables/drawables.xml` + `launcher_icon.png`

### 4. Test in the simulator

`Ctrl+Shift+P` → **"Monkey C: Run current project in Connect IQ
simulator"**. Set a fake GPS position under **Simulation → Location**
(e.g. Kalmar, Sweden: `56.6634, 16.3566`). Also test toggling
Celsius/Fahrenheit from the simulator's app settings panel.

### 5. Build and sideload to the watch

`Ctrl+Shift+P` → **"Monkey C: Build for Device"** → copy the resulting
`.prg` file to `GARMIN/APPS/` while the watch is connected via USB.
Disconnect and restart the watch.

## Publishing to the Connect IQ Store (optional)

High-level steps: create a developer account, export via "Monkey C:
Export Project" to get an `.iq` file, upload it at
apps.garmin.com/en-US/developer/upload, add a description + screenshots,
then go through Garmin's App Review Guidelines.

Things in this version specifically aimed at making review easier:

- **Permissions match actual usage** – only `Communications` and
  `Positioning` are requested, exactly what the app uses. No excess
  permissions.
- **No background execution** – the widget is a standard foreground
  widget (`type="widget"`), only polls while actually on screen
  (`onHide()` stops the timer), and doesn't request the `Background`
  permission. Minimal battery impact, and nothing for reviewers to
  question around background activity.
- **Attribution to the data source** is shown in the UI ("Data:
  temperatur.nu"), which both satisfies temperatur.nu's own terms of
  use and gives reviewers clear visibility into where the data comes
  from.
- **Describe the data usage clearly** in your store listing when you
  publish: mention that the app uses GPS position solely to find the
  nearest weather station, and that the position is sent to
  temperatur.nu's API for that purpose – transparency around location
  data tends to be what reviewers scrutinize most closely.
- **Robust error handling** – the app shows clear status messages
  (locating, fetching, no response, error) instead of crashing or
  showing something blank/broken on network failure, GPS timeout, or
  no station found.

## Easter egg: sauna mode

Tap **SELECT** 5 times quickly (each tap within ~600ms of the previous
one) to unlock **"SAUNA MODE UNLOCKED"**: a screen showing how many
degrees the current reading is below a classic 80°C Swedish sauna
(`bastu`), with one flame icon per ~15°C of ground already covered
(max 5 flames). It reverts to the normal display automatically after
4 seconds, or you can just tap SELECT once more.

A few implementation notes, in case you're extending it:

- Purely cosmetic/local - it reuses whatever temperature reading is
  already in memory and makes **no network request of its own**, so it
  can't affect the temperatur.nu rate limit.
- Input handling lives entirely in `TempustDelegate.mc`: every SELECT
  tap restarts a 450ms debounce timer, and only once that timer
  actually expires does the delegate decide, once, whether the burst
  was an easter-egg trigger (5+ rapid taps) or a normal single tap
  (call `refresh()`). This is deliberate - without the debounce, a
  5-tap burst would also fire up to 5 refresh calls before the
  easter egg check ever ran, risking the "max one identical request
  per 5 minutes" limit described below.
- If no reading has been fetched yet, sauna mode shows a short prompt
  instead of a bogus number.

## Things to keep in mind

**API limits:** without a signed key, temperatur.nu allows roughly 30
requests/hour per client id, and at most one identical request per 5
minutes. The default interval (5 min) in `TempustView.mc` respects
that. The `CLIENT_ID` constant in `TempustWeatherClient.mc` should be
unique to you if you're doing a lot of testing – feel free to swap it
out.

**Commercial use:** purely personal sideloading isn't subject to
temperatur.nu's commercial terms. If you publish widely on the Connect
IQ Store and it gets significant traction, re-check the terms at
temperatur.nu/info/api/ – at higher volume a signed/paid tier may be
required.

**Battery:** a one-shot GPS fix every 5 minutes uses some battery if
the widget is left open for a long time. Adjust
`REFRESH_INTERVAL_SECONDS` in `TempustView.mc` for a longer interval.
