FROM node:24-slim

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN npm install -g openclaw
# Install missing bundled channel plugin dependencies
# OpenClaw bundles channel plugins but doesn't ship all their SDK deps.
# Without these, every HTTP request crashes with MODULE_NOT_FOUND.
RUN cd /usr/local/lib/node_modules/openclaw && npm install --no-save \
    @buape/carbon \
    @larksuiteoapi/node-sdk \
    @slack/web-api @slack/bolt @slack/socket-mode \
    2>/dev/null || true

# Create non-root user
RUN useradd -m -s /bin/bash openclaw
USER openclaw
WORKDIR /home/openclaw

# Config will be mounted as volume or set via environment
RUN mkdir -p /home/openclaw/.openclaw

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

EXPOSE 18789

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
