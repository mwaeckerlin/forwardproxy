#!/bin/bash -e

if [ ! -z "$(ls -A /etc/nginx.original)" ]; then
    if [ -z "$(ls -A /etc/nginx)" ]; then
        echo "restore configuration"
        cp -a /etc/nginx.original/* /etc/nginx/
        chown -R www-data.www-data /etc/nginx
    fi
    rm -rf /etc/nginx.original
fi
sed -i '/^daemon off/d' /etc/nginx/nginx.conf
! test -e /etc/nginx/sites-enabled/default || rm /etc/nginx/sites-enabled/default

startNginx() {
    if nginx -t; then
        if pgrep nginx 2>&1 > /dev/null; then
            nginx -s reload
        else
            nginx
        fi
    else
        echo "**** ERROR: nginx configuration failed" 1>&2
    fi
}

updateConfig() {
    /nginx-configure.sh $*
    if nginx -t; then
        nginx -s reload
        if certbot renew -n --agree-tos -a webroot --webroot-path=/acme; then
            nginx -s reload
        fi
        echo "**** configuration updated $(date)"
    else
        echo "#### ERROR: configuration not updated $(date)" 1>&2
    fi
}

# source all configuration files named *.conf.sh
for f in /*.conf.sh /run/secrets/*.conf.sh; do
    if test -e "$f"; then
        . "$f"
    fi
done

#test -e /etc/ssl/certs/dhparam.pem || \
#    openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048

# run webserver
startNginx
if test -e /config/reverse-proxy.conf; then
    updateConfig $(</config/reverse-proxy.conf)
    if test "${LETSENCRYPT}" != "never"; then
        if ! pgrep cron 2>&1 > /dev/null; then
            cron -L7
        fi
    fi
    while true; do
        inotifywait -q -e close_write /config/reverse-proxy.conf
        echo "**** configuration changed $(date)"
        updateConfig $(</config/reverse-proxy.conf)
    done
else
    updateConfig
    if test "${LETSENCRYPT}" != "never"; then
        if ! pgrep cron 2>&1 > /dev/null; then
            cron -L7
        fi
    fi
    sleep infinity
fi
