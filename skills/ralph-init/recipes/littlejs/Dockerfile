FROM node:20

# Install project toolchain
WORKDIR /workspace

# Copy package files and install dependencies
COPY package*.json ./
RUN npm ci || npm install

# Install claude-code CLI (required for AFK)
RUN npm install -g @anthropic-ai/claude-code

# Preserve working directory
WORKDIR /workspace
