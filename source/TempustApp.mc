import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Lang;

// Application entry point. Connect IQ looks up this class via the
// "entry" attribute in manifest.xml.
class TempustApp extends Application.AppBase {

    private var _view as TempustView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary?) as Void {
    }

    function onStop(state as Lang.Dictionary?) as Void {
    }

function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
    _view = new TempustView();
    return [ _view, new TempustDelegate(_view) ] as [WatchUi.Views, WatchUi.InputDelegates];
}

    // Called by the system to populate this widget's row on the glance
    // list (fenix 6+ and other Glance-capable devices). Kept as its own
    // tiny view/class (TempustGlanceView) rather than reusing TempustView,
    // since glance mode can run with as little as 32KB of memory - see
    // Core Topics > Glances in the Connect IQ SDK docs.
    (:glance)
    function getGlanceView() as [ WatchUi.GlanceView ] or [ WatchUi.GlanceView, WatchUi.GlanceViewDelegate ] or Null {
        return [ new TempustGlanceView() ];
    }

    // Called automatically whenever the user changes a setting for this
    // app in Garmin Connect Mobile / Garmin Express (e.g. the
    // Celsius/Fahrenheit picker). We forward it to the view so the
    // currently displayed reading is reformatted immediately, without
    // requiring the user to close and reopen the widget.
    function onSettingsChanged() as Void {
        if (_view != null) {
            _view.onSettingsChanged();
        }
        WatchUi.requestUpdate();
    }
}

function getApp() as TempustApp {
    return Application.getApp() as TempustApp;
}
