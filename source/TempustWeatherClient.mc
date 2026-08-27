import Toybox.Communications;
import Toybox.Position;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.Application.Properties;
import Toybox.System;

// Values must match resources/properties/properties.xml and
// resources/settings/settings.xml (the "TempUnit" list setting).
(:glance)
const UNIT_CELSIUS = 0;
(:glance)
const UNIT_FAHRENHEIT = 1;

// Outcome codes returned to the caller via WeatherResult.status.
(:glance)
const RESULT_OK = 0;
(:glance)
const RESULT_NO_POSITION = 1;
(:glance)
const RESULT_NO_STATION = 2;
(:glance)
const RESULT_NETWORK_ERROR = 3;

// Converts a Celsius reading to whichever unit the user picked in the
// widget's settings (default: Celsius) and formats it with one decimal
// place. Shared by TempustView and TempustGlanceView so both always
// agree with the user's unit setting instead of each doing their own
// conversion.
(:glance)
function formatTemperatureCelsius(celsius as Lang.Float?) as Lang.String {
    if (celsius == null) {
        return "--";
    }

    var unit = Properties.getValue("TempUnit") as Lang.Number;
    var value = celsius;
    var suffix = "°C";

    if (unit == UNIT_FAHRENHEIT) {
        value = value * 9.0 / 5.0 + 32.0;
        suffix = "°F";
    }

    return value.format("%.1f") + suffix;
}

// Plain data holder passed back to whoever called fetchNearestTemperature().
// Keeping this as its own small class (rather than a loose Dictionary)
// makes the calling code self-documenting and easy to type-check.
(:glance)
class WeatherResult {
    public var status as Lang.Number;
    public var temperatureCelsius as Lang.Float?;
    public var stationName as Lang.String?;
    // Oldest-to-newest Celsius readings for the last ~24h at the same
    // station, already downsampled to a display-friendly point count.
    // Null whenever the history couldn't be fetched or parsed - that's
    // treated as "no graph today", not a hard failure, since the
    // current-temperature reading above is independently valid either
    // way (see TempustWeatherClient.onReceiveHistory()).
    public var historyCelsius as Lang.Array<Lang.Float>?;
    public var httpCode as Lang.Number?;

    function initialize(
        status as Lang.Number,
        temperatureCelsius as Lang.Float?,
        stationName as Lang.String?,
        historyCelsius as Lang.Array<Lang.Float>?,
        httpCode as Lang.Number?
    ) {
        self.status = status;
        self.temperatureCelsius = temperatureCelsius;
        self.stationName = stationName;
        self.historyCelsius = historyCelsius;
        self.httpCode = httpCode;
    }
}

// Encapsulates everything needed to go from "no data" to "temperature
// at the nearest temperatur.nu station": acquiring a GPS fix, calling
// the API, and parsing the response. Kept separate from TempustView so
// the view only has to deal with UI state, not networking details.
// Also used as-is by TempustGlanceView, hence :glance throughout - it
// has no dead weight to trim, the whole class is the fetch flow.
(:glance)
class TempustWeatherClient {

    private const API_URL = "https://api.temperatur.nu/tnu_1.20.php";

    // Identifies this app to temperatur.nu. Unsigned clients are rate
    // limited to roughly 30 requests/hour and one identical request
    // per 5 minutes - fine for a single personal widget, but change
    // this to something unique to you if you ever see repeated
    // "blocked" responses.
    private const CLIENT_ID = "tempust_connectiq_widget_v1";

    // Caps how many points the 24h history graph ever has to render.
    // Stations can report every few minutes, which for span=1day could
    // be well over a hundred raw points - far more detail than a small
    // watch screen (or the glance's tight memory budget) can use.
    private const HISTORY_MAX_POINTS = 30;

    private var _callback as Lang.Method?;
    private var _locationTimeoutTimer as Timer.Timer?;
    private var _positioningActive as Lang.Boolean = false;

    // Stashed between the "current reading" request and the follow-up
    // "24h history" request, so the final WeatherResult can carry both.
    private var _pendingTemperatureCelsius as Lang.Float?;
    private var _pendingStationName as Lang.String?;
    private var _pendingHttpCode as Lang.Number?;

    // Garmin's Position API has no built-in timeout: if a GPS fix never
    // comes in (indoors, weak signal, simulator location never set),
    // onPosition() simply never fires and the UI would sit on
    // "Locating..." forever. This caps the wait so it always resolves
    // to a clear "no position" status instead.
    //
    // 60s rather than something snappier because that's the realistic
    // order of magnitude for a cold GNSS fix on a wrist device; a
    // shorter cap just guarantees "No GPS position yet" every time the
    // watch has to actually acquire satellites.
    private const LOCATION_TIMEOUT_MS = 60000;

