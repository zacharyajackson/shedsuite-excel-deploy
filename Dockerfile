# Multi-stage build for production optimization
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install all dependencies (including dev dependencies for build)
RUN npm ci

# Copy source code
COPY src ./src

# ================================
# Production stage
FROM node:18-alpine AS production

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S shedsuite -u 1001 -G nodejs

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install only production dependencies
RUN npm ci --only=production && \
    npm cache clean --force

# Copy application source from builder stage
COPY --from=builder --chown=shedsuite:nodejs /app/src ./src

# Create logs directory and state directory for progress tracking
RUN mkdir -p logs && \
    mkdir -p .state && \
    chown -R shedsuite:nodejs logs && \
    chown -R shedsuite:nodejs .state

# Copy production scripts and configuration
COPY production ./production
COPY scripts ./scripts
COPY docs ./docs

# Set proper permissions
RUN chown -R shedsuite:nodejs production && \
    chown -R shedsuite:nodejs scripts && \
    chown -R shedsuite:nodejs docs

# Switch to non-root user
USER shedsuite

# Enhanced health check with more comprehensive validation
HEALTHCHECK --interval=30s --timeout=15s --start-period=10s --retries=3 \
    CMD node -e "const http = require('http'); const options = { hostname: 'localhost', port: process.env.PORT || 3000, path: '/health', timeout: 10000 }; const req = http.get(options, (res) => { if (res.statusCode === 200) { let data = ''; res.on('data', (chunk) => { data += chunk; }); res.on('end', () => { try { const health = JSON.parse(data); process.exit(health.overall === 'healthy' ? 0 : 1); } catch (e) { process.exit(1); } }); } else { process.exit(1); } }); req.on('error', () => process.exit(1)); req.end();"

# Resource limits - these will be used by container orchestration platforms
ENV NODE_OPTIONS="--max-old-space-size=512"

# Expose port
EXPOSE 3000

# Use explicit signal handling for graceful shutdown
STOPSIGNAL SIGTERM

# Start the application with production settings
CMD ["npm", "run", "start:production"]