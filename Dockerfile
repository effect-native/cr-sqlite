# Test CR-SQLite package in a clean Linux environment
FROM node:18-slim

# Install system dependencies for SQLite and Nix
RUN apt-get update && apt-get install -y \
    sqlite3 \
    curl \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Nix for building the extension
RUN curl -L https://nixos.org/nix/install | sh -s -- --yes --daemon
ENV PATH="/nix/var/nix/profiles/default/bin:${PATH}"

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY flake.nix flake.lock ./
COPY scripts/ ./scripts/
COPY build-macros.ts ./
COPY index.js index.d.ts ./
COPY bin/ ./bin/

# Install dependencies
RUN npm install

# Build the extension for current platform
RUN /bin/bash -c '. /nix/var/nix/profiles/default/etc/profile.d/nix.sh && nix run .#build-all-platforms'

# Test that the extension can be loaded
RUN node -e "
  import('./index.js').then(({ pathToCRSQLite }) => {
    console.log('✅ Package loads successfully');
    console.log('Extension path:', pathToCRSQLite);
    
    // Test with sqlite3 CLI
    const { execSync } = require('child_process');
    try {
      execSync(\`echo 'SELECT 1;' | sqlite3 -cmd '.load \${pathToCRSQLite}' :memory:\`, { stdio: 'inherit' });
      console.log('✅ Extension loads in SQLite successfully');
    } catch (error) {
      console.error('❌ Failed to load extension in SQLite:', error.message);
      process.exit(1);
    }
  }).catch(error => {
    console.error('❌ Package failed to load:', error.message);
    process.exit(1);
  });
"

# Test CLI tool
RUN npx cr-sqlite-extension-path

CMD ["echo", "✅ All tests passed! CR-SQLite package works in Docker."]