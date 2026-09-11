#!/bin/bash -e

if [ "${DNSDIST_ENABLE_DOT}" == "true" ]; then
  VALID_CERT_TYPE_VALUES=("auto-self" "manual")
  if [[ -z "$DNSDIST_DOT_CERT_TYPE" ]]; then
    echo "The environment variable DNSDIST_DOT_CERT_TYPE is not set."
    exit 1
  fi

  if [[ " ${VALID_CERT_TYPE_VALUES[*]} " =~ " ${DNSDIST_DOT_CERT_TYPE} " ]]; then
    if [ "${DNSDIST_DOT_CERT_TYPE}" == "auto-self" ]; then
      /usr/bin/step certificate create dot.snidust.local /etc/dnsdist/certs/tls.pem /etc/dnsdist/certs/tls.key --profile self-signed --subtle --no-password --insecure
    fi
  else
    echo "[ERROR] Invalid value for DNSDIST_DOT_CERT_TYPE: $DNSDIST_DOT_CERT_TYPE"
    exit 1
  fi
fi

if [ -z "${EXTERNAL_IP}" ]; then
  echo "[INFO] External IP not set - trying to get IP by myself"
  EXTERNAL_IP=$(curl -f icanhazip.com)
  export EXTERNAL_IP
fi

if [ -z "${DNSDIST_WEBSERVER_PASSWORD}" ]; then
  echo "[INFO] Dnsdist webserver password not set - generating one"
  DNSDIST_WEBSERVER_PASSWORD=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c12)
  export DNSDIST_WEBSERVER_PASSWORD
fi

if [ -z "${DNSDIST_WEBSERVER_API_KEY}" ]; then
  echo "[INFO] Dnsdist webserver api key not set - generating one"
  DNSDIST_WEBSERVER_API_KEY=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32)
  export DNSDIST_WEBSERVER_API_KEY
fi

if [ "$INSTALL_DEFAULT_DOMAINS" = true ]; then
  echo "[INFO] Installing default domains..."
  cp -vn /var/lib/snidust/domains.d/*.lst /etc/snidust/domains.d/ 2>/dev/null || true
fi

# ایجاد فایل کلاینت‌ها در صورتی که وجود نداشته باشد
if [ ! -f "/etc/snidust/clients.txt" ]; then
  echo "$ALLOWED_CLIENTS" | tr ',' '\n' | sed 's/^[ \t]*//;s/[ \t]*$//' > /etc/snidust/clients.txt
fi
export ALLOWED_CLIENTS_FILE="/etc/snidust/clients.txt"

echo "[INFO] Generating ACL..."
set +e
source generateACL.sh
set -e

echo "[INFO] Generating DNSDist Config..."
/bin/bash /etc/dnsdist/dnsdist.conf.template > /etc/dnsdist/dnsdist.conf

if [ "$DYNDNS_CRON_ENABLED" = true ]; then
  echo "[INFO] DynDNS Address in ALLOWED_CLIENTS detected => Enable cron job"
  echo "$DYNDNS_CRON_SCHEDULE /bin/bash /dynDNSCron.sh" > /etc/snidust/dyndns.cron
  supercronic /etc/snidust/dyndns.cron &
fi

echo "[INFO] Starting DNSDist..."
/usr/bin/dnsdist -C /etc/dnsdist/dnsdist.conf --supervised --disable-syslog --uid snidust --gid snidust &

echo "[INFO] Starting Web Panel..."
python3 /webpanel.py &

echo "[INFO] Starting nginx.."
nginx
nginx_processId=$!

sleep 5

echo "==================================================================="
echo "[INFO] SniDust started => Using $EXTERNAL_IP"
echo "[INFO] WebPanel active on port 8085"
echo "==================================================================="
wait $nginx_processId
