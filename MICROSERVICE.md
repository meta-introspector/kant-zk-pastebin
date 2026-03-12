# kant-pastebin Microservice

Clean actix-web microservice for pastebin functionality.

## Architecture

```
src/
├── main.rs       # Server setup, routes
├── handlers.rs   # Request handlers
├── models.rs     # Data structures
├── storage.rs    # File/IPFS operations
└── templates/    # HTML templates
```

## Routes

```
GET  /                    → Create paste form
POST /paste               → Create new paste (JSON)
GET  /paste/{id}          → View paste (HTML)
GET  /raw/{id}            → Raw text
GET  /browse              → List pastes
```

## Features

- JSON API for all operations
- HTML views for browser
- Static file serving
- CORS support
- Error handling
- Logging

## Stack

- actix-web 4.x
- serde for JSON
- tera for templates
- env_logger for logging
