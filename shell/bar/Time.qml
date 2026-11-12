pragma Singleton
// Clock/time formatting singleton used by the bar.
// Formats current time/date according to MuzeSettings (24h/seconds) so
// consumers can bind to `timeString`/`dateString` directly.

import Quickshell
import QtQuick
import "root:/settings"

// Singleton providing formatted clock strings for the bar.
// Reads user preferences from MuzeSettings (24h/seconds) and updates via
// SystemClock. Exposed as properties so Bar/other consumers can bind directly.
Singleton {
  id: root

  // Guard against the settings singleton not being initialised yet on the
  // very first evaluation (avoids "Unable to assign [undefined] to QString").
  readonly property string timeString: {
    const use24 = MuzeSettings.use24h === undefined ? true : MuzeSettings.use24h
    const secs = MuzeSettings.clockSeconds === undefined ? false : MuzeSettings.clockSeconds
    const fmt = use24
      ? (secs ? "HH:mm:ss" : "HH:mm")
      : (secs ? "h:mm:ss ap" : "h:mm ap")
    Qt.formatDateTime(clock.date, fmt)
  }

  readonly property string dateString: {
    Qt.formatDateTime(clock.date, "ddd MMM d")
  }

  // Ticks every second; format strings above decide what is shown.
  SystemClock {
    id: clock
    precision: SystemClock.Seconds
  }
}
