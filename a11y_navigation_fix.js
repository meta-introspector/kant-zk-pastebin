// FRACTRAN A11y Navigation Fix for kant-pastebin
// Add to main.rs HTML generation

const NAVIGATION_FIX = r#"
<script>
// FRACTRAN State Encoding for A11y
const FRACTRAN = {
  // State = 2^page × 3^action × 5^filter × 7^sort
  encode: (page, action, filter, sort) => {
    return 2n**BigInt(page) * 3n**BigInt(action) * 5n**BigInt(filter) * 7n**BigInt(sort);
  },
  
  decode: (state) => {
    let n = BigInt(state);
    const extract = (prime) => {
      let power = 0;
      while (n % prime === 0n) { n /= prime; power++; }
      return power;
    };
    return {
      page: extract(2n),
      action: extract(3n),
      filter: extract(5n),
      sort: extract(7n)
    };
  },
  
  toText: (state) => {
    const s = FRACTRAN.decode(state);
    const pages = ['home', 'browse', 'paste', 'search'];
    const actions = ['view', 'edit', 'delete', 'share'];
    const filters = ['all', 'deletable', 'large', 'duplicates'];
    const sorts = ['newest', 'oldest', 'title', 'size'];
    return `Page: ${pages[s.page] || 'unknown'}, Action: ${actions[s.action] || 'none'}, Filter: ${filters[s.filter] || 'all'}, Sort: ${sorts[s.sort] || 'newest'}`;
  }
};

// Update all buttons with ARIA and FRACTRAN state
document.addEventListener('DOMContentLoaded', () => {
  // Fix filter buttons
  document.querySelectorAll('.filter-btn').forEach((btn, idx) => {
    const filter = btn.dataset.filter || 'all';
    const state = FRACTRAN.encode(1, 0, idx, 0);
    
    btn.setAttribute('role', 'button');
    btn.setAttribute('aria-label', `Filter: ${filter}`);
    btn.setAttribute('data-fractran-state', state);
    btn.setAttribute('tabindex', '0');
    
    // Keyboard support
    btn.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        btn.click();
      }
    });
  });
  
  // Fix action buttons
  document.querySelectorAll('.btn').forEach((btn) => {
    if (!btn.hasAttribute('aria-label')) {
      const text = btn.textContent.trim();
      btn.setAttribute('aria-label', text);
    }
    btn.setAttribute('tabindex', '0');
  });
  
  // Add live region for announcements
  if (!document.getElementById('a11y-live')) {
    const live = document.createElement('div');
    live.id = 'a11y-live';
    live.setAttribute('aria-live', 'polite');
    live.setAttribute('aria-atomic', 'true');
    live.style.position = 'absolute';
    live.style.left = '-10000px';
    live.style.width = '1px';
    live.style.height = '1px';
    live.style.overflow = 'hidden';
    document.body.appendChild(live);
  }
  
  // Announce state changes
  const announce = (message) => {
    const live = document.getElementById('a11y-live');
    if (live) {
      live.textContent = message;
    }
  };
  
  // Track navigation state
  let currentState = FRACTRAN.encode(0, 0, 0, 0);
  
  // Update state on filter change
  document.querySelectorAll('.filter-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const state = btn.dataset.fractranState;
      currentState = state;
      announce(`Filter changed: ${btn.textContent}`);
      
      // Update active state
      document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
    });
  });
  
  // Keyboard navigation for paste list
  document.querySelectorAll('.paste').forEach((paste, idx) => {
    paste.setAttribute('tabindex', '0');
    paste.setAttribute('role', 'article');
    
    const title = paste.querySelector('.title')?.textContent || 'Untitled';
    paste.setAttribute('aria-label', `Paste: ${title}`);
    
    paste.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        paste.click();
      } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        const next = paste.nextElementSibling;
        if (next) next.focus();
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        const prev = paste.previousElementSibling;
        if (prev) prev.focus();
      }
    });
  });
  
  // Skip to content link
  if (!document.getElementById('skip-to-content')) {
    const skip = document.createElement('a');
    skip.id = 'skip-to-content';
    skip.href = '#main-content';
    skip.textContent = 'Skip to main content';
    skip.style.position = 'absolute';
    skip.style.left = '-10000px';
    skip.style.width = '1px';
    skip.style.height = '1px';
    skip.style.overflow = 'hidden';
    skip.addEventListener('focus', () => {
      skip.style.position = 'static';
      skip.style.width = 'auto';
      skip.style.height = 'auto';
    });
    skip.addEventListener('blur', () => {
      skip.style.position = 'absolute';
      skip.style.left = '-10000px';
      skip.style.width = '1px';
      skip.style.height = '1px';
    });
    document.body.insertBefore(skip, document.body.firstChild);
  }
  
  // Add main landmark
  const container = document.querySelector('.container');
  if (container && !container.hasAttribute('role')) {
    container.setAttribute('role', 'main');
    container.id = 'main-content';
  }
});
</script>
"#;
