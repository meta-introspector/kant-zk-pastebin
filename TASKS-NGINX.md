# Nginx Tasks — solana.solfunmeme.com

## User Tasks

### 1. Browse Error Documents
```
Open https://solana.solfunmeme.com/nginx-docs/errors/
```
Review all non-2xx responses captured as research documents.

### 2. Monitor Live Errors
```bash
sudo tail -f /var/log/nginx/error-docs/error.log
```

### 3. Check SSL Status
```bash
echo | openssl s_client -connect solana.solfunmeme.com:443 -servername solana.solfunmeme.com 2>&1 | grep -E "subject=|issuer="
# Should show issuer=C=US, O=Let's Encrypt, CN=YR1
```

### 4. View Research Access Logs
```bash
sudo tail -100 /var/log/nginx/research.access.log
```

### 5. Upload Large Files
No size limits. Upload directly to pastebin at `https://solana.solfunmeme.com/pastebin/`

## Dev Tasks

### 1. Deploy Config Changes
```bash
cd /mnt/data1/kant/pastebin
git add -A && git commit -m "description"
bash deploy.sh switch
sudo systemctl restart nginx.service
```

### 2. Diagnose SSL Issues
```bash
# Check which cert is active
sudo systemctl start ssl-selfsigned.service
readlink -f /etc/letsencrypt/live/solana.solfunmeme.com/fullchain.pem

# Force re-symlink to latest LE cert
sudo systemctl start certbot-renew.service
```

### 3. Analyze Error Patterns
```bash
# Top error URIs
sudo grep "^URI:" /var/log/nginx/error-docs/error.log | sort | uniq -c | sort -rn | head -20

# Top error status codes
sudo grep "^Status:" /var/log/nginx/error-docs/error.log | sort | uniq -c | sort -rn

# Slow requests (> 5 seconds)
sudo awk -F' ' '$8 > 5 {print}' /var/log/nginx/research.access.log | sort -k8 -rn | head -10
```

### 4. Regenerate Self-Signed Fallback
```bash
sudo rm -f /mnt/data1/kant/pastebin/ssl/solana.solfunmeme.com.{crt,key}
sudo systemctl start ssl-selfsigned.service
```

### 5. Manual Config Verification
```bash
# Find the active nginx config path
ps aux | grep "nginx: master" | grep -Po '/nix/store/[^"]+-nginx\.conf'

# Test syntax
sudo nginx -t -c /path/to/nginx.conf
```
