FROM alpine:3.23
LABEL org.opencontainers.image.authors="seji@tihoda.de"
ARG TARGETPLATFORM

ENV DNSDIST_BIND_IP=0.0.0.0
ENV ALLOWED_CLIENTS=127.0.0.1
ENV ALLOWED_CLIENTS_FILE=/etc/snidust/clients.txt
ENV EXTERNAL_IP=

ENV DNSDIST_ENABLE_DOT=false
ENV DNSDIST_DOT_CERT_TYPE=auto-self

ENV DNSDIST_WEBSERVER_PASSWORD=
ENV DNSDIST_WEBSERVER_API_KEY=
ENV DNSDIST_WEBSERVER_NETWORKS_ACL="127.0.0.1, ::1"

ENV DNSDIST_UPSTREAM_CHECK_INTERVAL=10
ENV DNSDIST_UPSTREAM_POOL_NAME="upstream"

ENV DNSDIST_RATE_LIMIT_DISABLE=false
ENV DNSDIST_RATE_LIMIT_WARN=800
ENV DNSDIST_RATE_LIMIT_BLOCK=1000
ENV DNSDIST_RATE_LIMIT_BLOCK_DURATION=360
ENV DNSDIST_RATE_LIMIT_EVAL_WINDOW=60

ENV DNSDIST_PACKAGE_CACHE_ENABLED=false
ENV DNSDIST_PACKAGE_CACHE_SIZE=50000

ENV SPOOF_ALL_DOMAINS=false
ENV DYNDNS_CRON_SCHEDULE="*/15 * * * *"
ENV INSTALL_DEFAULT_DOMAINS=true

HEALTHCHECK --interval=30s --timeout=3s CMD (pgrep "dnsdist" > /dev/null && pgrep "nginx" > /dev/null) || exit 1

EXPOSE 5300/udp
EXPOSE 8080/tcp
EXPOSE 8443/tcp
EXPOSE 8083/tcp
EXPOSE 8530/tcp
EXPOSE 8085/tcp

RUN apk update && apk upgrade && \
    apk add --no-cache jq tini dnsdist curl bash gnupg procps ca-certificates \
    openssl dog lua5.4-filesystem ipcalc libcap nginx nginx-mod-stream supercronic step-cli python3 && \
    rm -f /etc/nginx/conf.d/*.conf && \
    rm -rf /var/cache/apk/*

RUN mkdir -p /etc/dnsdist/conf.d /etc/dnsdist/certs /etc/snidust/domains.d /etc/sniproxy/ /var/lib/snidust/domains.d

COPY configs/dnsdist/dnsdist.conf.template /etc/dnsdist/dnsdist.conf.template
COPY configs/dnsdist/conf.d/00-SniDust.conf /etc/dnsdist/conf.d/00-SniDust.conf
COPY configs/nginx/nginx.conf /etc/nginx/nginx.conf
COPY domains.d /var/lib/snidust/domains.d

COPY entrypoint.sh /entrypoint.sh
COPY generateACL.sh /generateACL.sh
COPY dynDNSCron.sh /dynDNSCron.sh
COPY webpanel.py /webpanel.py

RUN chown -R snidust:snidust /etc/dnsdist/ /etc/snidust/ /etc/nginx/ /var/log/nginx/ /var/lib/nginx/ /run/nginx/ && \
    chmod +x /entrypoint.sh /generateACL.sh /dynDNSCron.sh

USER snidust

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/bin/bash", "/entrypoint.sh"]
