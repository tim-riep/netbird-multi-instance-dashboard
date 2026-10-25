# NetBird Dashboard

NetBird Dashboard is NetBird's management server UI.

## Tags

Each published image tag also has a rootless variant with the `-rootless`
suffix. For example, `main` is also published as `main-rootless`.

Each tag also has a Red Hat UBI variant with the `-ubi` suffix (for example
`main-ubi`). Stable releases are also tagged `ubi-latest`.

## How to use this image

HTTP:

```shell
docker run -d --rm -p 80:80 netbirdio/dashboard:main
```

Using an SSL certificate from Let's Encrypt:

```shell
docker run -d --rm -p 80:80 -p 443:443 \
  -e LETSENCRYPT_DOMAIN=app.mydomain.com \
  -e LETSENCRYPT_EMAIL=hello@mydomain.com \
  netbirdio/dashboard:main
```

For certificate generation, the server needs a public IP and a domain name
pointing to it.

### Rootless and OpenShift

The rootless image listens on port `8080`, runs as UID `10001` by default, and
supports OpenShift's arbitrary UID when the container retains GID `0`:

```shell
docker run -d --rm \
  --user 12345:0 \
  -p 8080:8080 \
  -e AUTH_AUTHORITY=https://idp.example.com \
  -e AUTH_CLIENT_ID=netbird-dashboard \
  -e AUTH_AUDIENCE=netbird-dashboard \
  -e AUTH_SUPPORTED_SCOPES='openid profile email' \
  -e USE_AUTH0=false \
  -e NETBIRD_MGMT_API_ENDPOINT=https://api.example.com \
  netbirdio/dashboard:main-rootless
```

The rootless image does not include Certbot or expose HTTPS. Terminate TLS at
the OpenShift Route, Ingress, or another reverse proxy.

### Red Hat UBI

The `-ubi` image behaves like the rootless image (port `8080`, UID `10001`,
GID `0`, no HTTPS) but is built on Red Hat Universal Base Image 9 minimal with
nginx 1.26 from the RHEL AppStream, for Red Hat container certification. It is
published for `linux/amd64` and `linux/arm64` only. License terms are in
`/licenses`.

## Several instances, one per hostname

One container can serve the dashboard for several NetBird instances. Which
instance a browser gets depends on the hostname in the URL.

Put one file per hostname into a directory, named `<hostname>.env`, and mount
it at `/etc/netbird-dashboard/instances` (or point `NETBIRD_INSTANCES_DIR`
somewhere else). Each file sets the same variables as the container
environment, as shell assignments:

```shell
# instances/vpn-a.example.com.env
NETBIRD_MGMT_API_ENDPOINT=https://api-a.example.com
AUTH_AUTHORITY=https://idp.example.com/realms/a
AUTH_CLIENT_ID=netbird-dashboard-a
NETBIRD_ANNOUNCEMENT='Instance "A"'
```

```shell
docker run -d --rm -p 8080:8080 \
  -v "$PWD/instances:/etc/netbird-dashboard/instances:ro" \
  -e AUTH_AUDIENCE=netbird-dashboard \
  -e AUTH_SUPPORTED_SCOPES='openid profile email' \
  -e USE_AUTH0=false \
  netbirdio/dashboard:main-rootless
```

- A variable the file leaves out is taken from the container environment, so
  settings all instances share can stay there.
- If the container environment is complete on its own, it is the default
  instance for every hostname without a file. Otherwise those hostnames get
  a 404.
- The browser loads its settings from `/config.json`. nginx answers it, and
  sets the Content-Security-Policy header, for the instance of the requested
  hostname only, so no instance's settings are visible from another hostname.
- The files are read at container start. Restart the container after
  changing them.
- `LETSENCRYPT_DOMAIN` covers a single domain. For several hostnames,
  terminate TLS at a reverse proxy that passes the original `Host` header.

## Environment variables

- `NGINX_SSL_PORT` changes the port that Nginx listens to. Defaults to `443`.
- `LETSENCRYPT_DOMAIN` enables Certbot for the specified domain. Defaults to
  `none`.
- `LETSENCRYPT_EMAIL` is used to register the certificate request. Defaults to
  `example@local`.

These certificate variables apply only to the standard image.