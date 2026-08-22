import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.Application.Properties;

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

class TempustView extends WatchUi.View {

    private var _client as TempustWeatherClient;
    private var _refreshTimer as Timer.Timer?;
    private var _isFetching as Lang.Boolean = false;

    private var _temperatureCelsius as Lang.Float?;
    private var _stationName as Lang.String = "";
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
            _stationName = (result.stationName != null)
                ? result.stationName
                : WatchUi.loadResource(Rez.Strings.UnknownStation) as Lang.String;
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

        dc.drawText(
            width / 2, height * 0.13,
            Graphics.FONT_SMALL,
            WatchUi.loadResource(Rez.Strings.LabelNearestTemp) as Lang.String,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        if (_statusText.length() > 0) {
            dc.drawText(
                width / 2, height / 2,
                Graphics.FONT_MEDIUM,
                _statusText,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        } else {
            dc.drawText(
                width / 2, height * 0.44,
                Graphics.FONT_NUMBER_MEDIUM,
                formatTemperature(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            dc.drawText(
                width / 2, height * 0.68,
                Graphics.FONT_XTINY,
                _stationName,
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }

        dc.drawText(
            width / 2, height * 0.85,
            Graphics.FONT_XTINY,
            WatchUi.loadResource(Rez.Strings.HintRefresh) as Lang.String,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        // Required-by-terms attribution for the data source (see
        // README) - kept small so it doesn't compete with the actual
        // reading, but always visible while a reading is shown.
        dc.drawText(
            width / 2, height * 0.95,
            Graphics.FONT_XTINY,
            "Data: temperatur.nu",
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    // Renders "sauna mode": how many degrees the current reading is
    // below a classic 80C sauna, plus one flame per ~15C already
    // covered - just a bit of fun, no new data source involved.
    private function drawEasterEgg(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_BLACK);
        dc.drawText(
            width / 2, height * 0.15,
            Graphics.FONT_SMALL,
            WatchUi.loadResource(Rez.Strings.EasterEggTitle) as Lang.String,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        if (_temperatureCelsius == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(
                width / 2, height / 2,
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
        dc.drawText(
            width / 2, height * 0.4,
            Graphics.FONT_NUMBER_MEDIUM,
            delta.format("%.0f") + "°",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.drawText(
            width / 2, height * 0.56,
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

        var spacing = width / 6;
        var startX = (width / 2) - (spacing * (flames - 1) / 2);
        var flameY = (height * 0.72).toNumber();
        var i = 0;
        while (i < flames) {
            drawFlame(dc, startX + i * spacing, flameY, 10, Graphics.COLOR_ORANGE);
            i += 1;
        }

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(
            width / 2, height * 0.88,
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

    // Converts the stored Celsius reading to whichever unit the user
    // picked in the widget's settings (default: Celsius) and formats
    // it for display with one decimal place.
    private function formatTemperature() as Lang.String {
        if (_temperatureCelsius == null) {
            return "--";
        }

        var unit = Properties.getValue("TempUnit") as Lang.Number;
        var value = _temperatureCelsius as Lang.Float;
        var suffix = "°C";

        if (unit == UNIT_FAHRENHEIT) {
            value = value * 9.0 / 5.0 + 32.0;
            suffix = "°F";
        }

        return value.format("%.1f") + suffix;
    }
}
