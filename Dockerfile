# Use NGINX as the base image
FROM nginx:1.30

# Copy the NGINX configuration and built web files with non-root ownership.
COPY --chown=nginx:nginx nginx.conf /etc/nginx/nginx.conf
COPY --chown=nginx:nginx ./build/web /usr/share/nginx/html

# Allow NGINX to bind to port 80 and write to the needed directories
# without running as root.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends libcap2-bin \
    && setcap cap_net_bind_service=+ep /usr/sbin/nginx \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/cache/nginx \
    && touch /var/run/nginx.pid \
    && chown -R nginx:nginx /var/cache/nginx \
    && chown nginx:nginx /var/run/nginx.pid

# The NGINX container exposes port 80 by default
# and starts automatically, so there's no need
# to specify an entrypoint or command. The
# EXPOSE statement has no effect and is purely
# for documentation.
EXPOSE 80

USER nginx:nginx
