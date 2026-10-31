# Node is for actions/checkout. A Forgejo runner's default ubuntu-latest image is node:20-bookworm.
FROM node:20-bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
