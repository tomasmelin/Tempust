import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.System;
import Toybox.Math;

// How often (in seconds) the widget automatically refreshes while it's
// on screen. temperatur.nu rate-limits identical requests from the
// same client to once per 5 minutes, so we match that here rather
// than polling more aggressively (which would also drain battery for
// no real benefit, since most stations only update every few minutes
// anyway).
const REFRESH_INTERVAL_SECONDS = 300;

// How long the easter egg screen stays up before reverting to the
// normal temperature display, in milliseconds.
const EASTER_EGG_DISPLAY_MS = 4000;

// Classic Swedish sauna (bastu) reference temperature, in Celsius,
// used only for the easter egg's "degrees from a sauna" readout.
const SAUNA_REFERENCE_CELSIUS = 80.0;

// Extra clearance (in pixels) kept between text and a round bezel,
// beyond the minimum the chord math says is needed - a small buffer
// against rounding/font-metric slop.
const BEZEL_MARGIN_PX = 4;

// Where the 24h graph sits vertically, as fractions of screen height.
// Deliberately a FIXED band, not derived from where the footer rows
// (hint/attribution) end up: an earlier version computed the graph's
// bottom edge from the footer's bezel-nudged position, which on some
// screen sizes could push the footer high enough to collapse the
// graph to near-zero height - the graph would just silently fail to
// show, with no error, on exactly the devices where the footer text
// needed the most nudging. Keeping the graph's vertical space
// unconditional avoids that whole failure mode; its horizontal extent
// is still computed at draw time from the actual bezel shape (see
// safeHalfWidthAt()), which is safe since that can only ever shrink
// the box, never collapse it to nothing based on unrelated content.
const GRAPH_TOP_FRACTION = 0.38;
const GRAPH_BOTTOM_FRACTION = 0.72;

// Vertical gap (in pixels) kept between stacked bottom rows (the 24h
// graph, the refresh hint, and the attribution line) so a bezel-safety
// nudge on one can never make it touch the next.
const ROW_GAP_PX = 4;

// Fixed size (see drawFlame()) of the easter egg's flame icons - used
// to keep the flame row's own width inside the bezel-safe span too,
// not just the row of flame centers.
const FLAME_SIZE = 10;

class TempustView extends WatchUi.View {

    private var _client as TempustWeatherClient;
    private var _refreshTimer as Timer.Timer?;
    private var _isFetching as Lang.Boolean = false;

    private var _temperatureCelsius as Lang.Float?;
    private var _distanceKm as Lang.Float?;
    private var _stationName as Lang.String = "";
    private var _historyCelsius as Lang.Array<Lang.Float>?;
    private var _statusText as Lang.String = "";

    private var _easterEggActive as Lang.Boolean = false;
    private var _easterEggTimer as Timer.Timer?;

    function initialize() {
        View.initialize();
        _client = new TempustWeatherClient();
        _statusText = WatchUi.loadResource(Rez.Strings.StatusPromptRefresh) as Lang.String;
    }

    function onShow() as Void {
        refresh();

        _refreshTimer = new Timer.Timer();
        _refreshTimer.start(method(:onRefreshTimer), REFRESH_INTERVAL_SECONDS * 1000, true);
    }

    function onHide() as Void {
        // Stop polling as soon as the widget is no longer visible, so
        // it doesn't keep waking the device / using the network in
        // the background.
        if (_refreshTimer != null) {
            _refreshTimer.stop();
            _refreshTimer = null;
        }
        if (_easterEggTimer != null) {
            _easterEggTimer.stop();
            _easterEggTimer = null;
        }
        _easterEggActive = false;
    }

    function onRefreshTimer() as Void {
        if (!_isFetching) {
            refresh();
        }
    }

