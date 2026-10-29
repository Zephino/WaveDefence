class_name WaveSuggestionEnvironment
extends RefCounted
## Coarse, non-identifying environment information attached to suggestions.
## Browser user-agent is examined locally and NEVER sent to the server.
## Browser/OS categories are best effort; exact hardware model is not collected.

const WEB_INFO_SCRIPT := """
(() => {
  const ua = navigator.userAgent || "";
  const ipad = /iPad/i.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  let os = "Unknown";
  if (ipad || /iPhone|iPod/i.test(ua)) os = "iOS";
  else if (/Android/i.test(ua)) os = "Android";
  else if (/Windows/i.test(ua)) os = "Windows";
  else if (/CrOS/i.test(ua)) os = "ChromeOS";
  else if (/Mac OS X|Macintosh/i.test(ua)) os = "macOS";
  else if (/Linux/i.test(ua)) os = "Linux";

  let device = "Desktop";
  if (ipad || /Tablet/i.test(ua) || (os === "Android" && !/Mobile/i.test(ua))) device = "Tablet";
  else if (/iPhone|iPod|Android|Mobile/i.test(ua)) device = "Phone";

  let browser = "Other";
  if (/SamsungBrowser/i.test(ua)) browser = "Samsung Internet";
  else if (/Edg|Edge|EdgiOS/i.test(ua)) browser = "Edge";
  else if (/OPR|Opera/i.test(ua)) browser = "Opera";
  else if (/Firefox|FxiOS/i.test(ua)) browser = "Firefox";
  else if (/Chrome|CriOS/i.test(ua)) browser = "Chrome";
  else if (/Safari/i.test(ua)) browser = "Safari";

  return [device, os, browser].join("|");
})()
"""


static func collect() -> Dictionary:
	var version: String = VersionInfo.current()
	var os_name: String = OS.get_name()
	var details := {
		"game_version": version,
		"runtime": "Native",
		"device_type": "Phone" if os_name == "Android" or os_name == "iOS" else "Desktop",
		"platform": os_name,
		"browser": "N/A",
	}
	if not OS.has_feature("web"):
		return details
	details["runtime"] = "Web"
	details["device_type"] = "Unknown"
	details["platform"] = "Unknown"
	details["browser"] = "Other"
	var raw: Variant = JavaScriptBridge.eval(WEB_INFO_SCRIPT)
	if raw is String:
		var parts: PackedStringArray = (raw as String).split("|")
		if parts.size() == 3:
			details["device_type"] = parts[0]
			details["platform"] = parts[1]
			details["browser"] = parts[2]
	return details
