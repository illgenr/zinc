#pragma once

#include <QString>

namespace zinc::ui {

// Installs a Qt message handler that logs to a file. On Windows GUI builds,
// stdout/stderr are often not visible, so this makes crash repros actionable.
void install_file_logging();

// Returns the default log file path (may be empty if unavailable).
QString default_log_file_path();

} // namespace zinc::ui
