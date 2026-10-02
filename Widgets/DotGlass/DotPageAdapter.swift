import Foundation

/// The adapter reads the rendered conversation and uses its existing composer.
/// It never reads cookies, bearer tokens, React internals, or private endpoints.
enum DotPageAdapter {
    static let source = #"""
    (() => {
      if (location.origin !== 'https://chatgpt.com' || window.__dotGlass) return;
      let pending = null, last = '', timer = null, nextID = 0;
      const rowIDs = new WeakMap();
      const visible = el => el && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
      const room = () => /^\/dots\/[A-Za-z0-9-]+\/?$/.test(location.pathname) ? location.origin + location.pathname.replace(/\/$/, '') : '';
      const root = () => document.querySelector('.messaging-root') || document.querySelector('main');
      const editor = () => root()?.querySelector('.composer-wrap [contenteditable="true"], .composer-wrap textarea, [contenteditable="true"][role="textbox"], #prompt-textarea, textarea[placeholder]');
      const readRows = () => Array.from(root()?.querySelectorAll('.message-row') || []).slice(-100).map((row) => {
        let id = row.getAttribute('data-message-id') || row.id;
        if (!id) { if (!rowIDs.has(row)) rowIDs.set(row, 'row-' + (++nextID)); id = rowIDs.get(row); }
        const parts = row.querySelectorAll('[data-orbit-message-text-part]');
        let text = parts.length ? Array.from(parts).map(p => p.innerText).join('\n\n') :
          Array.from(row.querySelectorAll('.message-text')).map(p => p.innerText).join('\n\n');
        if (!text) {
          const bubble = row.querySelector('.message-bubble');
          if (bubble) {
            const clone = bubble.cloneNode(true);
            clone.querySelectorAll('button, .message-inline-actions, .message-meta, svg, [aria-hidden="true"]').forEach(n => n.remove());
            text = clone.textContent || '';
          }
        }
        const hasAttachment = !!row.querySelector('img, video, [data-orbit-message-writing-block], .attachment-card, [data-mcp-confirmation-chip]');
        return { id, text: (text || '').trim().slice(0, 32000), isMine: row.classList.contains('self'), hasAttachment };
      }).filter(m => m.text || m.hasAttachment);
      const normalize = s => s.replace(/\s+/g, ' ').trim();
      function snapshot() {
        const conversation = room(), messages = conversation ? readRows() : [];
        let acknowledgement = null;
        if (pending && pending.room === conversation) {
          if (messages.some(m => m.isMine && !pending.before.has(m.id) && normalize(m.text) === normalize(pending.text))) {
            acknowledgement = pending.token; pending = null;
          }
        }
        const nameElement = document.querySelector('[aria-label^="Open "][aria-label$="’s profile"]');
        const name = nameElement?.getAttribute('aria-label')?.replace(/^Open /, '').replace(/’s profile$/, '') || (document.title && document.title !== 'ChatGPT' ? document.title.replace(/\s*[-–|]\s*ChatGPT$/, '').trim() : 'Your dot');
        const signedIn = !!document.querySelector('button[aria-label="Open profile menu"], [data-testid="profile-button"], [data-testid="accounts-profile-button"]');
        return { conversation, name, messages, acknowledgement, signedIn,
          ready: navigator.onLine && !!conversation && visible(editor()),
          typing: !!Array.from(root()?.querySelectorAll('.typing-indicator, .typing-bubble') || []).find(n => visible(n) && n.getAttribute('data-visible') === 'true'),
          mediaPlaying: Array.from(document.querySelectorAll('audio,video')).some(m => !m.paused && !m.ended && !m.muted && m.volume > 0 && m.readyState >= 2)
        };
      }
      function publish() {
        try {
          const value = snapshot(), encoded = JSON.stringify(value);
          if (encoded !== last) { last = encoded; window.webkit?.messageHandlers.dotGlass.postMessage(value); }
        } catch (_) { /* No page text or account details are logged. */ }
      }
      function schedule() { if (timer) return; timer = setTimeout(() => { timer = null; publish(); }, 180); }
      const observer = new MutationObserver(schedule);
      observer.observe(document.documentElement, {subtree:true, childList:true, characterData:true, attributes:true, attributeFilter:['disabled','data-visible','aria-busy']});

      const send = async (text, token, expectedRoom) => {
        const conversation = room(), input = editor();
        if (!conversation || conversation !== expectedRoom || !visible(input)) return 'not-ready';
        if (pending) return 'pending';
        if (typeof text !== 'string' || !text.trim() || text.length > 12000) return 'invalid';
        if ((input.value || input.innerText || '').trim()) return 'existing-draft';
        input.focus();
        if (input instanceof HTMLTextAreaElement) {
          Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set.call(input, text);
          input.dispatchEvent(new InputEvent('input', {bubbles:true, inputType:'insertText', data:text}));
        } else {
          const selection = getSelection(), range = document.createRange(); range.selectNodeContents(input);
          selection.removeAllRanges(); selection.addRange(range);
          if (!document.execCommand('insertText', false, text)) return 'editor-unavailable';
        }
        for (let attempt=0; attempt<20; attempt++) {
          if (room() !== expectedRoom) return 'room-changed';
          const scope = input.closest('.composer-wrap') || root();
          const button = scope?.querySelector('button[aria-label="Send"], button[aria-label="Send message"], button[data-testid="send-button"]');
          if (visible(button) && !button.disabled && button.getAttribute('aria-disabled') !== 'true') {
            pending = {room: conversation, text, token, before:new Set(readRows().map(m => m.id))};
            button.click(); schedule(); return 'submitted';
          }
          await new Promise(resolve => setTimeout(resolve, 100));
        }
        return 'send-unavailable';
      };
      let callRequested = false;
      const startCall = expectedRoom => {
        if (!room() || room() !== expectedRoom) return 'not-ready';
        if (callRequested) return 'pending';
        // ChatGPT varies the accessible name with viewport and call UI versions.
        // Match explicit call actions only, outside messages and the composer.
        const labels = new Set(['start call', 'start a call', 'call', 'voice call', 'start voice call', 'start a voice call', 'call your dot']);
        const dotName = snapshot().name.toLowerCase();
        if (dotName && dotName !== 'your dot') labels.add('call ' + dotName);
        const button = Array.from(document.querySelectorAll('button, [role="button"]')).find(el => {
          if (!visible(el) || el.closest('.message-row, .composer-wrap') || el.disabled || el.getAttribute('aria-disabled') === 'true') return false;
          return [el.getAttribute('aria-label'), el.getAttribute('title'), el.innerText]
            .some(label => label && labels.has(normalize(label).toLowerCase()));
        });
        if (!button) return 'call-unavailable';
        callRequested = true;
        button.click();
        return 'started';
      };
      const setMuted = (shouldMute, expectedRoom) => {
        if (!room() || room() !== expectedRoom) return 'not-ready';
        const muteLabels = ['mute', 'mute microphone', 'mute mic', 'turn microphone off'];
        const unmuteLabels = ['unmute', 'unmute microphone', 'unmute mic', 'turn microphone on'];
        const find = labels => Array.from(document.querySelectorAll('button, [role="button"]')).find(el =>
          visible(el) && !el.closest('.message-row, .composer-wrap') && !el.disabled && el.getAttribute('aria-disabled') !== 'true' &&
          [el.getAttribute('aria-label'), el.getAttribute('title'), el.innerText]
            .some(label => label && labels.includes(normalize(label).toLowerCase())));
        const button = find(shouldMute ? muteLabels : unmuteLabels);
        if (!button) return find(shouldMute ? unmuteLabels : muteLabels) ? 'unchanged' : 'unavailable';
        button.click(); return 'changed';
      };
      let signInClicked = false;
      const openSignIn = () => {
        if (signInClicked) return true;
        const button = Array.from(document.querySelectorAll('button, a')).find(el => visible(el) && /^(log in|sign in)$/i.test((el.innerText || el.getAttribute('aria-label') || '').trim()));
        if (!button) return false;
        signInClicked = true; button.click(); return true;
      };
      window.__dotGlass = {send, startCall, setMuted, openSignIn, resetCall: () => { callRequested = false; }, refresh:publish};
      window.addEventListener('pagehide', () => {observer.disconnect();  clearTimeout(timer);});
      window.addEventListener('online', schedule); window.addEventListener('offline', schedule);
      document.addEventListener('play', schedule, true); document.addEventListener('pause', schedule, true);
      publish();
    })();
    """#
}
