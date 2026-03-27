# Operations

## Logging

Use the shared logger to tune output noise during integration.

```swift
Logger.setMaxLevel(.ERROR)
Logger.removeDestination(.Stdout)
```

Practical defaults:

- Keep `ERROR` or `WARNING` logs enabled in production.
- Use `INFO` or `DEBUG` during integration and incident analysis.

## Local Development Commands

```bash
swift build -v
swift run wired3 --working-directory ./run
```

Build the macOS wrapper app bundle:

```bash
./Scripts/build-wired-server-app.sh release
```

Output artifacts:

- `dist/Wired Server.app`
- `dist/Wired-Server.app.zip`
- `dist/wired3`
- `dist/wired3.zip`

## Docker

Single-architecture local build:

```bash
docker buildx build \
  --platform linux/amd64 \
  -f Dockerfile \
  --target runtime \
  --build-arg WIRED_MARKETING_VERSION=3.0 \
  --build-arg WIRED_BUILD_NUMBER=12 \
  --build-arg WIRED_GIT_COMMIT=$(git rev-parse --short HEAD) \
  --load \
  -t wired3:dev .
```

Quick check:

```bash
docker run --rm --platform linux/amd64 wired3:dev --version
```

Multi-architecture publish example:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f Dockerfile \
  --target runtime \
  --build-arg WIRED_MARKETING_VERSION=3.0 \
  --build-arg WIRED_BUILD_NUMBER=12 \
  --build-arg WIRED_GIT_COMMIT=$(git rev-parse --short HEAD) \
  --push \
  -t ghcr.io/nark/wired3:3.0-12 .
```

If you use the release automation, `Scripts/distribute.sh --prepare --phase docker` and `--upload --phase docker` generate and publish Docker tags automatically.
