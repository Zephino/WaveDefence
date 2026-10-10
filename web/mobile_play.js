/* Mobile/web helpers: CSS landscape, fullscreen (real DOM gesture), PWA install, audio unlock. */
(function () {
	var mode = ""; // "" | "portrait-css" | "landscape-fill"
	var enterInFlight = false;
	var released = false;
	var fsBtn = null;
	var fsModal = null;
	var installModal = null;
	var deferredPrompt = null;
	var cssFullscreen = false;
	var audioUnlocked = false;
	var TRACKS = {
		menu: "music/web_loop_01.wav",
		calm: "music/web_loop_02.wav",
		intense: "music/web_loop_03.wav",
		siege_calm: "music/web_loop_04.wav",
		siege_intense: "music/web_loop_05.wav",
	};
	var musicBuffers = {};
	var musicLoading = {};
	var musicNodes = {};
	var musicMasterGain = null;
	var musicAnalyser = null;
	var musicVolume = 0.56;
	var sfxVolume = 0.64;
	var musicContext = "menu";
	var mixCalm = 1;
	var mixIntense = 0;
	var fallbackOsc = null;
	var lastMusicError = "";

	function scriptVersion() {
		var el = document.querySelector('script[src*="mobile_play.js"]');
		if (!el || !el.src) return "";
		var m = el.src.match(/[?&]v=([^&]+)/);
		return m ? m[1] : "";
	}

	function trackUrl(name) {
		var path = TRACKS[name];
		if (!path) return "";
		var ver = scriptVersion();
		return ver ? (path + "?v=" + encodeURIComponent(ver)) : path;
	}

	function resumeOne(ctx) {
		if (!ctx || ctx.state !== "suspended") return;
		try { ctx.resume(); } catch (e) {}
	}

	function ensureKickContext() {
		try {
			var Ctx = window.AudioContext || window.webkitAudioContext;
			if (!Ctx) return null;
			if (!window.__wdAudioKick) {
				window.__wdAudioKick = new Ctx();
			}
			resumeOne(window.__wdAudioKick);
			return window.__wdAudioKick;
		} catch (e) {
			return null;
		}
	}

	function ensureMusicGraph() {
		var ctx = ensureKickContext();
		if (!ctx) return null;
		if (!musicMasterGain) {
			musicMasterGain = ctx.createGain();
			musicMasterGain.gain.value = musicVolume;
			musicAnalyser = ctx.createAnalyser();
			musicAnalyser.fftSize = 256;
			musicMasterGain.connect(musicAnalyser);
			musicAnalyser.connect(ctx.destination);
		}
		return ctx;
	}

	function resumeAudioContexts() {
		resumeOne(window.__wdAudioKick);
		try {
			if (window.godotAudioContext) resumeOne(window.godotAudioContext);
		} catch (e) {}
	}

	function unlockAudio() {
		ensureKickContext();
		resumeAudioContexts();
	}

	function playUiBlip() {
		var ctx = ensureKickContext();
		if (!ctx || sfxVolume <= 0.001) return;
		try {
			var o = ctx.createOscillator();
			var g = ctx.createGain();
			o.type = "square";
			o.frequency.value = 784;
			g.gain.setValueAtTime(0.07 * sfxVolume, ctx.currentTime);
			g.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.07);
			o.connect(g);
			g.connect(ctx.destination);
			o.start();
			o.stop(ctx.currentTime + 0.08);
		} catch (e) {}
	}

	function startFallbackPad() {
		if (fallbackOsc) return;
		var ctx = ensureMusicGraph();
		if (!ctx || !musicMasterGain) return;
		try {
			var o = ctx.createOscillator();
			var g = ctx.createGain();
			o.type = "triangle";
			o.frequency.value = 196;
			g.gain.value = 0.12;
			o.connect(g);
			g.connect(musicMasterGain);
			o.start();
			fallbackOsc = { osc: o, gain: g };
		} catch (e) {}
	}

	function stopFallbackPad() {
		if (!fallbackOsc) return;
		try { fallbackOsc.osc.stop(); } catch (e) {}
		try { fallbackOsc.osc.disconnect(); fallbackOsc.gain.disconnect(); } catch (e) {}
		fallbackOsc = null;
	}

	function stopTrack(name) {
		var node = musicNodes[name];
		if (!node) return;
		try { node.src.stop(); } catch (e) {}
		try { node.src.disconnect(); node.gain.disconnect(); } catch (e) {}
		delete musicNodes[name];
	}

	function startTrack(name, level) {
		var ctx = ensureMusicGraph();
		var buf = musicBuffers[name];
		if (!ctx || !buf || !musicMasterGain) return false;
		stopTrack(name);
		try {
			var src = ctx.createBufferSource();
			var g = ctx.createGain();
			src.buffer = buf;
			src.loop = true;
			g.gain.value = Math.max(0, Math.min(1, level));
			src.connect(g);
			g.connect(musicMasterGain);
			src.start(0);
			musicNodes[name] = { src: src, gain: g, startedAt: ctx.currentTime };
			stopFallbackPad();
			return true;
		} catch (e) {
			lastMusicError = String(e);
			return false;
		}
	}

	function loadTrack(name) {
		if (musicBuffers[name] || musicLoading[name]) return musicLoading[name] || Promise.resolve(musicBuffers[name]);
		var url = trackUrl(name);
		if (!url) return Promise.resolve(null);
		var ctx = ensureMusicGraph();
		if (!ctx) return Promise.resolve(null);
		musicLoading[name] = fetch(url)
			.then(function (r) {
				if (!r.ok) throw new Error("HTTP " + r.status + " for " + url);
				return r.arrayBuffer();
			})
			.then(function (ab) {
				return ctx.decodeAudioData(ab.slice(0));
			})
			.then(function (buf) {
				musicBuffers[name] = buf;
				delete musicLoading[name];
				applyMusicMix();
				return buf;
			})
			.catch(function (e) {
				lastMusicError = String(e && e.message ? e.message : e);
				delete musicLoading[name];
				if (name === "menu" || name === "calm" || name === "siege_calm") {
					startFallbackPad();
				}
				return null;
			});
		return musicLoading[name];
	}

	function contextPair(name) {
		if (name === "standard") return ["calm", "intense"];
		if (name === "siege") return ["siege_calm", "siege_intense"];
		return ["menu", null];
	}

	function applyMusicMix() {
		var ctx = ensureMusicGraph();
		if (!ctx || !musicMasterGain) return;
		musicMasterGain.gain.value = Math.max(0, Math.min(1, musicVolume));
		var pair = contextPair(musicContext);
		var wanted = {};
		wanted[pair[0]] = pair[1] ? mixCalm : 1;
		if (pair[1]) wanted[pair[1]] = mixIntense;
		Object.keys(musicNodes).forEach(function (name) {
			if (!wanted.hasOwnProperty(name)) stopTrack(name);
		});
		Object.keys(wanted).forEach(function (name) {
			var level = wanted[name];
			if (level <= 0.001) {
				stopTrack(name);
				return;
			}
			if (!musicBuffers[name]) {
				loadTrack(name);
				return;
			}
			if (!musicNodes[name]) {
				startTrack(name, level);
			} else {
				musicNodes[name].gain.gain.value = Math.max(0, Math.min(1, level));
			}
		});
	}

	function musicSetContext(name) {
		if (name === "menu" || name === "standard" || name === "siege") {
			musicContext = name;
		} else {
			musicContext = "menu";
		}
		var pair = contextPair(musicContext);
		loadTrack(pair[0]);
		if (pair[1]) loadTrack(pair[1]);
		applyMusicMix();
	}

	function musicSetMix(calm, intense) {
		mixCalm = Math.max(0, Math.min(1, Number(calm) || 0));
		mixIntense = Math.max(0, Math.min(1, Number(intense) || 0));
		applyMusicMix();
	}

	function musicSetVolume(v) {
		musicVolume = Math.max(0, Math.min(1, Number(v) || 0));
		applyMusicMix();
	}

	function sfxSetVolume(v) {
		sfxVolume = Math.max(0, Math.min(1, Number(v) || 0));
	}

	function analyserLevel() {
		if (!musicAnalyser) return 0;
		var data = new Uint8Array(musicAnalyser.frequencyBinCount);
		musicAnalyser.getByteTimeDomainData(data);
		var sum = 0;
		for (var i = 0; i < data.length; i++) {
			var v = (data[i] - 128) / 128;
			sum += v * v;
		}
		return Math.sqrt(sum / data.length);
	}

	function musicArmAndPlayMenu() {
		Object.keys(TRACKS).forEach(function (name) {
			loadTrack(name);
		});
		musicSetContext("menu");
	}

	function unlockAndStartGame() {
		if (audioUnlocked) return;
		unlockAudio();
		musicArmAndPlayMenu();
		audioUnlocked = true;
		window.__wdAudioUnlocked = true;
		try {
			if (typeof window.__wdGodotUnlock === "function") {
				window.__wdGodotUnlock();
			}
		} catch (e) {}
	}

	function onFirstUserGesture() {
		if (audioUnlocked) return;
		unlockAndStartGame();
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
		musicSetContext: musicSetContext,
		musicSetMix: musicSetMix,
		musicSetVolume: musicSetVolume,
		sfxSetVolume: sfxSetVolume,
		musicStatus: function () {
			var playing = {};
			Object.keys(musicNodes).forEach(function (name) {
				var n = musicNodes[name];
				playing[name] = {
					gain: n.gain.gain.value,
					age: window.__wdAudioKick ? (window.__wdAudioKick.currentTime - n.startedAt) : 0,
				};
			});
			return {
				unlocked: !!audioUnlocked,
				context: musicContext,
				master: musicVolume,
				sfx: sfxVolume,
				mix: [mixCalm, mixIntense],
				kick: window.__wdAudioKick ? window.__wdAudioKick.state : "none",
				buffers: Object.keys(musicBuffers),
				loading: Object.keys(musicLoading),
				playing: playing,
				fallback: !!fallbackOsc,
				level: analyserLevel(),
				error: lastMusicError,
			};
		},
		playUiBlip: playUiBlip,
		exitPlayMode: exitPlayMode,
		applyCssLandscape: applyCssLandscape,
		isFullscreen: isFullscreen,
		refreshFsButton: refreshChromeButtons,
		refreshChromeButtons: refreshChromeButtons,
	};

	function boot() {
		applyCssLandscape();
		refreshChromeButtons();
		// Warm-decode loops while the AudioContext is still suspended.
		try {
			ensureMusicGraph();
			Object.keys(TRACKS).forEach(function (name) { loadTrack(name); });
		} catch (e) {}

		// Browsers block audible output until a real gesture. First click/tap/key
		// starts music in that same gesture — no separate "Tap to start" screen.
		document.addEventListener("pointerdown", onFirstUserGesture, true);
		document.addEventListener("touchstart", onFirstUserGesture, true);
		document.addEventListener("keydown", onFirstUserGesture, true);

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
