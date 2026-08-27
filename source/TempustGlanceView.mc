import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;

// Compact "at a glance" summary shown in the widget glance list.
// Reuses TempustWeatherClient so the glance always agrees with the
// full widget view, and does nothing beyond one fetch per showing -
// glance mode can run with as little as 32KB of memory and no working
// Timer.start()/WatchUi.requestUpdate() loop on constrained devices,
// so best practice is to keep it quick to load rather than polling
// (see Core Topics > Glances in the Connect IQ SDK docs).
(:glance)
class TempustGlanceView extends WatchUi.GlanceView {

    private var _client as TempustWeatherClient;
    private var _isFetching as Lang.Boolean = false;

    private var _temperatureCelsius as Lang.Float?;
    private var _stationName as Lang.String = "";
    private var _historyCelsius as Lang.Array<Lang.Float>?;
    private var _statusText as Lang.String = "";

    function initialize() {
        GlanceView.initialize();
        _client = new TempustWeatherClient();
    }

    function onShow() as Void {
        refresh();
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
                ? result.stationName as Lang.String
                : WatchUi.loadResource(Rez.Strings.UnknownStation) as Lang.String;
            _historyCelsius = result.historyCelsius;
            _statusText = "";
        } else if (result.status == RESULT_NO_POSITION) {
            _statusText = WatchUi.loadResource(Rez.Strings.StatusNoPosition) as Lang.String;
        } else if (result.status == RESULT_NO_STATION) {
            _statusText = WatchUi.loadResource(Rez.Strings.StatusNoStation) as Lang.String;
        } else {
            _statusText = WatchUi.loadResource(Rez.Strings.GlanceError) as Lang.String;
        }

        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        View.onUpdate(dc);

        var width = dc.getWidth();
        var height = dc.getHeight();

        // Full-bleed 24h trend line behind the text, dim enough to
        // stay a background flourish rather than compete with it.
        // Drawn first so the text below overwrites it where they
        // overlap - no fill, just the line, since a solid area chart
        // here would fight the glance row's own background instead of
        // sitting quietly behind the reading.
        if (_statusText.length() == 0) {
            // LT_GRAY, not DK_GRAY: dark gray on the row's black
            // background was too low-contrast to reliably show up
            // (practically invisible against COLOR_TRANSPARENT/black).
            drawTemperatureGraph(
                dc, 0, 0, width, height,
                _historyCelsius,
                Graphics.COLOR_LT_GRAY,
                null
            );
        }

        var text = (_statusText.length() > 0)
            ? _statusText
            : formatTemperatureCelsius(_temperatureCelsius) + "  " + _stationName;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            0, height / 2,
            Graphics.FONT_GLANCE,
            text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }
}
