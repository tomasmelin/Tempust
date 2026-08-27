import Toybox.Graphics;
import Toybox.Lang;

// Renders a compact line graph of `values` (oldest to newest, already
// downsampled by the caller) inside the box (x, y, w, h) on dc.
// Shared between TempustView (bright line + filled area, drawn as the
// main content) and TempustGlanceView (a dim line with no fill, drawn
// behind the temperature text as a background flourish), so both stay
// visually consistent and neither duplicates the scaling math.
//
// No-ops if there's nothing meaningful to draw - fewer than two points
// can't form a line, which covers both "fetch hasn't completed yet"
// and "the history request failed/was unavailable" (both leave
// `values` null rather than partially populated).
(:glance)
function drawTemperatureGraph(
    dc as Graphics.Dc,
    x as Lang.Numeric, y as Lang.Numeric, w as Lang.Numeric, h as Lang.Numeric,
    values as Lang.Array<Lang.Float>?,
    lineColor as Lang.Number,
    fillColor as Lang.Number?
) as Void {
    if (values == null || values.size() < 2) {
        return;
    }

    var count = values.size();
    var minValue = values[0] as Lang.Float;
    var maxValue = values[0] as Lang.Float;
    var i = 1;
    while (i < count) {
        var v = values[i] as Lang.Float;
        if (v < minValue) {
            minValue = v;
        }
        if (v > maxValue) {
            maxValue = v;
        }
        i += 1;
    }

    // A perfectly flat 24h (min == max) would divide by zero below;
    // draw it as a flat mid-height line instead.
    var range = maxValue - minValue;
    var flat = range < 0.001;

    var points = new [count] as Lang.Array<Graphics.Point2D>;
    i = 0;
    while (i < count) {
        var px = x + (w * i / (count - 1));
        var py = flat
            ? (y + (h / 2.0))
            : (y + h - (((values[i] as Lang.Float) - minValue) / range * h));
        points[i] = [ px, py ] as Graphics.Point2D;
        i += 1;
    }

    if (fillColor != null) {
        var polygon = new [count + 2] as Lang.Array<Graphics.Point2D>;
        polygon[0] = [ x, y + h ] as Graphics.Point2D;
        i = 0;
        while (i < count) {
            polygon[i + 1] = points[i];
            i += 1;
        }
        polygon[count + 1] = [ x + w, y + h ] as Graphics.Point2D;

        dc.setColor(fillColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(polygon);
    }

    dc.setColor(lineColor, Graphics.COLOR_TRANSPARENT);
    dc.setPenWidth(2);
    i = 1;
    while (i < count) {
        var a = points[i - 1];
        var b = points[i];
        dc.drawLine(a[0], a[1], b[0], b[1]);
        i += 1;
    }
    dc.setPenWidth(1);
}
