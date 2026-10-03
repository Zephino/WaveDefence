/* Mobile browser helpers: rotate prompt + best-effort fullscreen/landscape. */
(function () {
	var overlay = null;

	function isPortrait() {
		try {
			if (window.matchMedia) {
				if (window.matchMedia("(orientation: portrait)").matches) return true;
				if (window.matchMedia("(orientation: landscape)").matches) return false;
			}
		} catch (e) {}
		return window.innerHeight > window.innerWidth;
	}

	function ensureOverlay() {
		if (overlay) return overlay;
		overlay = document.createElement("div");
		overlay.id = "wd-rotate-overlay";
		overlay.innerHTML =
			'<div style="max-width:20rem;padding:1.25rem;font-family:system-ui,sans-serif;">' +
			'<div style="font-size:2.5rem;line-height:1;margin-bottom:0.75rem;">↻</div>' +
			"<div style=\"font-size:1.25rem;font-weight:700;margin-bottom:0.5rem;\">Rotate your phone</div>" +
			"<div style=\"font-size:0.95rem;opacity:0.9;line-height:1.35;\">" +
			"This game plays in <b>landscape</b>. Turn your phone sideways." +
			"<br><br>On iPhone, Safari often blocks fullscreen — for the best view use " +
			"<b>Share → Add to Home Screen</b>, then open that icon." +
			"</div></div>";
		overlay.style.cssText = [
			"position:fixed",
			"inset:0",
			"z-index:2147483647",
			"display:none",
			"align-items:center",
			"justify-content:center",
			"text-align:center",
			"color:#f2f4f6",
			"background:rgba(8,10,14,0.96)",
			"touch-action:none",
		].join(";");
		document.body.appendChild(overlay);
		return overlay;
	}

	function refreshRotatePrompt() {
		var el = ensureOverlay();
		el.style.display = isPortrait() ? "flex" : "none";
	}

	function getFullscreenElement() {
		return (
			document.fullscreenElement ||
			document.webkitFullscreenElement ||
			document.msFullscreenElement ||
			null
		);
	}

	function requestFullscreen() {
		var el = document.getElementById("canvas") || document.documentElement;
		var req =
			el.requestFullscreen ||
			el.webkitRequestFullscreen ||
			el.webkitRequestFullScreen ||
			el.msRequestFullscreen;
		if (!req) return Promise.resolve(false);
		try {
			var out = req.call(el);
			if (out && typeof out.then === "function") {
				return out.then(function () { return true; }).catch(function () { return false; });
			}
			return Promise.resolve(true);
		} catch (e) {
			return Promise.resolve(false);
		}
	}

	function lockLandscape() {
		try {
			if (screen.orientation && screen.orientation.lock) {
				return screen.orientation
					.lock("landscape")
					.then(function () { return true; })
					.catch(function () {
						return screen.orientation
							.lock("landscape-primary")
							.then(function () { return true; })
							.catch(function () { return false; });
					});
			}
		} catch (e) {}
		return Promise.resolve(false);
	}

	function enterPlayMode() {
		refreshRotatePrompt();
		// Fullscreen first (required on many Androids before orientation.lock works).
		return requestFullscreen().then(function () {
			return lockLandscape();
		}).then(function () {
			refreshRotatePrompt();
			try {
				window.scrollTo(0, 1);
			} catch (e) {}
			return true;
		});
	}

	window.WaveDefenceMobile = {
		enterPlayMode: enterPlayMode,
		refreshRotatePrompt: refreshRotatePrompt,
		isPortrait: isPortrait,
	};

	function boot() {
		ensureOverlay();
		refreshRotatePrompt();
		window.addEventListener("resize", refreshRotatePrompt);
		window.addEventListener("orientationchange", function () {
			setTimeout(refreshRotatePrompt, 50);
			setTimeout(refreshRotatePrompt, 300);
		});
		document.addEventListener("fullscreenchange", refreshRotatePrompt);
		document.addEventListener("webkitfullscreenchange", refreshRotatePrompt);
		// First user gesture anywhere on the page (captures better than Godot alone).
		function onFirstGesture() {
			enterPlayMode();
			document.removeEventListener("pointerdown", onFirstGesture, true);
			document.removeEventListener("touchstart", onFirstGesture, true);
			document.removeEventListener("click", onFirstGesture, true);
		}
		document.addEventListener("pointerdown", onFirstGesture, true);
		document.addEventListener("touchstart", onFirstGesture, true);
		document.addEventListener("click", onFirstGesture, true);
	}

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", boot);
	} else {
		boot();
	}
})();
