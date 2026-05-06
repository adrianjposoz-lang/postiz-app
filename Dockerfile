# Postiz production image — RSC fork.
# Mirrors the upstream Dockerfile.dev pattern (which is what the official
# ghcr.io/gitroomhq/postiz-app image effectively runs). Single-stage on purpose:
# matches Postiz's known-good build path; multi-stage trim can come later if needed.

FROM node:22.20-bookworm-slim

# Optional version metadata exposed to Next.js at build time.
ARG NEXT_PUBLIC_VERSION
ENV NEXT_PUBLIC_VERSION=$NEXT_PUBLIC_VERSION

# Build toolchain + nginx. Postiz fronts frontend + backend behind an nginx reverse
# proxy whose config (var/docker/nginx.conf) listens internally on :5000.
RUN apt-get update && apt-get install -y --no-install-recommends \
      g++ make python3-pip bash nginx \
    && rm -rf /var/lib/apt/lists/*

# Non-root user used by nginx (matches upstream).
RUN addgroup --system www \
 && adduser --system --ingroup www --home /www --shell /usr/sbin/nologin www \
 && mkdir -p /www \
 && chown -R www:www /www /var/lib/nginx

# pnpm + pm2 pinned. pm2 supervises the 3 app processes (frontend, backend, orchestrator).
RUN npm --no-update-notifier --no-fund --global install pnpm@10.6.1 pm2

WORKDIR /app
COPY . /app
COPY var/docker/nginx.conf /etc/nginx/nginx.conf

# Install + postinstall (runs `prisma generate`). Postiz's package.json whitelists
# bcrypt in pnpm.onlyBuiltDependencies; sharp ships prebuilt binaries that work
# without further approval. If a future runtime error points at a missing native
# dep, add it to pnpm.onlyBuiltDependencies upstream or `pnpm rebuild <pkg>` here.
RUN pnpm install --frozen-lockfile

# Build all three apps; 4GB heap mirrors upstream (512MB default OOMs).
RUN NODE_OPTIONS="--max-old-space-size=4096" pnpm run build

# nginx listens on 5000 per the bundled config; Railway routes external traffic here.
EXPOSE 5000

# nginx in background, then pm2 starts the 3 processes (delete -> prisma db push ->
# parallel start of frontend/backend/orchestrator). Matches upstream CMD.
CMD ["sh", "-c", "nginx && pnpm run pm2"]
