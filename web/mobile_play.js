/* Mobile web: CSS 90° landscape fill + best-effort fullscreen (hides browser chrome when allowed). */
(function () {
	var banner = null;
	var appliedPortraitCss = false;

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
		// Discord / Facebook / Instagram / etc. custom tabs often block fullscreen.
		if (/Discord|FBAN|FBAV|Instagram|Line\//i.test(ua)) return true;
		// Android Custom Tab chrome often exposes an "X" close affordance; UA still says Chrome.
		try {
			if (document.referrer && /discord\.com|discordapp\.com/i.test(document.referrer)) return true;
		} catch (e) {}
		return false;
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

	/** When the phone is upright (portrait), rotate the game 90° so it fills the screen as landscape. */
	function applyCssLandscape() {
		var c = canvasEl();
		if (!c) return;

		if (!isPortrait()) {
			if (appliedPortraitCss) {
				clearCanvasCss(c);
				appliedPortraitCss = false;
				notifyGodotResize();
			}
			// Fill the landscape browser viewport.
			c.style.width = "100vw";
			c.style.height = "100vh";
			c.style.maxWidth = "100vw";
			c.style.maxHeight = "100vh";
			return;
		}

		var w = window.innerWidth || document.documentElement.clientWidth;
		var h = window.innerHeight || document.documentElement.clientHeight;
		c.style.position = "fixed";
		c.style.left = "50%";
		c.style.top = "50%";
		// After rotate(90deg), width maps to visual height and height to visual width.
		c.style.width = h + "px";
		c.style.height = w + "px";
		c.style.maxWidth = "none";
		c.style.maxHeight = "none";
		c.style.transformOrigin = "center center";
		c.style.transform = "translate(-50%, -50%) rotate(90deg)";
		c.style.zIndex = "1";
		c.style.margin = "0";
		appliedPortraitCss = true;
		notifyGodotResize();
	}

	function notifyGodotResize() {
		try {
			window.dispatchEvent(new Event("resize"));
		} catch (e) {}
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
			"This Discord/in-app browser blocks it. Tap <b>⋮ → Open in Chrome</b>, " +
			"or <b>Add to Home screen</b>, then open that icon." +
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

	function refreshBanner() {
		var el = ensureBanner();
		var dismissed = false;
		try {
			dismissed = sessionStorage.getItem("wd_fs_banner_dismissed") === "1";
		} catch (e) {}
		var show =
			!isStandalone() &&
			!dismissed &&
			(isInAppBrowser() || !document.fullscreenElement);
		// Only nag when fullscreen clearly failed after a gesture, or in-app browser.
		if (isInAppBrowser() && !dismissed) {
			el.style.display = "block";
		} else if (!show) {
			el.style.display = "none";
		}
	}

	function requestFullscreen() {
		var targets = [
			canvasEl(),
			document.documentElement,
			document.body,
		].filter(Boolean);

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
				return Promise.resolve(!!(document.fullscreenElement || document.webkitFullscreenElement));
			} catch (e) {
				return tryOne(i + 1);
			}
		}
		return tryOne(0);
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
		applyCssLandscape();
		return requestFullscreen()
			.then(function (ok) {
				if (!ok && (isInAppBrowser() || !isStandalone())) {
					refreshBanner();
					var el = ensureBanner();
					if (!isInAppBrowser()) {
						// Soft tip if normal Chrome still refused fullscreen.
						try {
							if (sessionStorage.getItem("wd_fs_banner_dismissed") !== "1") {
								el.style.display = "block";
								el.querySelector("div").innerHTML =
									"<div style=\"display:flex;gap:10px;align-items:flex-start;\">" +
									'<div style="flex:1;"><b>Fullscreen blocked</b><br>' +
									"Tap again, or use Chrome menu → <b>Add to Home screen</b> for an app-like view.</div>" +
									'<button type="button" id="wd-fs-banner-x" style="background:#333;color:#fff;border:0;border-radius:6px;padding:6px 10px;">OK</button></div>';
								var b = el.querySelector("#wd-fs-banner-x");
								if (b) {
									b.onclick = function () {
										el.style.display = "none";
										sessionStorage.setItem("wd_fs_banner_dismissed", "1");
									};
								}
							}
						} catch (e) {}
					}
				}
				return lockLandscape();
			})
			.then(function () {
				applyCssLandscape();
				try {
					window.scrollTo(0, 1);
				} catch (e) {}
				return true;
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
		if (isInAppBrowser()) refreshBanner();
		window.addEventListener("resize", function () {
			applyCssLandscape();
		});
		window.addEventListener("orientationchange", function () {
			setTimeout(applyCssLandscape, 50);
			setTimeout(applyCssLandscape, 250);
			setTimeout(applyCssLandscape, 600);
		});
		document.addEventListener("fullscreenchange", applyCssLandscape);
		document.addEventListener("webkitfullscreenchange", applyCssLandscape);

		function onGesture() {
			enterPlayMode();
		}
		document.addEventListener("pointerdown", onGesture, true);
		document.addEventListener("touchstart", onGesture, true);
		document.addEventListener("click", onGesture, true);
	}

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", boot);
	} else {
		boot();
	}
})();