    // Kicks off the whole fetch flow. `callback` is invoked exactly
    // once with a WeatherResult, whether the fetch succeeded or failed.
    function fetchNearestTemperature(callback as Lang.Method) as Void {
        _callback = callback;

        // Fast path: the watch almost always already knows roughly
        // where it is (last activity, last sync, a fix another app just
        // took). "Nearest temperatur.nu station" is a coarse question -
        // stations are tens of kilometres apart - so a cached fix is a
        // perfectly good answer, and it means the common case resolves
        // instantly without powering up the GNSS receiver at all.
        var cached = Position.getInfo();
        if (hasUsableFix(cached)) {
            useFix(cached);
            return;
        }

        // No cached fix, so we have to actually acquire one.
        //
        // LOCATION_CONTINUOUS, not LOCATION_ONE_SHOT: with one-shot the
        // listener is only ever called if/when a fix materialises, and
        // on several devices - and in the simulator until a location is
        // set - it simply never fires, which is indistinguishable from
        // "no GPS" to the caller. Continuous mode starts reporting
        // right away (initially with QUALITY_NOT_AVAILABLE) and we
        // disable it again the moment a usable fix arrives, so the
        // receiver stays on no longer than one-shot would have kept it.
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        _positioningActive = true;

        _locationTimeoutTimer = new Timer.Timer();
        _locationTimeoutTimer.start(method(:onLocationTimeout), LOCATION_TIMEOUT_MS, false);
    }

    function onPosition(info as Position.Info) as Void {
        // Continuous mode reports every update, including the early
        // ones with no fix yet. Ignore those and keep waiting - the
        // timeout below is what eventually gives up.
        if (!hasUsableFix(info)) {
            return;
        }

        stopPositioning();
        useFix(info);
    }

    // Fires if no usable GPS fix arrived within LOCATION_TIMEOUT_MS.
    function onLocationTimeout() as Void {
        _locationTimeoutTimer = null;

        // One last look before giving up: a fix may have landed in the
        // system between updates.
        var last = Position.getInfo();
        stopPositioning();

        if (hasUsableFix(last)) {
            useFix(last);
            return;
        }

        invokeCallback(new WeatherResult(RESULT_NO_POSITION, null, null, null, null));
    }

    // A Position.Info is only worth using if the system actually has a
    // fix behind it. Note that info.position is non-null even with no
    // fix at all (it reads as 180/180 on most devices), so accuracy -
    // not null-ness - is the thing to check.
    private function hasUsableFix(info as Position.Info?) as Lang.Boolean {
        return info != null
            && info.position != null
            && info.accuracy != Position.QUALITY_NOT_AVAILABLE;
    }

    private function useFix(info as Position.Info) as Void {
        var degrees = (info.position as Position.Location).toDegrees();
        requestNearestStation(degrees[0], degrees[1]);
    }

    private function stopPositioning() as Void {
        cancelLocationTimeout();
        if (_positioningActive) {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
            _positioningActive = false;
        }
    }

    private function cancelLocationTimeout() as Void {
        if (_locationTimeoutTimer != null) {
            _locationTimeoutTimer.stop();
            _locationTimeoutTimer = null;
        }
    }

