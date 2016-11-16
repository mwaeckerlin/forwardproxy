# Docker Image: Virtual Hosts Reverse Proxy

## Redirect URL to Linked Container

On your computer start any number of services, then start a `mwaeckerlin/reverse-proxy` and link to all your docker services. The link alias must be the FQDN, the fully qualified domain name of your service. For example your URL is `wordpress.myhost.org` and wordpress runs in a docker container named `mysite`:

        docker run [...] -l mysite:wordpress.myhost.org mwaeckerlin/reverse-proxy

## If a Service Has More Than One Port

Normally the port is detected automatically. But if there are more than one open ports, you must declare which port you want to direct to. Jenkins for example exposes the ports 8080 and 5000. You want to forward to port 8080. For this you specify an additional environment variable that contains the URL in upper case, postfixed by `_TO_PORT`, e.g. redirect URL `jenkins.myhost.org` to port 8080 of container `jenkins`:

        docker run [...] -l jenkins:jenkins.myhost.org -e JENKINS.MYHOST.ORG_TO_PORT=8080 mwaeckerlin/reverse-proxy

## Forward or Redirect to Other Host

In addition, you can add environment variables that start with `redirect-` or `forward-` for an additional redirect or an additional forward, e.g. the following redirects from your old host at `old-host.com` to your new host at `new-host.org`, similary `-e forward-old-host.com=new-host.org` adds a forward:

        docker run [...] -e redirect-old-host.com=new-host.org mwaeckerlin/reverse-proxy

For special characters in the variable name (not in the value) use hexadecimal ASCII code, as in URL encoding, so if you need to append a path, use `%2f` instead of slash `/` in the path.

## SSL Certificates

Add a volume with your certificates in `/etc/ssl`, two files per URL, the certificate and the key, named <url>.crt and <url>.key. If found, it is automatically configured and http on port 80 is redirected to https on port 443.

## The Dummy-www-Prefix

Rules to redirect the dummy-www-prefix to the host without prefix are automatically added, so don't prepend `www.` to your hostnames.

## Example

Example:

  1. Start a wordpress instance (including a volume container):

        docker run -d --name test-volumes --volume /var/lib/mysql --volume /var/www/html ubuntu sleep infinity
        docker run -d --volumes-from test-volumes --name test-mysql -e MYSQL_ROOT_PASSWORD=$(pwgen -s 16 1) mysql
        docker run -d --volumes-from test-volumes --name test-wordpress --link test-mysql:mysql wordpress
  2. Start any number of other services ...
  3. Start a `reverse-proxy`: 

        docker run -d --restart=always --name reverse-proxy \
          --link test-wordpress:test.mydomain.com \
          -p 80:80 mwaeckerlin/reverse-proxy
  4. Head your browser to http://test.mydomain.com

Other Example:

  1. Situation:
    1. `hosta` in local network is public visible through `https://host.com`
    2. There is a `mwaeckerlin/dokuwiki` in a docker container on `hosta`
    3. There is a `mwaeckerlin/jenkins` running on `hostb` with opened port `8080`
    4. `https://host.com` is public in internet
    5. There is a SSL-certificate (in P12 format) for `host.com` named `host.com.p12`
  2. Requirements:
    1. There should be a default redirection from `https://host.com` to `https://host.com/dokuwiki`
    2. There should be a forwarding from `https://host.com/dokuwiki` to local container `dokuwiki`
    3. There should be a forwarding from `https://host.com/jenkins` to container `jenkins` that is exposed on port `8080` on `hostb`
  3. Configuration
    1. Create `host.com.crt` and an unencrypted `host.com.key` from `host.com.p12`: 

          ```bash
          openssl pkcs12 -in host.com.p12 -nocerts -out host.com.pem
          openssl rsa -in host.com.pem -out host.com.key
          openssl pkcs12 -in host.com.p12 -nokeys -out host.com.crt
          rm host.com.pem
          ```
    2. Create a docker volume containing the keys: 

          ```bash
          cat > Dockerfile <<EOF
          FROM mwaeckerlin/reverse-proxy
          VOLUME /etc/ssl
          ADD host.com.crt /etc/ssl/host.com.crt
          ADD host.com.key /etc/ssl/host.com.key
          CMD sleep infinity
          EOF
          docker build --rm --force-rm -t reverse-proxy-volume .
          rm Dockerfile
          ```
    3. Instanciate the volume and the reverse-proxy container 

          ```bash
          docker run -d --name reverse-proxy-volume reverse-proxy-volume
          docker run -d --name reverse-proxy \
            --volumes-from reverse-proxy-volume \
            -e redirect-host.com=host.com/dokuwiki \
            --link dokuwiki:host.com/dokuwiki \
            -e forward-host.com%2fjenkins=hostb:8080 \
            -p 80:80 -p 443:443 mwaeckerlin/reverse-proxy
          ```
