// Runs in the web page before the game starts (injected into the Web export
// preset's html/head_include by tools/web/update_head.py).
//
// 1. iPhone audio. iOS mutes web audio when the silent switch is on, and only
//    allows sound after a tap. On the first tap we ask iOS to treat the game's
//    sound as media playback (navigator.audioSession, iOS 17+), play a tiny
//    silent clip (the same trick for older iOS), and resume any paused
//    AudioContext.
// 2. Audio test panel: open the game with ?debug=audio to see the audio state
//    live and play a test beep that doesn't go through the game.
(function () {
  var ctxs = [];
  var starts = 0;
  var unlocks = 0;
  var lastErr = '';
  var Orig = window.AudioContext || window.webkitAudioContext;
  if (Orig) {
    var Wrapped = function (a, b) { var c = new Orig(a, b); ctxs.push(c); return c; };
    Wrapped.prototype = Orig.prototype;
    window.AudioContext = Wrapped;
    window.webkitAudioContext = Wrapped;
  }
  if (window.AudioBufferSourceNode) {
    var start = AudioBufferSourceNode.prototype.start;
    AudioBufferSourceNode.prototype.start = function () { starts++; return start.apply(this, arguments); };
  }
  // Stream mode: the game mixes everything itself and plays it through one
  // AudioWorklet (or, on older browsers, a ScriptProcessor). Count those.
  var mixers = 0;
  if (window.AudioWorkletNode) {
    var AW = window.AudioWorkletNode;
    var WrappedAW = function (c, n, o) { mixers++; return new AW(c, n, o); };
    WrappedAW.prototype = AW.prototype;
    window.AudioWorkletNode = WrappedAW;
  }
  if (Orig && Orig.prototype.createScriptProcessor) {
    var csp = Orig.prototype.createScriptProcessor;
    Orig.prototype.createScriptProcessor = function () { mixers++; return csp.apply(this, arguments); };
  }
  var silentPlayed = false;
  function unlock() {
    unlocks++;
    try { if (navigator.audioSession) { navigator.audioSession.type = 'playback'; } } catch (e) { lastErr = String(e); }
    for (var i = 0; i < ctxs.length; i++) {
      try { if (ctxs[i].state !== 'running') { ctxs[i].resume(); } } catch (e) { lastErr = String(e); }
    }
    if (!silentPlayed) {
      silentPlayed = true;
      try {
        var a = new Audio('SILENT_WAV');
        a.setAttribute('playsinline', '');
        a.play().catch(function (e) { lastErr = String(e); });
      } catch (e) { lastErr = String(e); }
    }
  }
  ['touchend', 'pointerup', 'mousedown', 'keydown'].forEach(function (t) {
    window.addEventListener(t, unlock, true);
  });

  if (location.search.indexOf('debug=audio') < 0) { return; }
  window.addEventListener('load', function () {
    var box = document.createElement('div');
    box.style.cssText = 'position:fixed;left:6px;top:6px;z-index:9999;background:rgba(0,0,0,0.8);color:#fff;' +
      'font:13px/1.35 monospace;padding:8px;border-radius:8px;max-width:92vw;white-space:pre-wrap';
    var text = document.createElement('div');
    var beep = document.createElement('button');
    beep.textContent = 'TEST BEEP';
    beep.style.cssText = 'margin-top:6px;font:15px monospace;padding:6px 12px';
    beep.addEventListener('click', function () {
      try {
        var c = new Orig();
        var o = c.createOscillator();
        var g = c.createGain();
        g.gain.value = 0.3;
        o.frequency.value = 660;
        o.connect(g); g.connect(c.destination);
        c.resume();
        o.start(); o.stop(c.currentTime + 0.4);
        lastErr = 'beep ctx: ' + c.state;
      } catch (e) { lastErr = 'beep: ' + e; }
    });
    box.appendChild(text);
    box.appendChild(beep);
    document.body.appendChild(box);
    setInterval(function () {
      var states = ctxs.map(function (c) { return c.state + ' ' + c.sampleRate + 'Hz'; }).join(', ');
      text.textContent = 'contexts: ' + (states || 'none') + '\nmixers: ' + mixers + '   buffer starts: ' + starts +
        '\nunlocks: ' + unlocks + '\naudioSession: ' + (navigator.audioSession ? navigator.audioSession.type : 'n/a') +
        '\nerror: ' + (lastErr || '-') + '\n' + navigator.userAgent;
    }, 500);
  });
})();