    private function requestNearestStation(lat as Lang.Double, lon as Lang.Double) as Void {
        // Deliberately no explicit "as" cast on either dictionary below:
        // Communications.makeWebRequest() expects a params dictionary
        // typed Dictionary<Object,Object> and an options dictionary with
        // a specific structural (record) type - both narrower/stricter
        // than the generic Dictionary<String,...>/Dictionary<Symbol,...>
        // casts we previously used, which the type checker rejected.
        // Leaving the literals uncast lets the compiler infer the exact
        // types the API wants.
        var params = {
            "lat"         => lat,
            "lon"         => lon,
            "num"         => 1,
            "sensor_type" => "air",
            "cli"         => CLIENT_ID
        };

        var options = {
            :method       => Communications.HTTP_REQUEST_METHOD_GET,
            :headers      => { "Accept" => "application/json" },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(API_URL, params, options, method(:onReceive));
    }

    function onReceive(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        if (responseCode != 200 || data == null || !(data instanceof Lang.Dictionary)) {
            invokeCallback(new WeatherResult(RESULT_NETWORK_ERROR, null, null, null, responseCode));
            return;
        }

        var stations = data.get("stations");
        if (stations == null || !(stations instanceof Lang.Array) || stations.size() == 0) {
            invokeCallback(new WeatherResult(RESULT_NO_STATION, null, null, null, responseCode));
            return;
        }

        var station = stations[0] as Lang.Dictionary;
        var rawTemp = station.get("temp");
        var rawName = station.get("title");
        var rawId = station.get("id");

        // temperatur.nu always reports readings in Celsius; unit
        // conversion (if the user picked Fahrenheit) happens later,
        // in TempustView, purely for display.
        _pendingTemperatureCelsius = (rawTemp != null) ? rawTemp.toString().toFloat() : null;
        _pendingStationName = (rawName != null) ? rawName.toString() : null;
        _pendingHttpCode = responseCode;

        if (rawId != null) {
            requestHistory(rawId.toString());
        } else {
            // No station id came back - can't look up its history, but
            // the current reading is still good on its own.
            invokeCallback(new WeatherResult(
                RESULT_OK, _pendingTemperatureCelsius, _pendingStationName, null, _pendingHttpCode
            ));
        }
    }

    // Follow-up request for the last ~24h of readings at the station
    // we just identified, keyed by its "id" (the "p" param - see
    // https://www.temperatur.nu/info/api/). Always resolves the
    // overall fetch with RESULT_OK: a missing/malformed history is
    // just "no graph today", not a reason to discard the current
    // reading we already have.
    private function requestHistory(stationId as Lang.String) as Void {
        var params = {
            "p"           => stationId,
            "data"        => "1",
            "span"        => "1day",
            "sensor_type" => "air",
            "cli"         => CLIENT_ID
        };

        var options = {
            :method       => Communications.HTTP_REQUEST_METHOD_GET,
            :headers      => { "Accept" => "application/json" },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(API_URL, params, options, method(:onReceiveHistory));
    }

    function onReceiveHistory(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or Null) as Void {
        // Temporary console diagnostics - see LOCAL_SETUP.md, "Console
        // output". Remove once the history graph is confirmed working
        // end-to-end in the simulator/on-device.
        System.println("Tempust: history responseCode=" + responseCode + " dataType=" + classNameOf(data));

        var history = parseHistory(data);
        System.println("Tempust: history points=" + ((history != null) ? history.size() : 0));

        invokeCallback(new WeatherResult(
            RESULT_OK, _pendingTemperatureCelsius, _pendingStationName, history, _pendingHttpCode
        ));
    }

    private function classNameOf(value as Lang.Object?) as Lang.String {
        if (value == null) {
            return "null";
        }
        if (value instanceof Lang.Dictionary) {
            return "Dictionary(keys=" + (value as Lang.Dictionary).keys() + ")";
        }
        if (value instanceof Lang.String) {
            var s = value as Lang.String;
            var preview = (s.length() > 80) ? (s.substring(0, 80) as Lang.String) + "..." : s;
            return "String(" + preview + ")";
        }
        return value.toString();
    }

    // Response shape confirmed against a live request (?p=<id>&data=1&
    // span=1day&cli=...): { "stations": [ { ..., "data": [ { "datetime":
    // "...", "temperatur": "12.3" }, ... ] } ] } - readings come back
    // oldest-to-newest already, at whatever interval the station
    // reports (often every couple of minutes), and can include the
    // literal string "temperatur":"NaN" for a glitched reading, which
    // toFloat() turns into null - skipped below rather than let a null
    // slip into a Float array.
    private function parseHistory(data as Lang.Dictionary or Lang.String or Null) as Lang.Array<Lang.Float>? {
        if (data == null || !(data instanceof Lang.Dictionary)) {
            System.println("Tempust: parseHistory - no dictionary in response");
            return null;
        }

        var stations = data.get("stations");
        if (!(stations instanceof Lang.Array) || stations.size() == 0) {
            System.println("Tempust: parseHistory - no 'stations' array");
            return null;
        }

        var station = stations[0] as Lang.Dictionary;
        var rawEntries = station.get("data");
        if (!(rawEntries instanceof Lang.Array) || rawEntries.size() == 0) {
            System.println("Tempust: parseHistory - no 'data' array on station (keys=" + station.keys() + ")");
            return null;
        }
        System.println("Tempust: parseHistory - found " + rawEntries.size() + " raw entries");

        var values = [] as Lang.Array<Lang.Float>;
        var i = 0;
        while (i < rawEntries.size()) {
            var entry = rawEntries[i];
            i += 1;
            if (!(entry instanceof Lang.Dictionary)) {
                continue;
            }
            var rawValue = entry.get("temperatur");
            if (rawValue == null) {
                continue;
            }
            var parsed = rawValue.toString().toFloat();
            if (parsed == null) {
                continue;
            }
            values.add(parsed);
        }

        return (values.size() >= 2) ? downsample(values, HISTORY_MAX_POINTS) : null;
    }

    // Evenly strides down to at most maxPoints entries, keeping the
    // oldest-to-newest order intact.
    private function downsample(values as Lang.Array<Lang.Float>, maxPoints as Lang.Number) as Lang.Array<Lang.Float> {
        if (values.size() <= maxPoints) {
            return values;
        }

        var stride = (values.size() + maxPoints - 1) / maxPoints;
        var result = [] as Lang.Array<Lang.Float>;
        var i = 0;
        while (i < values.size()) {
            result.add(values[i]);
            i += stride;
        }
        return result;
    }

    // Clears _callback before invoking, so the "exactly once" promise
    // above holds even if a late position update and the timeout race
    // each other.
    private function invokeCallback(result as WeatherResult) as Void {
        var callback = _callback;
        _callback = null;
        if (callback != null) {
            callback.invoke(result);
        }
    }
}