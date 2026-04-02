# cpython

A self-maintained Python Docker image that builds [CPython](https://github.com/python/cpython) from source on top of a
Debian-based (Debian or Ubuntu) base image. Designed for use as a lightweight, customizable Python runtime in
container-based workflows.

*Inspired by a personal need (want) for a production-grade, Ubuntu-based Python "**base**" image.*

---

## Quick Reference

- **GitHub Repository**: [stairwaytowonderland/cpython](https://github.com/stairwaytowonderland/cpython)
- **Docker Hub**: [stairwaytowonderland/cpython](https://hub.docker.com/r/stairwaytowonderland/cpython)
- **Maintained by**: [Andrew Haller](https://github.com/andrewhaller)
- **License**: [MIT](https://github.com/stairwaytowonderland/cpython/blob/main/LICENSE)

---

## Supported Tags

Tags follow the format `<python-version>[-<variant(def|perf)>][-<base-image-ref>]`.

> **NOTE**: If the *base-image* **variant** is `latest`, the `<base-image-ref>` refers to the *base-image* **name**, otherwise
> `<base-image-ref>` refers to the *base-image* **variant**.
> <br><br>
> Example:
>
> - If the *base-image* is `ubuntu:latest`, then `<base-image-ref>` will be **`ubuntu`** (the *base-image* **name**).
> - If *base-image* is `debian:bookworm-slim`, then `<base-image-ref>` will be **`bookworm-slim`** (the *base-image* **variant**).

| Ubuntu<br>(*`ubuntu:latest`*)                                                                                                                                | Debian<br>(*`debian:bookworm-slim`*)                                                                            | Python Version | Notes                                       |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- | -------------- | ------------------------------------------- |
| [`latest`](https://hub.docker.com/layers/stairwaytowonderland/cpython/latest), [`ubuntu`](https://hub.docker.com/layers/stairwaytowonderland/cpython/ubuntu) | [`bookworm-slim`](https://hub.docker.com/layers/stairwaytowonderland/cpython/bookworm-slim)                     | latest         | Default build                               |
| [`3.14-ubuntu`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.14-ubuntu)                                                                      | [`3.14-bookworm-slim`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.14-bookworm-slim)           | 3.14           | Standard build                              |
| [`3.14-perf-ubuntu`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.14-perf-ubuntu)                                                            | [`3.14-perf-bookworm-slim`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.14-perf-bookworm-slim) | 3.14           | PGO-optimized (`ENABLE_OPTIMIZATIONS=true`) |
| [`3.14-dev-ubuntu`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.14-dev-ubuntu)                                                              | [`3.14-dev-bookworm-slim`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.14-dev-bookworm-slim)   | 3.14           | Dev build with extended tooling             |
| [`3.13-ubuntu`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.13-ubuntu)                                                                      | [`3.13-bookworm-slim`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.13-bookworm-slim)           | 3.13           | Standard build                              |
| [`3.12-ubuntu`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.12-ubuntu)                                                                      | [`3.12-bookworm-slim`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.12-bookworm-slim)           | 3.12           | Standard build                              |
| [`3.12-perf-ubuntu`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.12-perf-ubuntu)                                                            | [`3.12-perf-bookworm-slim`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.12-perf-bookworm-slim) | 3.12           | PGO-optimized (`ENABLE_OPTIMIZATIONS=true`) |
| [`3.12-dev-ubuntu`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.12-dev-ubuntu)                                                              | [`3.12-dev-bookworm-slim`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.12-dev-bookworm-slim)   | 3.12           | Dev build with extended tooling             |
| [`3.11-ubuntu`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.11-ubuntu)                                                                      | [`3.11-bookworm-slim`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.11-bookworm-slim)           | 3.11           | Standard build                              |
| [`3.10-ubuntu`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.10-ubuntu)                                                                      | [`3.10-bookworm-slim`](https://hub.docker.com/layers/stairwaytowonderland/cpython/3.10-bookworm-slim)           | 3.10           | Standard build                              |

---

## Supported Platforms

- `linux/amd64`
- `linux/arm64`

---

## Base Images

All images are built on top of Debian-based base images. The default base is `ubuntu:latest`.

| Base Image | Variant         |
| ---------- | --------------- |
| `ubuntu`   | `latest`        |
| `debian`   | `bookworm-slim` |

> **Note**: The Dockerfile requires a Debian-based image. Other Debian-derived distributions may be used via the
> `IMAGE_NAME` and `VARIANT` build arguments.

---

## Usage

### Using in a Dockerfile

Use one of the published images as a base for your own application image:

```dockerfile
FROM stairwaytowonderland/cpython:3.14-ubuntu

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["python", "main.py"]
```

### Building the Image

Clone the repository and use the provided build script from the project root:

```bash
# Build with the default Python version (latest) targeting the base stage
./docker/bin/build.sh cpython .

# Build a specific Python version
./docker/bin/build.sh cpython \
  --build-arg PYTHON_VERSION=3.14 \
  .

# Build with PGO optimizations enabled
./docker/bin/build.sh cpython \
  --build-arg PYTHON_VERSION=3.14 \
  --build-arg ENABLE_OPTIMIZATIONS=true \
  .
```

Or build directly with `docker build`:

```bash
docker build \
  --build-arg PYTHON_VERSION=3.14 \
  --target base \
  -t cpython:3.14-ubuntu \
  -f docker/Dockerfile \
  .
```

### Running a Python Command

Run a one-off Python command using the image:

```bash
docker run --rm stairwaytowonderland/cpython:3.14-ubuntu python3 --version
```

Run an interactive Python shell:

```bash
docker run -it --rm stairwaytowonderland/cpython:3.14-ubuntu python3
```

Run a local script by mounting your project directory:

```bash
docker run --rm \
  -v "$(pwd)":/app \
  -w /app \
  stairwaytowonderland/cpython:3.14-ubuntu \
  python3 main.py
```

---

## License

This project is licensed under the **MIT License** — free to use, modify, and distribute with attribution.

See the [LICENSE](https://github.com/stairwaytowonderland/cpython/blob/main/LICENSE) file for the full license text.