    // Called by TempustApp.onSettingsChanged() when the user changes
    // the temperature unit while the widget is open - just needs a
    // redraw, the stored Celsius value doesn't change.
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }

    function refresh() as Void {
        if (_isFetching) {
            return;
        }
        _isFetching = true;
        _statusText = WatchUi.loadResource(Rez.Strings.StatusLocating) as Lang.String;
        WatchUi.requestUpdate();
        _client.fetchNearestTemperature(method(:onWeatherResult));
    }

    function onWeatherResult(result as WeatherResult) as Void {
        _isFetching = false;

        if (result.status == RESULT_OK) {
            _temperatureCelsius = result.temperatureCelsius;
            _distanceKm = result.distanceKm;
            _stationName = (result.stationName != null)
                ? result.stationName
                : WatchUi.loadResource(Rez.Strings.UnknownStation) as Lang.String;
            _historyCelsius = result.historyCelsius;
            _statusText = "";
        } else if (result.status == RESULT_NO_POSITION) {
            _statusText = WatchUi.loadResource(Rez.Strings.StatusNoPosition) as Lang.String;
        } else if (result.status == RESULT_NO_STATION) {
            _statusText = WatchUi.loadResource(Rez.Strings.StatusNoStation) as Lang.String;
        } else {
            var prefix = WatchUi.loadResource(Rez.Strings.StatusErrorPrefix) as Lang.String;
            var suffix = WatchUi.loadResource(Rez.Strings.StatusErrorSuffix) as Lang.String;
            var code = (result.httpCode != null) ? result.httpCode.toString() : "?";
            _statusText = prefix + code + suffix;
        }

        WatchUi.requestUpdate();
    }

    // Easter egg entry point, called by TempustDelegate after 5 rapid
    // SELECT taps. Doesn't touch the network at all - it's purely a
    // reinterpretation of the temperature reading already in memory,
    // so it can't affect the temperatur.nu rate limit either way.
    function triggerEasterEgg() as Void {
        _easterEggActive = true;

        if (_easterEggTimer != null) {
            _easterEggTimer.stop();
        } else {
            _easterEggTimer = new Timer.Timer();
        }
        _easterEggTimer.start(method(:onEasterEggExpired), EASTER_EGG_DISPLAY_MS, false);

        WatchUi.requestUpdate();
    }

    function onEasterEggExpired() as Void {
        _easterEggActive = false;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        View.onUpdate(dc);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (_easterEggActive) {
            drawEasterEgg(dc);
            return;
        }

        var width = dc.getWidth();
        var height = dc.getHeight();

        // Attribution is required by temperatur.nu's terms of use (see
        // README) but kept to just the name - short enough that it and
        // the hint below it need little to no bezel-safety nudging on
        // any device, unlike the old "Data: temperatur.nu" wording.
        var attributionText = "temperatur.nu";
        var attribDims = dc.getTextDimensions(attributionText, Graphics.FONT_XTINY);
        var attribTopY = bottomAnchoredTopY(dc, attributionText, Graphics.FONT_XTINY, height - attribDims[1]);

        var hintText = WatchUi.loadResource(Rez.Strings.HintRefresh) as Lang.String;
        var hintDims = dc.getTextDimensions(hintText, Graphics.FONT_XTINY);
        var hintTopY = bottomAnchoredTopY(dc, hintText, Graphics.FONT_XTINY, attribTopY - ROW_GAP_PX - hintDims[1]);

        if (_statusText.length() > 0) {
            drawSafeText(
                dc, height / 2,
                Graphics.FONT_MEDIUM,
                _statusText,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        } else {
            drawSafeText(
                dc, height * 0.20,
                Graphics.FONT_NUMBER_MEDIUM,
                formatTemperature(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );

            var distanceText = formatDistanceKm(_distanceKm);
            var stationLine = (distanceText.length() > 0)
                ? _stationName + " · " + distanceText
                : _stationName;
            drawSafeText(
                dc, height * 0.33,
                Graphics.FONT_XTINY,
                stationLine,
                Graphics.TEXT_JUSTIFY_CENTER
            );

            // Fixed vertical band (see GRAPH_TOP/BOTTOM_FRACTION) -
            // only the horizontal extent adapts to the bezel.
            var graphTop = height * GRAPH_TOP_FRACTION;
            var graphBottom = height * GRAPH_BOTTOM_FRACTION;
            // Chord width shrinks the further a row sits from the
            // vertical center, so the tighter of the graph's top and
            // bottom edges is what has to fit - same reasoning as
            // drawSafeText(), just for a box instead of a text
            // baseline.
            var graphHalfWidth = safeHalfWidthAt(dc, graphTop);
            var bottomHalfWidth = safeHalfWidthAt(dc, graphBottom);
            if (bottomHalfWidth < graphHalfWidth) {
                graphHalfWidth = bottomHalfWidth;
            }

            drawTemperatureGraph(
                dc,
                (width / 2.0) - graphHalfWidth, graphTop,
                graphHalfWidth * 2, graphBottom - graphTop,
                _historyCelsius,
                Graphics.COLOR_ORANGE,
                Graphics.COLOR_DK_GRAY
            );
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, hintTopY, Graphics.FONT_XTINY, hintText, Graphics.TEXT_JUSTIFY_CENTER);

        // Required-by-terms attribution for the data source (see
        // README) - kept small so it doesn't compete with the actual
        // reading, but always visible while a reading is shown.
        dc.drawText(width / 2, attribTopY, Graphics.FONT_XTINY, attributionText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Renders "sauna mode": how many degrees the current reading is
    // below a classic 80C sauna, plus one flame per ~15C already
    // covered - just a bit of fun, no new data source involved.
    private function drawEasterEgg(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_BLACK);
        drawSafeText(
            dc, height * 0.15,
            Graphics.FONT_SMALL,
            WatchUi.loadResource(Rez.Strings.EasterEggTitle) as Lang.String,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        if (_temperatureCelsius == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            drawSafeText(
                dc, height / 2,
                Graphics.FONT_SMALL,
                WatchUi.loadResource(Rez.Strings.EasterEggNoData) as Lang.String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }

        var current = _temperatureCelsius as Lang.Float;
        var delta = SAUNA_REFERENCE_CELSIUS - current;
        if (delta < 0) {
            delta = 0.0;
        }

        var prefix = WatchUi.loadResource(Rez.Strings.EasterEggPrefix) as Lang.String;
        var suffix = WatchUi.loadResource(Rez.Strings.EasterEggSuffix) as Lang.String;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        drawSafeText(
            dc, height * 0.4,
            Graphics.FONT_NUMBER_MEDIUM,
            delta.format("%.0f") + "°",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        drawSafeText(
            dc, height * 0.56,
            Graphics.FONT_XTINY,
            prefix + delta.format("%.0f") + "°C" + suffix,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // One flame per ~15C of ground already covered toward 80C,
        // capped at 5 so it can never overflow the screen width.
        var flameCount = (SAUNA_REFERENCE_CELSIUS - delta) / 15.0;
        var flames = flameCount.toNumber();
        if (flames > 5) {
            flames = 5;
        }
        if (flames < 0) {
            flames = 0;
        }

        var flameY = (height * 0.72).toNumber();

        // Widest layout (5 flames at the default width/6 spacing) can
        // run past a round bezel on smaller screens, so cap the span to
        // whatever's actually safe at this row - leaving room for each
        // flame's own width (FLAME_SIZE * 0.6 either side of its
        // center), not just the row of flame centers.
        var safeHalfSpan = safeHalfWidthAt(dc, flameY) - (FLAME_SIZE * 0.6);
        if (safeHalfSpan < 0) {
            safeHalfSpan = 0.0;
        }
        var spacing = width / 6;
        if (flames > 1) {
            var maxSpacing = ((safeHalfSpan * 2) / (flames - 1)).toNumber();
            if (spacing > maxSpacing) {
                spacing = maxSpacing;
            }
        }
        var startX = (width / 2) - (spacing * (flames - 1) / 2);
        var i = 0;
        while (i < flames) {
            drawFlame(dc, startX + i * spacing, flameY, FLAME_SIZE, Graphics.COLOR_ORANGE);
            i += 1;
        }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        drawSafeText(
            dc, height * 0.88,
            Graphics.FONT_XTINY,
            WatchUi.loadResource(Rez.Strings.EasterEggFooter) as Lang.String,
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    // Small filled-polygon flame icon centered at (cx, cy) with
    // roughly `s` pixels of half-height. Deliberately simple (no
    // bitmap asset needed) - just enough to read as a flame at
    // watch-display size.
    private function drawFlame(dc as Graphics.Dc, cx as Lang.Number, cy as Lang.Number, s as Lang.Number, color as Lang.Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
dc.fillPolygon([
    [cx, cy - s],
    [cx + (s * 0.6).toNumber(), cy - (s * 0.1).toNumber()],
    [cx + (s * 0.35).toNumber(), cy + s],
    [cx - (s * 0.35).toNumber(), cy + s],
    [cx - (s * 0.6).toNumber(), cy - (s * 0.1).toNumber()]
]);
    }

    // How far (in pixels) content can extend left/right of the
    // horizontal center at vertical position y while staying clear of
    // a round/semi-round bezel, with BEZEL_MARGIN_PX of slack. Chord
    // width shrinks the further y sits from the vertical center, which
    // is what the 24h graph and the easter egg's flame row use this
    // for - drawSafeText() below does the equivalent math itself since
    // it also needs to know its own text's on-screen vertical center
    // first. Rectangular screens always get the untouched half-width.
    private function safeHalfWidthAt(dc as Graphics.Dc, y as Lang.Numeric) as Lang.Float {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var half = width / 2.0;

        var shape = System.getDeviceSettings().screenShape;
        if (shape == System.SCREEN_SHAPE_ROUND || shape == System.SCREEN_SHAPE_SEMI_ROUND) {
            var radius = half;
            var offset = y - (height / 2.0);
            if (offset < 0) {
                offset = -offset;
            }
            if (offset >= radius) {
                return 0.0;
            }
            var chordHalf = Math.sqrt((radius * radius) - (offset * offset)) as Lang.Float;
            if (chordHalf < half) {
                half = chordHalf;
            }
        }

        return half - BEZEL_MARGIN_PX;
    }

    // Inverse of safeHalfWidthAt(): the largest |y - center| at which
    // content halfWidth pixels wide (each side of center) still clears
    // a round/semi-round bezel, with BEZEL_MARGIN_PX of slack. On a
    // rectangular screen there's no bezel to avoid, so the full
    // available half-height is returned unconditionally.
    private function maxSafeOffsetFor(dc as Graphics.Dc, halfWidth as Lang.Float) as Lang.Float {
        var width = dc.getWidth();
        var height = dc.getHeight();

        var shape = System.getDeviceSettings().screenShape;
        if (shape != System.SCREEN_SHAPE_ROUND && shape != System.SCREEN_SHAPE_SEMI_ROUND) {
            return height / 2.0;
        }

        var radius = width / 2.0;
        var needed = halfWidth + BEZEL_MARGIN_PX;
        if (needed >= radius) {
            return 0.0;
        }
        return Math.sqrt((radius * radius) - (needed * needed)) as Lang.Float;
    }

    // Top-anchored y (matches TEXT_JUSTIFY_CENTER without VCENTER) that
    // puts `text` as close to the screen's bottom edge as its own
    // measured width allows on this device's bezel, but never lower
    // than `belowY`.
    //
    // This is what onUpdate() uses to stack the hint and attribution
    // rows bottom-up: each is placed from its own measured width
    // outward rather than a guessed height fraction, so however wide a
    // given string turns out to be - a longer translation, a bigger
    // font on some device - it can't silently overlap the row above
    // it or get clipped by the bezel. A fixed-fraction placement (the
    // previous approach here) can't make that guarantee: a wide string
    // parked close to a round edge needs far more clearance than its
    // height fraction alone suggests, and unlike a single isolated
    // drawSafeText() call it has neighbors that need to stay clear too.
    private function bottomAnchoredTopY(dc as Graphics.Dc, text as Lang.String, font as Graphics.FontType, belowY as Lang.Numeric) as Lang.Float {
        var height = dc.getHeight();
        var dims = dc.getTextDimensions(text, font);
        var halfWidth = dims[0] / 2.0;
        var textHeight = dims[1];

        var idealCenterY = (height / 2.0) + maxSafeOffsetFor(dc, halfWidth);
        var idealTopY = idealCenterY - (textHeight / 2.0);

        return (idealTopY < belowY) ? idealTopY : (belowY as Lang.Float);
    }

    // Horizontally-centered dc.drawText(), nudged toward the vertical
    // center just far enough to clear a round/semi-round bezel.
    //
    // Several rows here are deliberately parked close to the very top
    // or bottom of the screen (e.g. the attribution line at 95% of
    // height), but on a round display the usable width shrinks fast
    // away from the vertical center - a chord near the edge can be
    // well under half the screen's diameter. Every device in this
    // widget's compatible-devices list is round or semi-round, so
    // without this, edge rows silently clip off the sides of the
    // display. Rectangular screens are unaffected: the chord check
    // only ever moves text on round/semi-round shapes.
    private function drawSafeText(dc as Graphics.Dc, y as Lang.Numeric, font as Graphics.FontType, text as Lang.String, justify as Lang.Number) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var safeY = y;

        var shape = System.getDeviceSettings().screenShape;
        if (shape == System.SCREEN_SHAPE_ROUND || shape == System.SCREEN_SHAPE_SEMI_ROUND) {
            var dims = dc.getTextDimensions(text, font);
            var textWidth = dims[0];
            var textHeight = dims[1];

            var vCentered = (justify & Graphics.TEXT_JUSTIFY_VCENTER) != 0;
            var textCenterY = vCentered ? y : y + (textHeight / 2.0);

            var radius = width / 2.0;
            var halfNeeded = (textWidth / 2.0) + BEZEL_MARGIN_PX;
            if (halfNeeded < radius) {
                var maxOffset = Math.sqrt((radius * radius) - (halfNeeded * halfNeeded)) as Lang.Float;
                var offset = textCenterY - (height / 2.0);
                if (offset > maxOffset) {
                    safeY = y - (offset - maxOffset);
                } else if (offset < -maxOffset) {
                    safeY = y - (offset + maxOffset);
                }
            }
            // else: this text is wider than the screen's diameter (minus
            // margin) at any height on this device - repositioning can't
            // help, so it's left where it was asked to be drawn.
        }

        dc.drawText(width / 2, safeY, font, text, justify);
    }

    // Converts the stored Celsius reading to whichever unit the user
    // picked in the widget's settings (default: Celsius) and formats
    // it for display with one decimal place.
    private function formatTemperature() as Lang.String {
        return formatTemperatureCelsius(_temperatureCelsius);
    }
}
