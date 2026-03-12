// Static Pastebin - Browser Storage with Optional Server Sync

const DB_NAME = 'kant-pastebin';
const STORE_NAME = 'pastes';

let db;
let serverUrl = localStorage.getItem('serverUrl') || 'https://solana.solfunmeme.com/pastebin';

// Initialize IndexedDB
function initDB() {
  const request = indexedDB.open(DB_NAME, 1);
  
  request.onerror = () => console.error('DB error');
  
  request.onsuccess = (e) => {
    db = e.target.result;
    loadPastes();
  };
  
  request.onupgradeneeded = (e) => {
    const db = e.target.result;
    const store = db.createObjectStore(STORE_NAME, { keyPath: 'id' });
    store.createIndex('timestamp', 'timestamp', { unique: false });
  };
}

// Save config
function saveConfig() {
  serverUrl = document.getElementById('serverUrl').value;
  localStorage.setItem('serverUrl', serverUrl);
  alert('✅ Config saved');
}

// Create paste
document.getElementById('pasteForm').onsubmit = async (e) => {
  e.preventDefault();
  
  const title = document.getElementById('title').value || 'untitled';
  const content = document.getElementById('content').value;
  const keywords = document.getElementById('keywords').value.split(',').map(s => s.trim()).filter(s => s);
  
  const paste = {
    id: Date.now().toString(),
    title,
    content,
    keywords,
    timestamp: new Date().toISOString(),
    synced: false
  };
  
  // Save locally
  const tx = db.transaction([STORE_NAME], 'readwrite');
  tx.objectStore(STORE_NAME).add(paste);
  
  tx.oncomplete = () => {
    document.getElementById('result').innerHTML = `✅ Saved locally: ${paste.id}`;
    loadPastes();
    
    // Try to sync to server
    if (serverUrl) {
      syncToServer(paste);
    }
  };
  
  // Clear form
  document.getElementById('content').value = '';
  document.getElementById('title').value = '';
  document.getElementById('keywords').value = '';
};

// Sync to server
async function syncToServer(paste) {
  try {
    const res = await fetch(`${serverUrl}/paste`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content: paste.content,
        title: paste.title,
        keywords: paste.keywords
      })
    });
    
    if (res.ok) {
      const data = await res.json();
      
      // Update local record
      const tx = db.transaction([STORE_NAME], 'readwrite');
      paste.synced = true;
      paste.serverId = data.id;
      paste.ipfsCid = data.ipfs_cid;
      paste.serverUrl = `${serverUrl}/paste/${data.id}`;
      tx.objectStore(STORE_NAME).put(paste);
      
      document.getElementById('result').innerHTML += `<br>☁️ Synced to server: ${data.id}`;
      if (data.ipfs_cid) {
        document.getElementById('result').innerHTML += `<br>📦 IPFS: ${data.ipfs_cid}`;
      }
      document.getElementById('result').innerHTML += `<br>🔗 URL: <a href="${paste.serverUrl}" target="_blank">${paste.serverUrl}</a>`;
      
      loadPastes();
    }
  } catch (err) {
    console.error('Sync failed:', err);
  }
}

// Load pastes
function loadPastes() {
  const tx = db.transaction([STORE_NAME], 'readonly');
  const store = tx.objectStore(STORE_NAME);
  const request = store.getAll();
  
  request.onsuccess = () => {
    const pastes = request.result.reverse();
    const html = pastes.map(p => {
      const url = p.serverId ? `${serverUrl}/paste/${p.serverId}` : '';
      return `
      <div class="paste-item ${p.synced ? 'synced' : ''}">
        <strong>${p.title}</strong>
        <span class="timestamp">${new Date(p.timestamp).toLocaleString()}</span>
        ${p.synced ? '☁️' : '💾'}
        ${p.ipfsCid ? `<br><code>ipfs cat ${p.ipfsCid}</code>` : ''}
        <br><button onclick="viewPaste('${p.id}')">View</button>
        <button onclick="deletePaste('${p.id}')">Delete</button>
        ${url ? `<button onclick="shareUrl('${url}')">🔗 Share URL</button>` : ''}
        ${url ? `<button onclick="showQR('${url}', '${p.title}')">📱 QR Code</button>` : ''}
      </div>
    `;
    }).join('');
    
    document.getElementById('pasteList').innerHTML = html || '<p>No pastes yet</p>';
  };
}

