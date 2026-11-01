FROM node:20-alpine AS base

# Install security updates
RUN apk --no-cache add ca-certificates dumb-init

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8080
ENV HOST=0.0.0.0

COPY package*.json ./

# Install only production dependencies
RUN npm ci --only=production

COPY src/ ./src/

# Create unprivileged runtime user
USER node

EXPOSE 8080

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "src/index.js"]
