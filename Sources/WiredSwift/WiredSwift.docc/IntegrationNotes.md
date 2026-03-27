# Integration Notes

## Compatibility

- Swift: 5.9+
- Platforms: macOS and Linux

## Choosing A Connection Style

- Use ``Connection`` for explicit request/reply control and custom loops.
- Use ``AsyncConnection`` in modern async/await codebases.
- Use ``BlockConnection`` when integrating with callback-based app architectures.

## Recommended Integration Boundaries

- Keep transport concerns in a dedicated networking layer around `WiredSwift`.
- Map protocol messages to your app domain models outside transport types.
- Centralize reconnect and retry strategy instead of scattering it across UI code.

## Documentation Strategy

- API-level documentation comes from `///` comments.
- Conceptual and operational guidance lives in this `.docc` catalog.

## CI Strategy

This repository validates DocC generation in pull requests and publishes static documentation from `master` to GitHub Pages.
