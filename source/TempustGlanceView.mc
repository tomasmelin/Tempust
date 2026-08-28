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
//
// No custom icon drawing here: the dc passed to onUpdate() is
// documented as "bounded by glance area" - a sub-region, not the
// whole row - and in practice the system already draws this app's
// launcher icon in its own reserved slot to the left of it, so text
// starting near x=0 of our dc lands in the right place without us
// drawing anything for the icon ourselves. An earlier version tried
// to draw its own icon badge on top of/beside that and it looked
// wrong (a stray line instead of a recognisable thermometer).
//
// No background fill either - a couple of attempts at a colored card
// (a full gradient, then a flatter muted one) both read as a
// graphical glitch rather than styling, so this leaves the row's own
// background showing through, as it did originally.
(:glance)
class TempustGlanceView extends WatchUi.GlanceView {

    private var _client as TempustWeatherClient;
    private var _isFetching as Lang.Boolean = false;

    private var _temperatureCelsius as Lang.Float?;
    private var _distanceKm as Lang.Float?;
    private var _stationName as Lang.String = "";
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
            _distanceKm = result.distanceKm;
            _stationName = (result.stationName != null)
                ? result.stationName as Lang.String
                : WatchUi.loadResource(Rez.Strings.UnknownStation) as Lang.String;
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

        // No fill: leave the row's own background showing through
        // (transparent, reading as black on most devices/themes), as
        // it was before this app tried adding a colored card - that
        // read as a graphical bug rather than styling.
        //
        // A little padding past the left edge; the system's own
        // launcher-icon slot (outside our dc - see the class comment)
        // already accounts for itself, so text starts near the left
        // edge of what we're given, not offset for an icon we're not
        // drawing.
        var textLeft = width * 0.06;
        var textWidth = width - textLeft - (width * 0.03);
        if (textWidth < 0) {
            textWidth = 0;
        }

        if (_statusText.length() > 0) {
            drawFittedText(
                dc, textLeft, height / 2.0, textWidth,
                Graphics.FONT_GLANCE, _statusText, Graphics.COLOR_WHITE
            );
        } else {
            var distanceText = formatDistanceKm(_distanceKm);
            var line2 = (distanceText.length() > 0)
                ? _stationName + " · " + distanceText
                : _stationName;

            drawFittedText(
                dc, textLeft, height * 0.32, textWidth,
                Graphics.FONT_GLANCE, formatTemperatureCelsius(_temperatureCelsius), Graphics.COLOR_WHITE
            );
            drawFittedText(
                dc, textLeft, height * 0.72, textWidth,
                Graphics.FONT_XTINY, line2, Graphics.COLOR_LT_GRAY
            );
        }
    }

    // Left-justified, vertically-centered text, shrunk to fit maxWidth
    // via fitTextToWidth() first - the glance area is a rectangular
    // sub-region (not subject to the round-bezel clipping the main
    // widget view has to work around), so a too-wide string here just
    // gets hard-clipped by the dc's own bounds instead of eased in;
    // truncating it ourselves is what avoids that.
    private function drawFittedText(
        dc as Graphics.Dc, x as Lang.Numeric, y as Lang.Numeric, maxWidth as Lang.Numeric,
        font as Graphics.FontType, text as Lang.String, color as Lang.Number
    ) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            x, y, font, fitTextToWidth(dc, text, font, maxWidth),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    // Binary search for the longest text + "..." that fits in
    // maxWidth pixels at the given font.
    private function fitTextToWidth(dc as Graphics.Dc, text as Lang.String, font as Graphics.FontType, maxWidth as Lang.Numeric) as Lang.String {
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
            return text;
        }

        var ellipsis = "...";
        var lo = 0;
        var hi = text.length();
        while (lo < hi) {
            var mid = (lo + hi + 1) / 2;
            var candidate = (text.substring(0, mid) as Lang.String) + ellipsis;
            if (dc.getTextWidthInPixels(candidate, font) <= maxWidth) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }

        return (lo > 0) ? ((text.substring(0, lo) as Lang.String) + ellipsis) : ellipsis;
    }
}
