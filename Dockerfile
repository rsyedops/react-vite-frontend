# syntax=docker/dockerfile:1

# Vite 2 predates Node 18 and fails to load its own config on current releases.
# Pinning the build stage is what keeps the application source untouched.
FROM node:16.20.2-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

# Baked in at build time because a static bundle has no runtime environment.
# "/api" keeps the image environment-agnostic: the ingress decides which backend
# that path reaches.
ARG VITE_API_URL=/api
ENV VITE_API_URL=$VITE_API_URL

COPY . .
RUN npm run build

# The unprivileged variant listens on 8080 as a non-root user, with no need for
# NET_BIND_SERVICE or a writable /var/run.
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime

# Patched base packages. The image runs as nginx, so root is taken only for
# the upgrade and dropped again before anything else is added.
USER root
RUN apk upgrade --no-cache
USER nginx

COPY --chown=nginx:nginx docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build --chown=nginx:nginx /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
