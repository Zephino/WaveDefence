/* Mobile/web helpers: CSS landscape fill, fullscreen button (menu + floating), Quit cleanup. */
(function () {
	var mode = ""; // "" | "portrait-css" | "landscape-fill"
	var enterInFlight = false;
	var released = false;
	var fsBtn = null;

	function isPortrait() {
		try {
			if (window.matchMedia) {
				if (window.matchMedia("(orientation: portrait)").matches) return true;
				if (window.matchMedia("(orientation: landscape)").matches) return false;
			}
		} catch (e) {}
		return (window.innerHeight || 0) > (window.innerWidth || 0);
	}

	function isFullscreen() {
		return !!(document.fullscreenElement || document.webkitFullscreenElement || document.msFullscreenElement);
	}

	function canvasEl() {
		return document.getElementById("canvas");
	}

	function clearCanvasCss(c) {
		if (!c) return;
		c.style.position = "";
		c.style.left = "";
		c.style.top = "";
		c.style.width = "";
		c.style.height = "";
		c.style.maxWidth = "";
		c.style.maxHeight = "";
		c.style.transform = "";
		c.style.transformOrigin = "";
		c.style.margin = "";
		c.style.zIndex = "";
	}

	function notifyGodotResize() {
		if (notifyGodotResize._t) clearTimeout(notifyGodotResize._t);
		notifyGodotResize._t = setTimeout(function () {
			try {
				window.dispatchEvent(new Event("resize"));
			} catch (e) {}
		}, 120);
	}

	function exitFullscreen() {
		var exit =
			document.exitFullscreen ||
			document.webkitExitFullscreen ||
			document.webkitCancelFullScreen ||
			document.msExitFullscreen;
		if (!exit || !isFullscreen()) return Promise.resolve(true);
		try {
			var out = exit.call(document);
			if (out && typeof out.then === "function") {
				return out.then(function () { return true; }).catch(function () { return true; });
			}
		} catch (e) {}
		return Promise.resolve(true);
	}

	function unlockOrientation() {
		try {
			if (screen.orientation && screen.orientation.unlock) {
				screen.orientation.unlock();
			}
		} catch (e) {}
	}

	function lockLandscape() {
		try {
			if (screen.orientation && screen.orientation.lock) {
				return screen.orientation.lock("landscape").catch(function () {
					return screen.orientation.lock("landscape-primary").catch(function () {
						return false;
					});
				});
			}
		} catch (e) {}
		return Promise.resolve(false);
	}

	function ensureFsButton() {
		if (fsBtn) return fsBtn;
		fsBtn = document.createElement("button");
		fsBtn.type = "button";
		fsBtn.id = "wd-fs-btn";
		fsBtn.textContent = "Fullscreen";
		fsBtn.style.cssText = [
			"position:fixed",
			"top:10px",
			"right:10px",
			"z-index:2147483645",
			"display:none",
			"padding:10px 14px",
			"border:0",
			"border-radius:8px",
			"background:#d4a017",
			"color:#141414",
			"font:600 15px/1.1 system-ui,sans-serif",
			"box-shadow:0 2px 10px rgba(0,0,0,0.45)",
			"touch-action:manipulation",
		].join(";");
		fsBtn.addEventListener("click", function (ev) {
			ev.preventDefault();
			ev.stopPropagation();
			enterFullscreen();
		});
		document.body.appendChild(fsBtn);
		return fsBtn;
	}

	/** Show floating Fullscreen when the browser dropped out of FS (sleep, swipe, etc.). */
	function refreshFsButton() {
		if (released) {
			if (fsBtn) fsBtn.style.display = "none";
			return;
		}
		var btn = ensureFsButton();
		btn.style.display = isFullscreen() ? "none" : "block";
	}

	/** Quit: undo fullscreen / CSS and try to leave the page. */
	function exitPlayMode() {
		released = true;
		enterInFlight = false;
		unlockOrientation();
		clearCanvasCss(canvasEl());
		mode = "";
		refreshFsButton();

		return exitFullscreen().then(function () {
			try {
				if (window.history && window.history.length > 1) {
					window.history.back();
					return true;
				}
			} catch (e) {}
			try {
				window.close();
			} catch (e) {}
			try {
				document.body.innerHTML =
					'<div style="min-height:100vh;display:flex;align-items:center;justify-content:center;' +
					'background:#101418;color:#e8eef2;font:18px/1.4 system-ui,sans-serif;text-align:center;padding:24px;">' +
					"<div><b>Wave Defence closed</b><br><br>You can close this tab or go back.</div></div>";
			} catch (e) {}
			return true;
		});
	}

	function applyCssLandscape() {
		if (released) return;
		var c = canvasEl();
		if (!c) return;

		var want = isPortrait() ? "portrait-css" : "landscape-fill";
		if (want === mode) return;
		mode = want;

		if (want === "landscape-fill") {
			clearCanvasCss(c);
			c.style.width = "100vw";
			c.style.height = "100vh";
			c.style.maxWidth = "100vw";
			c.style.maxHeight = "100vh";
			notifyGodotResize();
			return;
		}

		var w = window.innerWidth || document.documentElement.clientWidth;
		var h = window.innerHeight || document.documentElement.clientHeight;
		c.style.position = "fixed";
		c.style.left = "50%";
		c.style.top = "50%";
		c.style.width = h + "px";
		c.style.height = w + "px";
		c.style.maxWidth = "none";
		c.style.maxHeight = "none";
		c.style.transformOrigin = "center center";
		c.style.transform = "translate(-50%, -50%) rotate(90deg)";
		c.style.zIndex = "1";
		c.style.margin = "0";
		notifyGodotResize();
	}

	function requestFullscreen() {
		if (isFullscreen()) return Promise.resolve(true);
		var targets = [document.documentElement, document.body].filter(Boolean);

		function tryOne(i) {
			if (i >= targets.length) return Promise.resolve(false);
			var el = targets[i];
			var req =
				el.requestFullscreen ||
				el.webkitRequestFullscreen ||
				el.webkitRequestFullScreen ||
				el.msRequestFullscreen;
			if (!req) return tryOne(i + 1);
			try {
				var out = req.call(el, { navigationUI: "hide" });
				if (out && typeof out.then === "function") {
					return out.then(function () { return true; }).catch(function () {
						return tryOne(i + 1);
					});
				}
				return Promise.resolve(isFullscreen());
			} catch (e) {
				return tryOne(i + 1);
			}
		}
		return tryOne(0);
	}

	/** Menu Fullscreen button + floating restore button. */
	function enterFullscreen() {
		if (released || enterInFlight) return Promise.resolve(false);
		enterInFlight = true;
		mode = "";
		applyCssLandscape();
		return requestFullscreen()
			.then(function () {
				return lockLandscape();
			})
			.then(function () {
				mode = "";
				applyCssLandscape();
				enterInFlight = false;
				refreshFsButton();
				return isFullscreen();
			})
			.catch(function () {
				enterInFlight = false;
				refreshFsButton();
				return false;
			});
	}

	function onResume() {
		if (released) return;
		// Screen timeout / app switch drops fullscreen; restore layout + show FS control.
		mode = "";
		applyCssLandscape();
		refreshFsButton();
	}

	window.WaveDefenceMobile = {
		enterFullscreen: enterFullscreen,
		exitPlayMode: exitPlayMode,
		applyCssLandscape: applyCssLandscape,
		isFullscreen: isFullscreen,
		refreshFsButton: refreshFsButton,
	};

	function boot() {
		applyCssLandscape();
		refreshFsButton();

		window.addEventListener("resize", function () {
			if (!released) applyCssLandscape();
		});
		window.addEventListener("orientationchange", function () {
			if (released) return;
			mode = "";
			setTimeout(applyCssLandscape, 80);
			setTimeout(function () {
				applyCssLandscape();
				refreshFsButton();
			}, 300);
		});
		document.addEventListener("fullscreenchange", function () {
			if (released) return;
			mode = "";
			applyCssLandscape();
			refreshFsButton();
		});
		document.addEventListener("webkitfullscreenchange", function () {
			if (released) return;
			mode = "";
			applyCssLandscape();
			refreshFsButton();
		});
		document.addEventListener("visibilitychange", function () {
			if (document.visibilityState === "visible") onResume();
		});
		window.addEventListener("pageshow", onResume);
		window.addEventListener("focus", onResume);
	}

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", boot);
	} else {
		boot();
	}
})();
