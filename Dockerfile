# Headless Ghidra for arm64. Kept in a container so the host needs no JDK.
FROM eclipse-temurin:25-jdk

# The release tag is Ghidra_<ver>_build, and the asset filename carries a build date
# (ghidra_12.1.3_PUBLIC_20260817.zip) that cannot be derived from the version -- so
# resolve it from the release API. Set GHIDRA_URL to pin one exactly or build offline.
ARG GHIDRA_VER=12.1.3
ARG GHIDRA_URL=
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends unzip curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
    url="${GHIDRA_URL}"; \
    if [ -z "$url" ]; then \
      url="$(curl -fsSL "https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/tags/Ghidra_${GHIDRA_VER}_build" \
             | grep -o 'https://[^"]*_PUBLIC_[0-9]*\.zip' | head -n1)"; \
    fi; \
    test -n "$url"; \
    echo "==> ghidra ${GHIDRA_VER} from ${url}"; \
    curl -fsSL -o /tmp/ghidra.zip "$url"; \
    unzip -q /tmp/ghidra.zip -d /opt; \
    rm /tmp/ghidra.zip; \
    mv /opt/ghidra_* /opt/ghidra

ENV PATH="/opt/ghidra/support:${PATH}"
WORKDIR /work
