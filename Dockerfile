FROM node:22-bookworm-slim

ENV NODE_ENV=production
WORKDIR /app/src

# Install prod deps first for layer caching (onnxruntime-node pulls prebuilt
# glibc binaries during install — bookworm-slim is glibc, so no compiler needed).
COPY src/package.json src/package-lock.json ./
RUN npm ci --omit=dev

# App source
COPY src/ ./

# Model cache dir (populated at runtime by fetch-model.js -> ../model) owned by
# the unprivileged node user that ships in the base image.
RUN mkdir -p /app/model && chown -R node:node /app
USER node

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "index.js"]
