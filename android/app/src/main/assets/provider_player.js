(() => {
  if (window.__providerPlayerEvents) {
    window.__providerPlayerEvents.refresh();
    return;
  }

  let hasPlayed = false;
  let backgroundPaused = false;
  let bootstrapStarted = false;
  let playPending = false;
  const deadline = Date.now() + 40000;
  let startupTimer;
  const noop = () => {};

  function cleanAds() {
    // These hooks belong to the dedicated 90minutes player, not its HLS loader.
    window.open = () => null;
    for (const name of ['triggerSmartLink', '_popOnce']) {
      if (typeof window[name] === 'function') window[name] = noop;
    }
    if ('_prerollEnabled' in window) window._prerollEnabled = false;
    if ('_prerollDone' in window) window._prerollDone = true;
    for (const element of document.querySelectorAll('#adContainer, #adOverlay, .ad-overlay, .ad-container')) {
      for (const media of element.querySelectorAll('video,audio')) media.pause();
      if (element.childNodes.length) element.replaceChildren();
    }
  }

  function installStyle() {
    if (!document.documentElement || document.getElementById('provider-player-clean-style')) return;
    const style = document.createElement('style');
    style.id = 'provider-player-clean-style';
    style.textContent = '#adContainer,#adOverlay,.ad-overlay,.ad-container{display:none!important;pointer-events:none!important}';
    document.documentElement.appendChild(style);
  }

  function startWhenReady() {
    cleanAds();
    installStyle();
    if (hasPlayed || backgroundPaused || Date.now() >= deadline) {
      clearInterval(startupTimer);
      return;
    }
    const media = document.getElementById('video') || document.querySelector('video');
    if (!media) return;
    // A listing tap is the user's play intent. Only unmute during initial startup.
    media.muted = false;
    media.defaultMuted = false;
    if (typeof window.forceUnmute === 'function') {
      try { window.forceUnmute(); } catch (_) {}
    }
    if (!bootstrapStarted && typeof window.startPlayback === 'function') {
      bootstrapStarted = true;
      try { window.startPlayback(); } catch (_) { bootstrapStarted = false; }
    }
    if (!hasPlayed && media.paused && media.readyState >= 1 && !playPending) {
      playPending = true;
      try {
        Promise.resolve(media.play()).catch(noop).finally(() => { playPending = false; });
      } catch (_) { playPending = false; }
    }
  }

  window.__providerPlayerEvents = {refresh: startWhenReady};
  document.addEventListener('playing', event => {
    // An ad must never satisfy the main video's startup event.
    if (!event.target.matches('video') || event.target.closest('#adContainer,#adOverlay,.ad-overlay,.ad-container')) return;
    hasPlayed = true;
    clearInterval(startupTimer);
    cleanAds();
    console.info('__PROVIDER_PLAYER_PLAYING__');
  }, true);
  document.addEventListener('loadedmetadata', startWhenReady, true);
  document.addEventListener('canplay', startWhenReady, true);
  document.addEventListener('DOMContentLoaded', startWhenReady, {once: true});
  // Disable ad click hooks before the provider's normal player controls run.
  document.addEventListener('click', cleanAds, true);
  window.addEventListener('message', event => {
    if (!event.data || event.data.providerPlayerPause !== true) return;
    backgroundPaused = true;
    clearInterval(startupTimer);
    document.querySelectorAll('video,audio').forEach(media => media.pause());
    for (let i = 0; i < frames.length; i++) {
      try { frames[i].postMessage({providerPlayerPause:true}, '*'); } catch (_) {}
    }
  });
  const observer = new MutationObserver(() => { installStyle(); cleanAds(); });
  observer.observe(document, {childList: true, subtree: true});
  startupTimer = setInterval(startWhenReady, 750);
  startWhenReady();
})();