// Share URL
function shareUrl(url) {
  // Encode entire paste content in URL
  const tx = db.transaction([STORE_NAME], 'readonly');
  const pasteId = url.split('/').pop();
  
  tx.objectStore(STORE_NAME).openCursor().onsuccess = (e) => {
    const cursor = e.target.result;
    if (cursor) {
      const p = cursor.value;
      if (p.serverId === pasteId) {
        // Compress and encode entire paste in URL fragment
        const data = {
          title: p.title,
          content: p.content,
          keywords: p.keywords,
          timestamp: p.timestamp,
          ipfs_cid: p.ipfsCid
        };
        const encoded = btoa(encodeURIComponent(JSON.stringify(data)));
        const dataUrl = `${window.location.origin}${window.location.pathname}#paste=${encoded}`;
        
        if (navigator.share) {
          navigator.share({ 
            url: dataUrl, 
            title: p.title
          });
        } else {
          navigator.clipboard.writeText(dataUrl);
          document.getElementById('result').innerHTML = '✅ URL copied to clipboard';
        }
        return;
      }
      cursor.continue();
    }
  };
}

// Show QR Code
function showQR(url, title) {
  const qrDiv = document.createElement('div');
  qrDiv.style.cssText = 'position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);background:#fff;padding:20px;border:3px solid #0f0;z-index:1000';
  qrDiv.innerHTML = `
    <h3 style="color:#000">${title}</h3>
    <canvas id="qrcode"></canvas>
    <br><button onclick="copyQR()">📋 Copy</button>
    <button onclick="shareQR('${url}', '${title}')">🔗 Share</button>
    <button onclick="this.parentElement.remove()">Close</button>
  `;
  document.body.appendChild(qrDiv);
  
  // Generate QR code
  generateQR(url, document.getElementById('qrcode'));
}

function copyQR() {
  const canvas = document.getElementById('qrcode');
  canvas.toBlob(blob => {
    navigator.clipboard.write([new ClipboardItem({'image/png': blob})]);
    document.getElementById('result').innerHTML = '✅ QR code copied';
  });
}

function shareQR(url, title) {
  const canvas = document.getElementById('qrcode');
  canvas.toBlob(blob => {
    const file = new File([blob], 'qrcode.png', {type: 'image/png'});
    if (navigator.share) {
      navigator.share({
        title: title,
        files: [file]
      });
    }
  });
}

// Simple QR Code generator
function generateQR(text, canvas) {
  const size = 256;
  const qr = qrcode(0, 'M');
  qr.addData(text);
  qr.make();
  
  const ctx = canvas.getContext('2d');
  const cells = qr.getModuleCount();
  const cellSize = size / cells;
  
  canvas.width = size;
  canvas.height = size;
  
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, size, size);
  ctx.fillStyle = '#000';
  
  for (let row = 0; row < cells; row++) {
    for (let col = 0; col < cells; col++) {
      if (qr.isDark(row, col)) {
        ctx.fillRect(col * cellSize, row * cellSize, cellSize, cellSize);
      }
    }
  }
}

// View paste
function viewPaste(id) {
  const tx = db.transaction([STORE_NAME], 'readonly');
  const request = tx.objectStore(STORE_NAME).get(id);
  
  request.onsuccess = () => {
    const paste = request.result;
    document.getElementById('title').value = paste.title;
    document.getElementById('content').value = paste.content;
    document.getElementById('keywords').value = paste.keywords.join(', ');
    document.getElementById('result').innerHTML = `✅ Loaded: ${paste.title}`;
  };
}

// Delete paste
function deletePaste(id) {
  if (!confirm('Delete this paste?')) return;
  
  const tx = db.transaction([STORE_NAME], 'readwrite');
  tx.objectStore(STORE_NAME).delete(id);
  
  tx.oncomplete = () => loadPastes();
}

// Initialize
document.getElementById('serverUrl').value = serverUrl;
initDB();

// Load paste from URL fragment
window.addEventListener('load', () => {
  const hash = window.location.hash;
  if (hash.startsWith('#paste=')) {
    try {
      const encoded = hash.substring(7);
      const data = JSON.parse(decodeURIComponent(atob(encoded)));
      
      // Display loaded paste
      document.getElementById('title').value = data.title;
      document.getElementById('content').value = data.content;
      document.getElementById('keywords').value = data.keywords.join(', ');
      
      document.getElementById('result').innerHTML = `
        ✅ Loaded from URL<br>
        Title: ${data.title}<br>
        ${data.ipfs_cid ? `IPFS: ${data.ipfs_cid}<br>` : ''}
        Timestamp: ${new Date(data.timestamp).toLocaleString()}
      `;
    } catch (err) {
      console.error('Failed to load paste from URL:', err);
    }
  }
});
