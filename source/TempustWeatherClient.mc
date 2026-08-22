import Toybox.Communications;
import Toybox.Position;
import Toybox.Lang;

// Values must match resources/properties/properties.xml and
// resources/settings/settings.xml (the "TempUnit" list setting).
const UNIT_CELSIUS = 0;
const UNIT_FAHRENHEIT = 1;

// Outcome codes returned to the caller via WeatherResult.status.
const RESULT_OK = 0;
const RESULT_NO_POSITION = 1;
const RESULT_NO_STATION = 2;
const RESULT_NETWORK_ERROR = 3;

// Plain data holder passed back to whoever called fetchNearestTemperature().
// Keeping this as its own small class (rather than a loose Dictionary)
// makes the calling code self-documenting and easy to type-check.
class WeatherResult {
    public var status as Lang.Number;
    public var temperatureCelsius as Lang.Float?;
    public var stationName as Lang.String?;
    public var httpCode as Lang.Number?;

    function initialize(
        status as Lang.Number,
        temperatureCelsius as Lang.Float?,
        stationName as Lang.String?,
        httpCode as Lang.Number?
    ) {
        self.status = status;
        self.temperatureCelsius = temperatureCelsius;
        self.stationName = stationName;
        self.httpCode = httpCode;
    }
}

// Encapsulates everything needed to go from "no data" to "temperature
// at the nearest temperatur.nu station": acquiring a GPS fix, calling
// the API, and parsing the response. Kept separate from TempustView so
// the view only has to deal with UI state, not networking details.
class TempustWeatherClient {

    private const API_URL = "https://api.temperatur.nu/tnu_1.20.php";

    // Identifies this app to temperatur.nu. Unsigned clients are rate
    // limited to roughly 30 requests/hour and one identical request
    // per 5 minutes - fine for a single personal widget, but change
    // this to something unique to you if you ever see repeated
    // "blocked" responses.
    private const CLIENT_ID = "tempust_connectiq_widget_v1";

    private var _callback as Lang.Method?;

    // Kicks off the whole fetch flow. `callback` is invoked exactly
    // once with a WeatherResult, whether the fetch succeeded or failed.
    function fetchNearestTemperature(callback as Lang.Method) as Void {
        _callback = callback;
        Position.enableLocationEvents(Position.LOCATION_ONE_SHOT, method(:onPosition));
    }

    function onPosition(info as Position.Info) as Void {
        if (info == null || info.position == null) {
            invokeCallback(new WeatherResult(RESULT_NO_POSITION, null, null, null));
            return;
        }

        var degrees = info.position.toDegrees();
        requestNearestStation(degrees[0], degrees[1]);
    }

    private function requestNearestStation(lat as Lang.Double, lon as Lang.Double) as Void {
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
            invokeCallback(new WeatherResult(RESULT_NETWORK_ERROR, null, null, responseCode));
            return;
        }

        var stations = data.get("stations");
        if (stations == null || !(stations instanceof Lang.Array) || stations.size() == 0) {
            invokeCallback(new WeatherResult(RESULT_NO_STATION, null, null, responseCode));
            return;
        }

        var station = stations[0] as Lang.Dictionary;
        var rawTemp = station.get("temp");
        var rawName = station.get("title");

        // temperatur.nu always reports readings in Celsius; unit
        // conversion (if the user picked Fahrenheit) happens later,
        // in TempustView, purely for display.
        var temperatureCelsius = (rawTemp != null) ? rawTemp.toString().toFloat() : null;
        var stationName = (rawName != null) ? rawName.toString() : null;

        invokeCallback(new WeatherResult(RESULT_OK, temperatureCelsius, stationName, responseCode));
    }

    private function invokeCallback(result as WeatherResult) as Void {
        if (_callback != null) {
            _callback.invoke(result);
        }
    }
}
