/* Mobile/web helpers: CSS landscape, fullscreen (real DOM gesture), PWA install, audio unlock. */
(function () {
	var mode = ""; // "" | "portrait-css" | "landscape-fill"
	var enterInFlight = false;
	var released = false;
	var fsBtn = null;
	var fsModal = null;
	var installModal = null;
	var startGate = null;
	var deferredPrompt = null;
	var cssFullscreen = false;
	var audioContexts = [];
	var audioUnlocked = false;

	// Patch early (before Godot boots) so we can resume the engine AudioContext after a tap.
	(function patchAudioContext() {
		var Orig = window.AudioContext || window.webkitAudioContext;
		if (!Orig || Orig.__wdPatched) return;
		function wrap(Base) {
			function Patched(options) {
				var ctx = new Base(options);
				audioContexts.push(ctx);
				return ctx;
			}
			Patched.prototype = Base.prototype;
			Patched.__wdPatched = true;
			try {
				Object.keys(Base).forEach(function (k) {
					try { Patched[k] = Base[k]; } catch (e) {}
				});
			} catch (e) {}
			return Patched;
		}
		if (window.AudioContext) window.AudioContext = wrap(window.AudioContext);
		if (window.webkitAudioContext) window.webkitAudioContext = wrap(window.webkitAudioContext);
	})();

	function resumeOne(ctx) {
		if (!ctx || ctx.state !== "suspended") return;
		try { ctx.resume(); } catch (e) {}
	}

	function resumeAudioContexts() {
		for (var i = 0; i < audioContexts.length; i++) {
			resumeOne(audioContexts[i]);
		}
		try {
			if (window.__wdAudioKick) resumeOne(window.__wdAudioKick);
		} catch (e) {}
	}

	function unlockAudio() {
		resumeAudioContexts();
		try {
			var Ctx = window.AudioContext || window.webkitAudioContext;
			if (Ctx && !window.__wdAudioKick) {
				window.__wdAudioKick = new Ctx();
				var buf = window.__wdAudioKick.createBuffer(1, 1, 22050);
				var src = window.__wdAudioKick.createBufferSource();
				src.buffer = buf;
				src.connect(window.__wdAudioKick.destination);
				src.start(0);
			}
			resumeOne(window.__wdAudioKick);
		} catch (e) {}
	}

	function unlockAndStartGame() {
		unlockAudio();
		audioUnlocked = true;
		window.__wdAudioUnlocked = true;
		hideStartGate();
		try {
			if (typeof window.__wdGodotUnlock === "function") {
				window.__wdGodotUnlock();
			}
		} catch (e) {}
	}

	function ensureStartGate() {
		if (startGate) return startGate;
		startGate = document.createElement("div");
		startGate.id = "wd-start-gate";
		startGate.style.cssText = [
			"position:fixed",
			"inset:0",
			"z-index:2147483647",
			"display:flex",
			"align-items:center",
			"justify-content:center",
			"background:rgba(8,10,14,0.92)",
			"padding:24px",
			"box-sizing:border-box",
		].join(";");
		var card = document.createElement("div");
		card.style.cssText = [
			"max-width:360px",
			"width:100%",
			"background:#1a222c",
			"color:#e8eef2",
			"border-radius:12px",
			"padding:22px 18px",
			"text-align:center",
			"font:16px/1.35 system-ui,sans-serif",
			"box-shadow:0 12px 40px rgba(0,0,0,0.45)",
		].join(";");
		card.innerHTML = "<b style=\"font-size:22px;display:block;margin-bottom:10px;\">Wave Defence</b>" +
			"<div style=\"opacity:0.85;margin-bottom:16px;\">Browsers block game audio until you tap. Tap below to start with sound.</div>";
		var go = document.createElement("button");
		go.type = "button";
		go.textContent = "Tap to start";
		go.style.cssText = [
			"display:block",
			"width:100%",
			"padding:16px 16px",
			"border:0",
			"border-radius:8px",
			"background:#d4a017",
			"color:#141414",
			"font:700 18px/1.1 system-ui,sans-serif",
			"touch-action:manipulation",
		].join(";");
		go.addEventListener("click", function (ev) {
			ev.preventDefault();
			ev.stopPropagation();
			unlockAndStartGame();
		});
		card.appendChild(go);
		startGate.appendChild(card);
		document.body.appendChild(startGate);
		return startGate;
	}

	function hideStartGate() {
		if (startGate) startGate.style.display = "none";
	}

	function isTouchish() {
		try {
			if (window.matchMedia && window.matchMedia("(pointer: coarse)").matches) return true;
		} catch (e) {}
		return "ontouchstart" in window || (navigator.maxTouchPoints || 0) > 0;
	}

	function isIos() {
		return /iphone|ipad|ipod/i.test(navigator.userAgent || "") ||
			(navigator.platform === "MacIntel" && (navigator.maxTouchPoints || 0) > 1);
	}

	/** True only when launched as an installed PWA / home-screen icon — not browser fullscreen. */
	function isStandalone() {
		try {
			if (window.matchMedia && window.matchMedia("(display-mode: standalone)").matches) return true;
			if (window.matchMedia && window.matchMedia("(display-mode: minimal-ui)").matches) return true;
		} catch (e) {}
		// iOS Safari: only set when opened from Add to Home Screen.
		if (typeof navigator.standalone === "boolean") return !!navigator.standalone;
		// Android Trusted Web Activity / related-app launch.
		try {
			if (document.referrer && document.referrer.indexOf("android-app://") === 0) return true;
		} catch (e) {}
		return false;
	}

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

	function fullscreenOk() {
		return isFullscreen() || cssFullscreen || isStandalone();
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

	function styleChipButton(el, bg) {
		el.style.cssText = [
			"position:fixed",
			"z-index:2147483645",
			"display:none",
			"padding:10px 14px",
			"border:0",
			"border-radius:8px",
			"background:" + bg,
			"color:#141414",
			"font:600 15px/1.1 system-ui,sans-serif",
			"box-shadow:0 2px 10px rgba(0,0,0,0.45)",
			"touch-action:manipulation",
			"-webkit-tap-highlight-color:transparent",
		].join(";");
	}

	function ensureFsButton() {
		if (fsBtn) return fsBtn;
		fsBtn = document.createElement("button");
		fsBtn.type = "button";
		fsBtn.id = "wd-fs-btn";
		fsBtn.textContent = "Fullscreen";
		styleChipButton(fsBtn, "#d4a017");
		fsBtn.style.top = "10px";
		fsBtn.style.right = "10px";
		fsBtn.addEventListener("click", function (ev) {
			ev.preventDefault();
			ev.stopPropagation();
			hideFsModal();
			enterFullscreen();
		});
		document.body.appendChild(fsBtn);
		return fsBtn;
	}

	function ensureFsModal() {
		if (fsModal) return fsModal;
		fsModal = document.createElement("div");
		fsModal.id = "wd-fs-modal";
		fsModal.style.cssText = [
			"position:fixed",
			"inset:0",
			"z-index:2147483646",
			"display:none",
			"align-items:center",
			"justify-content:center",
			"background:rgba(8,10,14,0.72)",
			"padding:24px",
			"box-sizing:border-box",
		].join(";");
		var card = document.createElement("div");
		card.style.cssText = [
			"max-width:360px",
			"width:100%",
			"background:#1a222c",
			"color:#e8eef2",
			"border-radius:12px",
			"padding:22px 18px",
			"text-align:center",
			"font:16px/1.35 system-ui,sans-serif",
			"box-shadow:0 12px 40px rgba(0,0,0,0.45)",
		].join(";");
		card.innerHTML = "<b style=\"font-size:20px;display:block;margin-bottom:10px;\">Go fullscreen</b>" +
			"<div style=\"opacity:0.85;margin-bottom:16px;\">Browsers only allow fullscreen from a real tap. Tap the button below.</div>";
		var go = document.createElement("button");
		go.type = "button";
		go.textContent = "Tap for Fullscreen";
		go.style.cssText = [
			"display:block",
			"width:100%",
			"padding:14px 16px",
			"border:0",
			"border-radius:8px",
			"background:#d4a017",
			"color:#141414",
			"font:700 17px/1.1 system-ui,sans-serif",
			"touch-action:manipulation",
		].join(";");
		go.addEventListener("click", function (ev) {
			ev.preventDefault();
			ev.stopPropagation();
			hideFsModal();
			enterFullscreen();
		});
		var cancel = document.createElement("button");
		cancel.type = "button";
		cancel.textContent = "Not now";
		cancel.style.cssText = [
			"display:block",
			"width:100%",
			"margin-top:10px",
			"padding:12px 16px",
			"border:0",
			"border-radius:8px",
			"background:#2a3440",
			"color:#d7dee5",
			"font:600 15px/1.1 system-ui,sans-serif",
			"touch-action:manipulation",
		].join(";");
		cancel.addEventListener("click", function (ev) {
			ev.preventDefault();
			ev.stopPropagation();
			hideFsModal();
			refreshChromeButtons();
		});
		card.appendChild(go);
		card.appendChild(cancel);
		fsModal.appendChild(card);
		document.body.appendChild(fsModal);
		return fsModal;
	}

	function showFsModal() {
		var m = ensureFsModal();
		m.style.display = "flex";
		ensureFsButton().style.display = "block";
	}

	function hideFsModal() {
		if (fsModal) fsModal.style.display = "none";
	}

	function hideInstallModal() {
		if (installModal) installModal.style.display = "none";
	}

	function ensureInstallModal() {
		if (installModal) return installModal;
		installModal = document.createElement("div");
		installModal.id = "wd-install-modal";
		installModal.style.cssText = [
			"position:fixed",
			"inset:0",
			"z-index:2147483646",
			"display:none",
			"align-items:center",
			"justify-content:center",
			"background:rgba(8,10,14,0.72)",
			"padding:24px",
			"box-sizing:border-box",
		].join(";");
		document.body.appendChild(installModal);
		return installModal;
	}

	function showInstallCard(title, bodyHtml, primaryLabel, primaryFn) {
		var m = ensureInstallModal();
		m.innerHTML = "";
		var card = document.createElement("div");
		card.style.cssText = [
			"max-width:360px",
			"width:100%",
			"background:#1a222c",
			"color:#e8eef2",
			"border-radius:12px",
			"padding:22px 18px",
			"text-align:center",
			"font:16px/1.35 system-ui,sans-serif",
			"box-shadow:0 12px 40px rgba(0,0,0,0.45)",
		].join(";");
		var h = document.createElement("b");
		h.style.cssText = "font-size:20px;display:block;margin-bottom:10px;";
		h.textContent = title;
		card.appendChild(h);
		var body = document.createElement("div");
		body.style.cssText = "opacity:0.9;margin-bottom:16px;text-align:left;";
		body.innerHTML = bodyHtml;
		card.appendChild(body);
		if (primaryLabel && primaryFn) {
			var go = document.createElement("button");
			go.type = "button";
			go.textContent = primaryLabel;
			go.style.cssText = [
				"display:block",
				"width:100%",
				"padding:14px 16px",
				"border:0",
				"border-radius:8px",
				"background:#3d9a68",
				"color:#f4fff8",
				"font:700 17px/1.1 system-ui,sans-serif",
				"touch-action:manipulation",
			].join(";");
			go.addEventListener("click", function (ev) {
				ev.preventDefault();
				ev.stopPropagation();
				primaryFn();
			});
			card.appendChild(go);
		}
		var cancel = document.createElement("button");
		cancel.type = "button";
		cancel.textContent = "Close";
		cancel.style.cssText = [
			"display:block",
			"width:100%",
			"margin-top:10px",
			"padding:12px 16px",
			"border:0",
			"border-radius:8px",
			"background:#2a3440",
			"color:#d7dee5",
			"font:600 15px/1.1 system-ui,sans-serif",
			"touch-action:manipulation",
		].join(";");
		cancel.addEventListener("click", function (ev) {
			ev.preventDefault();
			ev.stopPropagation();
			hideInstallModal();
		});
		card.appendChild(cancel);
		m.appendChild(card);
		m.style.display = "flex";
	}

	function refreshChromeButtons() {
		if (released) {
			if (fsBtn) fsBtn.style.display = "none";
			hideFsModal();
			hideInstallModal();
			return;
		}
		var btn = ensureFsButton();
		btn.style.display = fullscreenOk() ? "none" : "block";
	}

	function runInstallFromGesture() {
		if (!deferredPrompt) return false;
		var prompt = deferredPrompt;
		deferredPrompt = null;
		hideInstallModal();
		prompt.prompt();
		Promise.resolve(prompt.userChoice).then(function () {
			deferredPrompt = null;
		}).catch(function () {});
		return true;
	}

	/** Called from Settings → Install app (web only). */
	function promptInstall() {
		if (released) return false;
		// Prefer a real Chromium install prompt whenever the browser offered one.
		// Do this BEFORE the standalone check so fullscreen mode never blocks install.
		if (deferredPrompt) {
			showInstallCard(
				"Install Wave Defence",
				"Tap below to add the game to your home screen. Browsers require a real tap to show the install prompt.",
				"Tap to Install",
				runInstallFromGesture
			);
			return true;
		}
		if (isStandalone()) {
			showInstallCard(
				"Already on home screen",
				"This copy is already running from your home-screen app icon. " +
				"If you still only see a browser tab, close this and open the Wave Defence icon instead — " +
				"or use your browser menu → <b>Install app</b> / <b>Add to Home screen</b>."
			);
			return true;
		}
		if (isIos()) {
			showInstallCard(
				"Add to Home Screen",
				"Safari cannot auto-install. Tap <b>Share</b> (square with arrow) → <b>Add to Home Screen</b>, " +
				"then open the new Wave Defence icon for app-style play."
			);
			return true;
		}
		showInstallCard(
			"Install from browser",
			"Chrome has not offered an install prompt yet. Try: open the ⋮ menu → <b>Install app</b> or " +
			"<b>Add to Home screen</b>. Stay on this page a few seconds, then try Install app again. " +
			"Use Chrome (or Edge) on Android for the easiest install."
		);
		return false;
	}

	/** Quit: undo fullscreen / CSS and try to leave the page. */
	function exitPlayMode() {
		released = true;
		enterInFlight = false;
		cssFullscreen = false;
		unlockOrientation();
		clearCanvasCss(canvasEl());
		mode = "";
		refreshChromeButtons();

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
		var targets = [document.documentElement, document.body, canvasEl()].filter(Boolean);

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

	/** Real-gesture fullscreen (floating button / modal). */
	function enterFullscreen() {
		if (released || enterInFlight) return Promise.resolve(false);
		enterInFlight = true;
		mode = "";
		applyCssLandscape();
		return requestFullscreen()
			.then(function (ok) {
				if (!ok && isTouchish()) {
					// iOS / restricted browsers: CSS fill is the practical fullscreen.
					cssFullscreen = true;
				}
				return lockLandscape();
			})
			.then(function () {
				mode = "";
				applyCssLandscape();
				enterInFlight = false;
				refreshChromeButtons();
				return fullscreenOk();
			})
			.catch(function () {
				enterInFlight = false;
				if (isTouchish()) cssFullscreen = true;
				refreshChromeButtons();
				return fullscreenOk();
			});
	}

	/**
	 * Called from the Godot menu button. Canvas clicks are not a trusted
	 * fullscreen gesture, so show a real HTML tap target instead.
	 */
	function promptFullscreen() {
		if (released) return false;
		if (fullscreenOk()) {
			mode = "";
			applyCssLandscape();
			return true;
		}
		if (isTouchish() || !document.fullscreenEnabled) {
			showFsModal();
			refreshChromeButtons();
			return false;
		}
		return enterFullscreen();
	}

	function onResume() {
		if (released) return;
		if (!isFullscreen()) cssFullscreen = false;
		mode = "";
		applyCssLandscape();
		refreshChromeButtons();
	}

	window.WaveDefenceMobile = {
		enterFullscreen: enterFullscreen,
		promptFullscreen: promptFullscreen,
		promptInstall: promptInstall,
		unlockAudio: unlockAudio,
		unlockAndStartGame: unlockAndStartGame,
		isAudioUnlocked: function () { return !!audioUnlocked; },
		exitPlayMode: exitPlayMode,
		applyCssLandscape: applyCssLandscape,
		isFullscreen: isFullscreen,
		refreshFsButton: refreshChromeButtons,
		refreshChromeButtons: refreshChromeButtons,
	};

	function boot() {
		applyCssLandscape();
		refreshChromeButtons();
		ensureStartGate();

		// Resume on every real DOM gesture. Do not notify Godot here (avoids a resume/unlock loop).
		document.addEventListener("pointerdown", resumeAudioContexts, true);
		document.addEventListener("touchstart", resumeAudioContexts, true);
		document.addEventListener("keydown", resumeAudioContexts, true);

		window.addEventListener("beforeinstallprompt", function (e) {
			e.preventDefault();
			deferredPrompt = e;
			refreshChromeButtons();
		});
		window.addEventListener("appinstalled", function () {
			deferredPrompt = null;
			refreshChromeButtons();
		});

		window.addEventListener("resize", function () {
			if (!released) applyCssLandscape();
		});
		window.addEventListener("orientationchange", function () {
			if (released) return;
			mode = "";
			setTimeout(applyCssLandscape, 80);
			setTimeout(function () {
				applyCssLandscape();
				refreshChromeButtons();
			}, 300);
		});
		document.addEventListener("fullscreenchange", function () {
			if (released) return;
			if (isFullscreen()) cssFullscreen = false;
			mode = "";
			applyCssLandscape();
			refreshChromeButtons();
		});
		document.addEventListener("webkitfullscreenchange", function () {
			if (released) return;
			if (isFullscreen()) cssFullscreen = false;
			mode = "";
			applyCssLandscape();
			refreshChromeButtons();
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
