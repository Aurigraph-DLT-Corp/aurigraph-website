# Dockerfile for Aurigraph Website (Next.js)
# Supports both development and production modes

FROM node:21-alpine

WORKDIR /app

# Install dumb-init to handle signals properly and wget for health checks
RUN apk add --no-cache dumb-init wget

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy source code and public files
COPY . .

# Build for production (creates .next directory)
RUN npm run build

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nextjs -u 1001

# Ensure proper permissions for nextjs user
RUN chown -R nextjs:nodejs /app

USER nextjs

# Expose port 3000
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:3000 || exit 1

# Use dumb-init to handle signals
ENTRYPOINT ["dumb-init", "--"]

# Start Next.js app - supports both dev and production based on NODE_ENV
CMD [ "sh", "-c", "if [ \"$NODE_ENV\" = \"development\" ]; then npm run dev; else npm start; fi" ]
