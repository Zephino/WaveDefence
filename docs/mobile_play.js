/* Mobile web: CSS 90° landscape fill + one-shot fullscreen (avoid black flashes on every tap). */
(function () {
	var banner = null;
	var mode = ""; // "" | "portrait-css" | "landscape-fill"
	var fullscreenAttempted = false;
	var enterInFlight = false;

	function isPortrait() {
		try {
			if (window.matchMedia) {
				if (window.matchMedia("(orientation: portrait)").matches) return true;
				if (window.matchMedia("(orientation: landscape)").matches) return false;
			}
		} catch (e) {}
		return (window.innerHeight || 0) > (window.innerWidth || 0);
	}

	function isStandalone() {
		try {
			if (window.matchMedia && window.matchMedia("(display-mode: standalone)").matches) return true;
			if (window.matchMedia && window.matchMedia("(display-mode: fullscreen)").matches) return true;
			if (navigator.standalone === true) return true;
		} catch (e) {}
		return false;
	}

	function isInAppBrowser() {
		var ua = navigator.userAgent || "";
		if (/Discord|FBAN|FBAV|Instagram|Line\//i.test(ua)) return true;
		try {
			if (document.referrer && /discord\.com|discordapp\.com/i.test(document.referrer)) return true;
		} catch (e) {}
		return false;
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
		// Debounced — firing resize on every tap blanks the WebGL canvas on many phones.
		if (notifyGodotResize._t) clearTimeout(notifyGodotResize._t);
		notifyGodotResize._t = setTimeout(function () {
			try {
				window.dispatchEvent(new Event("resize"));
			} catch (e) {}
		}, 120);
	}

	/** Apply CSS only when orientation mode actually changes. */
	function applyCssLandscape() {
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

	function ensureBanner() {
		if (banner) return banner;
		banner = document.createElement("div");
		banner.id = "wd-fs-banner";
		banner.style.cssText = [
			"position:fixed",
			"left:0",
			"right:0",
			"bottom:0",
			"z-index:2147483646",
			"display:none",
			"padding:10px 12px",
			"background:rgba(12,14,18,0.94)",
			"color:#f0f3f6",
			"font:14px/1.35 system-ui,sans-serif",
			"border-top:1px solid rgba(255,255,255,0.12)",
		].join(";");
		banner.innerHTML =
			'<div style="display:flex;gap:10px;align-items:flex-start;">' +
			'<div style="flex:1;">' +
			"<b>Want the real fullscreen app look?</b><br>" +
			"In-app browsers (Discord, etc.) block it. Tap <b>⋮ → Open in Chrome</b>, " +
			"or <b>Add to Home screen</b>." +
			"</div>" +
			'<button type="button" id="wd-fs-banner-x" style="background:#333;color:#fff;border:0;border-radius:6px;padding:6px 10px;">OK</button>' +
			"</div>";
		document.body.appendChild(banner);
		var btn = banner.querySelector("#wd-fs-banner-x");
		if (btn) {
			btn.addEventListener("click", function () {
				banner.style.display = "none";
				try {
					sessionStorage.setItem("wd_fs_banner_dismissed", "1");
				} catch (e) {}
			});
		}
		return banner;
	}

	function showFsTip() {
		var dismissed = false;
		try {
			dismissed = sessionStorage.getItem("wd_fs_banner_dismissed") === "1";
		} catch (e) {}
		if (dismissed || isStandalone()) return;
		ensureBanner().style.display = "block";
	}

	function requestFullscreen() {
		if (isFullscreen()) return Promise.resolve(true);
		var targets = [document.documentElement, document.body, canvasEl()].filter(Boolean);

		function tryOne(i) {
			if (i >= targets.length) return Promise.resolve(false);
			var el = targets[i];
			// Prefer documentElement — fullscreen on the WebGL canvas often blacks out Godot.
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

	/**
	 * @param {object} [opts]
	 * @param {boolean} [opts.forceFullscreen] — request FS even if we already tried
	 */
	function enterPlayMode(opts) {
		opts = opts || {};
		applyCssLandscape();

		var needFs = opts.forceFullscreen || (!fullscreenAttempted && !isFullscreen());
		if (!needFs || enterInFlight) {
			return Promise.resolve(true);
		}
		enterInFlight = true;
		fullscreenAttempted = true;

		return requestFullscreen()
			.then(function (ok) {
				if (!ok) showFsTip();
				return lockLandscape();
			})
			.then(function () {
				applyCssLandscape();
				enterInFlight = false;
				return true;
			})
			.catch(function () {
				enterInFlight = false;
				return false;
			});
	}

	window.WaveDefenceMobile = {
		enterPlayMode: enterPlayMode,
		applyCssLandscape: applyCssLandscape,
		isPortrait: isPortrait,
		refreshRotatePrompt: applyCssLandscape,
	};

	function boot() {
		applyCssLandscape();
		if (isInAppBrowser()) showFsTip();

		window.addEventListener("resize", function () {
			applyCssLandscape();
		});
		window.addEventListener("orientationchange", function () {
			mode = ""; // force recompute after rotate
			setTimeout(applyCssLandscape, 80);
			setTimeout(applyCssLandscape, 300);
		});
		document.addEventListener("fullscreenchange", function () {
			mode = "";
			applyCssLandscape();
		});
		document.addEventListener("webkitfullscreenchange", function () {
			mode = "";
			applyCssLandscape();
		});

		// One gesture only for fullscreen — repeating it on every button tap caused black flashes.
		function onFirstGesture() {
			enterPlayMode({ forceFullscreen: true });
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
