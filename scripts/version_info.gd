class_name VersionInfo
extends RefCounted

## Single place to read the displayed app version.
## Prefers root VERSION (canonical), then project setting (always present in exports).

const VERSION_PATH := "res://VERSION"


static func current() -> String:
	if FileAccess.file_exists(VERSION_PATH):
		var f := FileAccess.open(VERSION_PATH, FileAccess.READ)
		if f:
			var text := f.get_as_text().strip_edges()
			if not text.is_empty():
				return text
	var from_settings := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	if not from_settings.is_empty():
		return from_settings
	return "00.01.00"


static func label() -> String:
	return "v%s" % current()
