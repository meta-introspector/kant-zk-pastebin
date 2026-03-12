// FRACTRAN A11y Enhancement
// Progressive enhancement - works without JS, better with JS

(function() {
  // Add keyboard support to all buttons
  document.querySelectorAll('button, .reply-btn').forEach(btn => {
    if (!btn.hasAttribute('aria-label')) {
      btn.setAttribute('aria-label', btn.textContent.trim());
    }
    if (!btn.hasAttribute('tabindex')) {
      btn.setAttribute('tabindex', '0');
    }
    btn.setAttribute('role', 'button');
    
    // Keyboard handler
    btn.onkeydown = e => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        btn.click();
      }
    };
  });

  // Live region for screen reader announcements
  const live = document.createElement('div');
  live.id = 'a11y-live';
  live.setAttribute('aria-live', 'polite');
  live.style.cssText = 'position:absolute;left:-10000px;width:1px;height:1px';
  document.body.appendChild(live);
  
  // FRACTRAN state encoding (optional)
  window.FRACTRAN = {
    encode: (page, action, filter, sort) => 
      2n ** BigInt(page) * 3n ** BigInt(action) * 5n ** BigInt(filter) * 7n ** BigInt(sort)
  };
})();
