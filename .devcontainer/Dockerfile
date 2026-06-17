FROM mcr.microsoft.com/devcontainers/javascript-node:1-20-bookworm

ARG GODOT_VERSION=4.6

RUN apt-get update && apt-get install -y \
    unzip \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Godot 4.x headless (--headless フラグで GUI なしで実行可能)
RUN wget -q \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    -O /tmp/godot.zip \
    && unzip /tmp/godot.zip -d /tmp/godot \
    && mv "/tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -rf /tmp/godot /tmp/godot.zip
