#!/bin/bash -ex

OPT=${1:-"-f"}
PORT=80

# check how to run apache
sed -i '/^daemon off/d' /etc/nginx/nginx.conf
proxycmd=nginx
case "${OPT}" in
    (-f) echo "daemon off;" >> /etc/nginx/nginx.conf;;
    (-d) ;;
    (-n) proxycmd="sleep infinity";;
    (-h|--help)
        echo "OPTIONS:"
        echo "  -h    show this help"
        echo "  -f    run in foreground"
        echo "  -d    run as daemon in background"
        echo "  -n    don't start apache, only configure"
        exit;;
    (*) echo "unknown option $OPT, try --help"; exit 1;;
esac

# cleanup from previous run
rm -r /etc/nginx/sites-{available,enabled}/* || true

# check for environment variables that are set for explicit redirecting
# redirect
for redirect in $(env | sed -n 's/redirect-\(.*\)=.*/\1/p'); do
    frompath=$(echo "${redirect,,}" | sed 's/+/ /g;s/%\([0-9a-f][0-9a-f]\)/\\x\1/g;s/_/-/g' | xargs -0 printf "%b")
    fromservername=${frompath%%/*}
    if test "${frompath#*/}" != "${frompath}"; then
        cmd="rewrite ^/${frompath#*/}/(.*)$ http://${target}/\$1 redirect"
    else
        cmd="return 301 \$scheme://${target}\$request_uri"
    fi     
    target=$(env | sed -n 's/redirect-'$redirect'=//p')
    site=${fromservername}${fromlocation//\//_}.conf
    cat > /etc/nginx/sites-available/${site} <<EOF
         server { # redirect www to non-www
           listen ${PORT};
           server_name www.${fromservername};
           return 301 \$scheme://${fromservername}\$request_uri;
         }
         server {
           listen ${PORT};
           server_name ${fromservername};
           ${cmd};
         }
EOF
    cat /etc/nginx/sites-available/${site}
    ln -s /etc/nginx/sites-available/${site} /etc/nginx/sites-enabled/${site}
done
# forward
for forward in $(env | sed -n 's/forward-\(.*\)=.*/\1/p'); do
    frompath=$(echo "${forward,,}" | sed 's/+/ /g;s/%\([0-9a-f][0-9a-f]\)/\\x\1/g;s/_/-/g' | xargs -0 printf "%b")
    fromservername=${frompath%%/*}
    if test "${frompath#*/}" != "${frompath}"; then
        fromlocation=/${frompath#*/}
    else
        fromlocation=
    fi     
    target=$(env | sed -n 's/forward-'$forward'=//p')
    site=${fromservername}${fromlocation//\//_}.conf
    cat > /etc/nginx/sites-available/${site} <<EOF
         server { # redirect www to non-www
           listen ${PORT};
           server_name www.${fromservername};
           return 301 \$scheme://${fromservername}\$request_uri;
         }
         server {
           listen ${PORT};
           server_name ${fromservername};
           location ${fromlocation}/ {
             include proxy.conf;
             proxy_pass ${target};
             subs_filter "http://${target}" "http://${frompath}";
             subs_filter "${target}" "${frompath}";
           }
         }
EOF
    cat /etc/nginx/sites-available/${site}
    ln -s /etc/nginx/sites-available/${site} /etc/nginx/sites-enabled/${site}
done
# scan through all linked docker containers and add virtual hosts
for name in $(env | sed -n 's/_PORT_.*_TCP_ADDR=.*//p' | sort | uniq); do
    if env | egrep -q '^'${name}'_TO_PORT='; then
        linkedport="$(env | sed -n 's/'${name}'_TO_PORT=//p')"
    else
        linkedport="$(env | sed -n 's/'${name}'_PORT_.*_TCP_PORT=//p')"
    fi
    linkedhostname="$(env | sed -n 's/'${name}'_NAME=.*\///p')"
    linkedip="$(env | sed -n 's/'${name}'_PORT_'${linkedport}'_TCP_ADDR=//p')"
    linkedserverpath=$(echo "${name,,}" | sed 's/+/ /g;s/%\([0-9a-f][0-9a-f]\)/\\x\1/g;s/_/-/g' | xargs -0 printf "%b")
    linkedservername=${linkedserverpath%%/*}
    if test "${linkedserverpath#*/}" != "${linkedserverpath}"; then
        linkedlocation=/${linkedserverpath#*/}
    else
        linkedlocation=
    fi
    if test "${linkedport}" = "${PORT}"; then
        linkedproxy="http://${linkedip}"
    else
        linkedproxy="http://${linkedip}:${linkedport}"
    fi
    site=${linkedhostname}_${linkedservername}_${linkedport}.conf
    cat > /etc/nginx/sites-available/${site} <<EOF
         server { # redirect www to non-www
           listen ${PORT};
           server_name www.${linkedservername};
           return 301 \$scheme://${linkedservername}\$request_uri;
         }
         server {
           listen ${PORT};
           server_name ${linkedservername};
           location ${linkedlocation}/ {
             include proxy.conf;
             proxy_pass ${linkedproxy};
             subs_filter "http://${linkedip}:${linkedport}" "http://${linkedservername}${linkedlocation}";
             subs_filter "http://${linkedip}" "http://${linkedservername}${linkedlocation}";
             subs_filter "${linkedip}:${linkedport}" "${linkedservername}${linkedlocation}";
             subs_filter "${linkedip}" "${linkedservername}${linkedlocation}";
           }
         }
EOF
    cat /etc/nginx/sites-available/${site}
    ln -s /etc/nginx/sites-available/${site} /etc/nginx/sites-enabled/${site}
done

# run apache
eval $proxycmd
