import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

// Handles user input for the widget. SELECT (or a tap, on touchscreen
// devices - BehaviorDelegate maps both to onSelect automatically)
// normally triggers a manual refresh.
//
// Easter egg: tapping SELECT EASTER_EGG_TAP_COUNT times in quick
// succession (each tap within RAPID_TAP_WINDOW_MS of the previous one)
// unlocks "sauna mode" in the view instead of refreshing. Every tap
// resets a short debounce timer, so a whole burst of taps resolves
// into exactly ONE action once the burst ends - either the easter egg,
// or a single refresh() call. This matters for more than UX: it stops
// a rapid-tap burst from firing one API request per tap, which could
// trip temperatur.nu's "max one identical request per 5 minutes" rate
// limit (see README).
class TempustDelegate extends WatchUi.BehaviorDelegate {

    private const RAPID_TAP_WINDOW_MS = 600;
    private const EASTER_EGG_TAP_COUNT = 5;
    private const TAP_DEBOUNCE_MS = 450;

    private var _view as TempustView;
    private var _tapCount as Lang.Number = 0;
    private var _lastTapTime as Lang.Number = 0;
    private var _debounceTimer as Timer.Timer?;

    function initialize(view as TempustView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Lang.Boolean {
        var now = System.getTimer();

        if (_tapCount > 0 && (now - _lastTapTime) <= RAPID_TAP_WINDOW_MS) {
            _tapCount += 1;
        } else {
            _tapCount = 1;
        }
        _lastTapTime = now;

        if (_debounceTimer != null) {
            _debounceTimer.stop();
        } else {
            _debounceTimer = new Timer.Timer();
        }
        _debounceTimer.start(method(:onDebounceExpired), TAP_DEBOUNCE_MS, false);

        return true;
    }

    // Fires once, TAP_DEBOUNCE_MS after the last tap in a burst.
    function onDebounceExpired() as Void {
        var taps = _tapCount;
        _tapCount = 0;

        if (taps >= EASTER_EGG_TAP_COUNT) {
            _view.triggerEasterEgg();
        } else {
            _view.refresh();
        }
    }

    function onMenu() as Lang.Boolean {
        _view.refresh();
        return true;
    }
}
