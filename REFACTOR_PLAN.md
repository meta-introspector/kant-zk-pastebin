# Refactoring Plan: Separate API from Display

## Current Problem
- HTML templates mixed with API logic in main.rs
- Hard to maintain, test, and extend
- Can't easily add new frontends (CLI, TUI, mobile)

## Target Architecture

```
src/
├── main.rs           # Server setup, routes
├── api.rs            # JSON API endpoints
├── model.rs          # Data structures (Paste, etc)
├── storage.rs        # File I/O, IPFS
├── views/            # HTML templates
│   ├── home.html
│   ├── paste.html
│   └── browse.html
└── static/
    ├── a11y.js
    └── style.css
```

## API Endpoints (JSON)

```
POST   /api/paste          → Create paste, return {id, url}
GET    /api/paste/{id}     → Get paste JSON
GET    /api/browse?q=...   → List pastes JSON
DELETE /api/paste/{id}     → Delete paste
```

## View Endpoints (HTML)

```
GET /              → Home page (create form)
GET /paste/{id}    → View paste (HTML)
GET /raw/{id}      → Raw text
GET /browse        → Browse pastes (HTML)
```

## Benefits

1. **API-first**: Can build CLI, mobile app, etc
2. **Testable**: Test API separately from HTML
3. **Simple**: Each file has one job
4. **Progressive**: HTML works without JS, JS enhances

## Implementation Steps

1. Extract model.rs (Paste struct)
2. Extract api.rs (JSON endpoints)
3. Move HTML to templates
4. Update main.rs to wire it together
5. Add /raw/{id} endpoint
6. Fix reply_to display
