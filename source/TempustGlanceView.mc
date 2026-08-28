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
// Styled to match Connect IQ's own glances (Notifications, Calendar,
// etc.): a round icon badge on the left, on a background that fades
// from an accent color to black across the row. Blue here, since the
// stock glances already claim green (Notifications) and orange
// (weather). Drawing this background ourselves - rather than leaving
// any of the row unpainted - is also what fixes an earlier graphical
// glitch where an unstyled area of the row showed a stray placeholder
// box instead of our content.
(:glance)
class TempustGlanceView extends WatchUi.GlanceView {

    // Background fades from this color (left) to black (right).
    private const ACCENT_COLOR = 0x2E8FFF;

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

        drawFadeBackground(dc, width, height);
        drawIconBadge(dc, height);

        // Text starts just past the icon badge, with a small gutter on
        // both sides so a device with very little glance-row width
        // never has fitTextToWidth() work with a negative budget.
        var textLeft = height * 1.15;
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

    // Horizontal strips blending from ACCENT_COLOR at the left edge to
    // black at the right, approximating a fade without relying on
    // alpha blending (fillRectangle only supports a solid fill color,
    // and COLOR_TRANSPARENT means "don't fill", not "partially fill").
    private function drawFadeBackground(dc as Graphics.Dc, width as Lang.Numeric, height as Lang.Numeric) as Void {
        var steps = 20;
        var stripWidth = (width.toFloat() / steps) + 1;

        var r0 = (ACCENT_COLOR >> 16) & 0xFF;
        var g0 = (ACCENT_COLOR >> 8) & 0xFF;
        var b0 = ACCENT_COLOR & 0xFF;

        var i = 0;
        while (i < steps) {
            var t = 1.0 - (i.toFloat() / (steps - 1));
            var color = (((r0 * t).toNumber()) << 16)
                | (((g0 * t).toNumber()) << 8)
                | ((b0 * t).toNumber());

            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(i * (width.toFloat() / steps), 0, stripWidth, height);
            i += 1;
        }
    }

    // Simple drawn thermometer glyph (a filled circle badge, no bitmap
    // asset needed) sized to the row height, matching the launcher
    // icon's look closely enough to be recognizable at a glance.
    private function drawIconBadge(dc as Graphics.Dc, rowHeight as Lang.Numeric) as Void {
        var cx = rowHeight * 0.5;
        var cy = rowHeight * 0.5;
        var r = rowHeight * 0.32;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);

        dc.setColor(ACCENT_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(cx, cy - (r * 0.5), cx, cy + (r * 0.3));
        dc.fillCircle(cx, cy + (r * 0.45), r * 0.22);
        dc.setPenWidth(1);
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
