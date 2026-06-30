# Traefik — Overview and Migration from NGINX

## Overview

This document is the general reference for running **Traefik** as the ingress proxy in our Kubernetes environment. It explains what Traefik is, why we are moving away from NGINX (including the retirement of the NGINX Ingress Controller), how our Traefik setup is structured, and how to perform the migration.

In our environment, routes are primarily defined using Traefik's **file provider** (a YAML dynamic configuration file mounted into the Traefik pod via a ConfigMap). Traffic transformations — such as URL rewrite rules and CORS — are handled by **Traefik `Middleware` CRDs**. Kubernetes `Ingress` resources can also be enabled when needed through the `kubernetesIngress` provider.

---

## Table of Contents

1. [What is Traefik?](#what-is-traefik)
2. [Why Migrate: NGINX Ingress Retirement](#why-migrate-nginx-ingress-retirement)
3. [Why Choose Traefik](#why-choose-traefik)
4. [Key Differences](#key-differences)
5. [Prerequisites](#prerequisites)
6. [Routing Architecture](#routing-architecture)
7. [Traefik Middlewares](#traefik-middlewares)
   - [Using Middleware with Kubernetes Ingress Annotations (Optional)](#using-middleware-with-kubernetes-ingress-annotations-optional)
   - [URL Rewrite Rules](#url-rewrite-rules)
   - [CORS Configuration](#cors-configuration)
   - [HTTPS Redirect](#https-redirect)
8. [File Provider — Dynamic Route Configuration](#file-provider--dynamic-route-configuration)
   - [Full Example](#full-example)
   - [Referencing Middleware CRDs from the File Provider](#referencing-middleware-crds-from-the-file-provider)
   - [File Provider TLS Certificates via ConfigMap](#file-provider-tls-certificates-via-configmap)
9. [Applying Configuration to the Cluster](#applying-configuration-to-the-cluster)
   - [Helm Values Example (Custom Cert + Ingress + File Provider)](#helm-values-example-custom-cert--ingress--file-provider)
   - [Optional Ingress Resource Example](#optional-ingress-resource-example)
10. [Application Gateway Health Checks (`/ping`)](#application-gateway-health-checks-ping)
11. [Installation Script](#installation-script)
12. [Verification](#verification)
13. [Rollback Procedure](#rollback-procedure)
14. [Troubleshooting](#troubleshooting)
15. [References](#references)

---

## What is Traefik?

**Traefik** (pronounced _traffic_) is a modern, cloud-native reverse proxy and load balancer designed for dynamic environments such as Kubernetes, Docker, and service meshes. Unlike traditional proxies that require manual configuration restarts, Traefik automatically discovers services and updates its routing configuration in real time.

### Core concepts

| Concept | Description |
|---|---|
| **EntryPoint** | The network port Traefik listens on (e.g., port `80` for HTTP, port `443` for HTTPS). |
| **Router** | Matches an incoming request (by host, path, headers, etc.) and forwards it to a service. Routers can attach one or more middlewares. |
| **Middleware** | A processing step applied to a request or response before it reaches the backend — e.g., path rewriting, CORS headers, rate limiting, authentication. |
| **Service** | The upstream backend (Kubernetes Service, URL, etc.) that Traefik forwards matched requests to. |
| **Provider** | The source of Traefik's dynamic configuration. Common providers include `kubernetesCRD`, `kubernetesIngress`, and `file`. In our setup the primary routing provider is `file`. |

### How Traefik works

```
                        ┌──────────────────────────────────────────┐
                        │               Traefik                    │
                        │                                          │
  Incoming Request      │  EntryPoint ──▶ Router ──▶ Middlewares  │
 ──────────────────────▶│   (:80/:443)    (rules)    (rewrite,     │
                        │                             CORS, auth)  │
                        │                     │                    │
                        └─────────────────────┼────────────────────┘
                                              │
                                              ▼
                                   ┌─────────────────┐
                                   │  Backend Service │
                                   │  (Kubernetes     │
                                   │   ClusterIP)     │
                                   └─────────────────┘
```

Traefik reads its routing rules from one or more **providers**. When a provider's configuration changes (e.g., a ConfigMap is updated), Traefik reloads its routing table with **zero downtime** — no pod restart or reload signal is needed.

---

## Why Migrate: NGINX Ingress Retirement

The **NGINX Ingress Controller** (`kubernetes/ingress-nginx`) — the most widely used Kubernetes ingress controller — has reached **end-of-life**. The Kubernetes project announced that it will no longer receive new features, and active maintenance will wind down. The key points are:

- **Kubernetes SIG-Network** officially announced the deprecation and eventual retirement of `ingress-nginx` in favour of the **Gateway API**, which supersedes the older `networking.k8s.io/v1 Ingress` resource.
- Security patches and bug fixes for `ingress-nginx` will become increasingly limited over time.
- The `networking.k8s.io/v1 Ingress` API itself is considered a legacy API — it lacks the expressiveness needed for modern traffic management (e.g., traffic splitting, header-based routing, advanced middleware chains).
- Staying on a deprecated, unmaintained ingress controller increases operational risk: vulnerabilities (e.g., the critical `ingress-nginx` remote code execution CVEs in 2024–2025) will go unpatched.

### What this means for us

| Risk | Detail |
|---|---|
| Security vulnerabilities | No new patches for NGINX Ingress CVEs after EOL |
| No new features | Traffic management capabilities are frozen |
| Kubernetes version compatibility | Future Kubernetes versions may drop `Ingress` API support |
| Community support | Issue reports and PRs on `ingress-nginx` will go unaddressed |

Migrating to **Traefik** with the **file provider** addresses all of these risks: Traefik is actively maintained, has a strong roadmap, and supports modern traffic management patterns without depending on the deprecated `Ingress` API.

---

## Why Choose Traefik

| Capability | Traefik | NGINX Ingress |
|---|---|---|
| **Active maintenance** | ✅ Actively developed by Traefik Labs | ⚠️ Entering retirement |
| **Zero-downtime config reload** | ✅ Native hot reload via provider watch | ❌ Requires reload signal |
| **Built-in dashboard** | ✅ Web UI showing all routers, middlewares, services | ❌ Not available |
| **Middleware as code** | ✅ `Middleware` CRDs — reusable, version-controlled | ❌ Inline annotations per Ingress resource |
| **Multiple config sources** | ✅ File, CRD, Docker, Consul, etc. — composable | ❌ Only Kubernetes Ingress API |
| **Traffic splitting / canary** | ✅ Native weighted round-robin | ❌ Requires external tooling |
| **Observability** | ✅ Built-in metrics (Prometheus), tracing (OpenTelemetry), access logs | ⚠️ Limited, via annotations |
| **TLS automation** | ✅ Let's Encrypt / ACME built in | ❌ External cert-manager required |
| **No Ingress API dependency** | ✅ File provider routes bypass the deprecated Ingress API | ❌ Tightly coupled to `networking.k8s.io/v1 Ingress` |

---

## Key Differences

Before starting the migration, ensure the following are in place:

| Requirement | Details |
|---|---|
| AKS / Kubernetes Cluster | Version 1.24 or later |
| kubectl | Configured to target the cluster |
| Helm | Version 3.x |
| Cluster Admin permissions | Required to install/remove cluster-wide controllers |
| Existing NGINX | Installed via Helm (`ingress-nginx` chart) |
| Backed-up NGINX config | Export existing NGINX configuration before starting |

---

## Key Differences

| Feature | NGINX | Traefik (file provider) |
|---|---|---|
| Route definitions | `nginx.conf` / ConfigMap snippets | File provider YAML (`http.routers`) mounted as a ConfigMap |
| Traffic transformations | `nginx.conf` directives / annotations | `Middleware` CRDs (`stripPrefix`, `replacePathRegex`, `headers`, etc.) |
| CORS | `add_header` directives | `headers` Middleware CRD |
| URL rewrites | `rewrite` / `proxy_pass` directives | `replacePathRegex` or `stripPrefix` Middleware CRD |
| TLS termination | `ssl_certificate` directives | `tls` block in file provider router, cert from Kubernetes Secret |
| Dashboard | Not built-in | Built-in web UI on port `8080` |
| Hot reload | Requires NGINX reload signal | Traefik watches the ConfigMap and reloads automatically |

---

## Routing Architecture

```
                  ┌──────────────────────────────────────────────┐
                  │               Traefik Pod                    │
                  │                                              │
  Client Request  │  ┌──────────────┐    ┌────────────────────┐ │
 ───────────────▶ │  │   Router     │───▶│   Middleware Chain  │ │
                  │  │ (file        │    │  (Middleware CRDs:  │ │
                  │  │  provider)   │    │   rewrite, CORS,    │ │
                  │  └──────────────┘    │   redirect, etc.)   │ │
                  │         │            └────────────────────┘ │
                  │         │ dynamic config                      │
                  │  ┌──────┴──────────────────────────────────┐ │
                  │  │  ConfigMap: traefik-dynamic-config       │ │
                  │  └─────────────────────────────────────────┘ │
                  └────────────────────────┬─────────────────────┘
                                           │
                                           ▼
                              ┌─────────────────────┐
                              │  Kubernetes Service  │
                              │  (ClusterIP)         │
                              └─────────────────────┘
```

**Key points:**
- Routers and backend services are declared in a **file provider** ConfigMap (Traefik dynamic configuration).
- Middlewares are declared as **`Middleware` CRDs** and referenced by name from the file provider config.
- `Ingress` resources are optional and can be enabled through `providers.kubernetesIngress.enabled=true`.
- `IngressRoute` and Gateway API resources are not required for this setup.

---

## Traefik Middlewares

`Middleware` CRDs are applied to named routers inside the file provider configuration. Define each middleware in its own manifest and apply it to the cluster.

### Using Middleware with Kubernetes Ingress Annotations (Optional)

> Our production setup uses the **file provider** (not `Ingress` resources). This section is for teams that also enable Traefik's `kubernetesIngress` provider.

You can attach one or more `Middleware` CRDs to an `Ingress` by using the `traefik.ingress.kubernetes.io/router.middlewares` annotation:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  namespace: production
  annotations:
    kubernetes.io/ingress.class: traefik
    traefik.ingress.kubernetes.io/router.middlewares: production-rewrite-api-path@kubernetescrd,production-cors-headers@kubernetescrd
spec:
  rules:
    - host: my-app.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: my-app-service
                port:
                  number: 80
```

#### Annotation Pattern Breakdown

Pattern:

```text
traefik.ingress.kubernetes.io/router.middlewares: <namespace>-<middleware-name>@kubernetescrd[,<namespace>-<middleware-name>@kubernetescrd...]
```

Parts:
- `traefik.ingress.kubernetes.io/router.middlewares` — Traefik annotation key used to bind middleware chain to the Ingress router.
- `<namespace>` — Kubernetes namespace where the `Middleware` CRD exists.
- `-` — required separator between namespace and middleware resource name.
- `<middleware-name>` — value from `metadata.name` of the `Middleware` CRD.
- `@kubernetescrd` — provider suffix telling Traefik the middleware comes from CRDs.
- `,` — optional separator for multiple middlewares, applied left-to-right.

### URL Rewrite Rules

#### Strip a Path Prefix

Removes a leading path segment before forwarding to the backend.

**NGINX equivalent (`nginx.conf`):**
```nginx
location /api/ {
    rewrite ^/api/(.*) /$1 break;
    proxy_pass http://my-service;
}
```

**Traefik `stripPrefix` Middleware:**
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: strip-api-prefix
  namespace: <YOUR_NAMESPACE>
spec:
  stripPrefix:
    prefixes:
      - /api
```

#### Replace a Path Using a Regular Expression

Use `replacePathRegex` for pattern-based rewrites.

**NGINX equivalent:**
```nginx
rewrite ^/api(/.*)?$ $1 break;
```

**Traefik `replacePathRegex` Middleware:**
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rewrite-api-path
  namespace: <YOUR_NAMESPACE>
spec:
  replacePathRegex:
    regex: ^/api(/|$)(.*)
    replacement: /$2
```

#### Add a Path Prefix

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: add-app-prefix
  namespace: <YOUR_NAMESPACE>
spec:
  addPrefix:
    prefix: /app
```

---

### CORS Configuration

**NGINX equivalent (`nginx.conf`):**
```nginx
add_header 'Access-Control-Allow-Origin'  'https://example.com';
add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS';
add_header 'Access-Control-Allow-Headers' 'Authorization,Content-Type';
add_header 'Access-Control-Allow-Credentials' 'true';
add_header 'Access-Control-Max-Age' 1728000;
```

**Traefik `headers` Middleware:**
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: cors-headers
  namespace: <YOUR_NAMESPACE>
spec:
  headers:
    accessControlAllowOriginList:
      - "https://example.com"
    accessControlAllowMethods:
      - GET
      - POST
      - PUT
      - DELETE
      - OPTIONS
    accessControlAllowHeaders:
      - Authorization
      - Content-Type
      - X-CustomHeader
    accessControlAllowCredentials: true
    accessControlMaxAge: 1728000
    addVaryHeader: true
```

> **Note:** To allow all origins (not recommended for production), replace `accessControlAllowOriginList` with:
> ```yaml
> accessControlAllowOriginListRegex:
>   - ".*"
> ```

---

### HTTPS Redirect

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: https-redirect
  namespace: <YOUR_NAMESPACE>
spec:
  redirectScheme:
    scheme: https
    permanent: true
```

---

## File Provider — Dynamic Route Configuration

Routes are defined in a YAML file that Traefik loads via its **file provider**. In Kubernetes, this file is stored in a ConfigMap and mounted into the Traefik pod.

### Full Example

The following ConfigMap defines two routers:
- `my-app-http` — redirects HTTP to HTTPS.
- `my-app-https` — handles HTTPS traffic, rewrites the `/api` prefix, applies CORS, and forwards to the backend service.

```yaml
# traefik-dynamic-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: traefik-dynamic-config
  namespace: traefik
data:
  dynamic.yaml: |
    http:

      routers:

        my-app-http:
          rule: "Host(`my-app.example.com`)"
          entryPoints:
            - web
          middlewares:
            - <YOUR_NAMESPACE>-https-redirect@kubernetescrd
          service: my-app-service

        my-app-https:
          rule: "Host(`my-app.example.com`) && PathPrefix(`/api`)"
          entryPoints:
            - websecure
          tls:
            secretName: my-app-tls
          middlewares:
            - <YOUR_NAMESPACE>-rewrite-api-path@kubernetescrd
            - <YOUR_NAMESPACE>-cors-headers@kubernetescrd
          service: my-app-service

      services:

        my-app-service:
          loadBalancer:
            servers:
              - url: "http://my-app-service.<YOUR_NAMESPACE>.svc.cluster.local:80"
```

> **Middleware reference format:** When referencing a `Middleware` CRD from the file provider, use `<namespace>-<middleware-name>@kubernetescrd`.

---

### Referencing Middleware CRDs from the File Provider

Traefik supports mixing providers. Middlewares defined as CRDs in Kubernetes are referenced from the file provider using the `@kubernetescrd` suffix:

```yaml
middlewares:
  - production-rewrite-api-path@kubernetescrd
  - production-cors-headers@kubernetescrd
```

Alternatively, middlewares can be declared inline inside the `dynamic.yaml` ConfigMap without creating separate CRD resources:

```yaml
http:
  middlewares:

    rewrite-api-path:
      replacePathRegex:
        regex: "^/api(/|$)(.*)"
        replacement: "/$2"

    cors-headers:
      headers:
        accessControlAllowOriginList:
          - "https://example.com"
        accessControlAllowMethods:
          - GET
          - POST
          - OPTIONS
        addVaryHeader: true
```

If using inline middlewares in the file provider, reference them with the `@file` suffix:

```yaml
middlewares:
  - rewrite-api-path@file
  - cors-headers@file
```

### File Provider TLS Certificates via ConfigMap

When using custom certificates, keep TLS routing config in the file provider ConfigMap and mount cert files into the Traefik pod.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: traefik-tls-config
  namespace: traefik
data:
  tls.yaml: |
    tls:
      stores:
        default:
          defaultCertificate:
            certFile: /mnt/certs/tls.crt
            keyFile: /mnt/certs/tls.key
      certificates:
        - certFile: /mnt/certs/tls.crt
          keyFile: /mnt/certs/tls.key
```

This allows Traefik to load certificate paths from mounted files instead of embedding certificate material in Kubernetes Secrets.

---

## Applying Configuration to the Cluster

### Step 1 — Apply the Middleware CRDs

```bash
kubectl apply -f middlewares/rewrite-api-path.yaml
kubectl apply -f middlewares/cors-headers.yaml
kubectl apply -f middlewares/https-redirect.yaml
```

### Step 2 — Apply the Dynamic Config ConfigMap

```bash
kubectl apply -f traefik-dynamic-config.yaml
```

### Step 3 — Helm Values Example (Custom Cert + Ingress + File Provider)

Use Helm values like the following when you need custom TLS certificate files, Traefik file-provider config from a ConfigMap, and Kubernetes Ingress resources enabled.

```yaml
# traefik-values.yaml
providers:
  kubernetesCRD:
    enabled: true
  kubernetesIngress:
    enabled: true

ingressClass:
  enabled: true
  isDefaultClass: true

additionalVolumes:
  - name: secrets-store-inline
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: kv-agw-tls
  - name: dynamic-config
    configMap:
      name: traefik-tls-config

additionalVolumeMounts:
  - name: secrets-store-inline
    mountPath: /mnt/certs
    readOnly: true
  - name: dynamic-config
    mountPath: /dynamic
    readOnly: true

additionalArguments:
  - "--providers.file.directory=/dynamic"
  - "--providers.file.watch=true"
```

### Step 4 — Optional Ingress Resource Example

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  namespace: production
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/router.middlewares: production-rewrite-api-path@kubernetescrd,production-cors-headers@kubernetescrd
spec:
  ingressClassName: traefik
  rules:
    - host: my-app.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: my-app-service
                port:
                  number: 80
```

### Step 5 — Apply or Upgrade Traefik

```bash
kubectl apply -f traefik-dynamic-config.yaml
kubectl apply -f traefik-tls-config.yaml

helm upgrade traefik traefik/traefik \
  --namespace traefik \
  --values traefik-values.yaml

kubectl apply -f my-app-ingress.yaml
```

> **Hot reload:** With `--providers.file.watch=true`, Traefik automatically picks up changes to the ConfigMap without a restart.

---

## Application Gateway Health Checks (`/ping`)

When Azure Application Gateway is in front of Traefik, configure the backend health probe path as `/ping` instead of `/`.

Traefik's dedicated health endpoint is `/ping`, so this path is the reliable option for gateway backend health checks.

### Enable `/ping` in Traefik

If not already enabled, add the following static arguments in your Traefik Helm values:

```yaml
additionalArguments:
  - "--ping=true"
  - "--ping.entryPoint=web"
```

### Application Gateway backend probe

Set the probe path to:

```text
/ping
```

This ensures Application Gateway can consistently detect healthy Traefik backends.

---

## Installation Script

The following script automates the migration. It checks whether NGINX is installed, removes it if found, and then installs Traefik (with file provider and CRD provider enabled) via Helm.

> **Warning:** Removing NGINX will cause a brief downtime for all services that depend on it. Plan this during a maintenance window or after routing traffic away (e.g., at the DNS/load balancer level).

```bash
#!/usr/bin/env bash
# migrate-to-traefik.sh
# Migrates from NGINX to Traefik (file provider + Middleware CRDs).
# Usage:
#   NGINX_RELEASE_NAME=my-nginx TRAEFIK_NAMESPACE=traefik ./migrate-to-traefik.sh

set -euo pipefail

# ── Configurable defaults ────────────────────────────────────────────────────
NGINX_RELEASE_NAME="${NGINX_RELEASE_NAME:-ingress-nginx}"
NGINX_NAMESPACE="${NGINX_NAMESPACE:-ingress-nginx}"
TRAEFIK_RELEASE_NAME="${TRAEFIK_RELEASE_NAME:-traefik}"
TRAEFIK_NAMESPACE="${TRAEFIK_NAMESPACE:-traefik}"
TRAEFIK_CHART_VERSION="${TRAEFIK_CHART_VERSION:-}"      # leave empty for latest
DYNAMIC_CONFIG_CM="${DYNAMIC_CONFIG_CM:-traefik-dynamic-config}"  # ConfigMap name

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

check_dependencies() {
  for cmd in helm kubectl; do
    command -v "$cmd" &>/dev/null || die "'$cmd' is required but not installed."
  done
}

# ── Check if NGINX is installed ───────────────────────────────────────────────
nginx_is_installed() {
  helm status "$NGINX_RELEASE_NAME" --namespace "$NGINX_NAMESPACE" &>/dev/null
}

uninstall_nginx() {
  log "NGINX detected (release: $NGINX_RELEASE_NAME, namespace: $NGINX_NAMESPACE)."
  log "Uninstalling NGINX..."
  helm uninstall "$NGINX_RELEASE_NAME" --namespace "$NGINX_NAMESPACE"
  log "Waiting for NGINX pods to terminate..."
  kubectl wait --for=delete pod \
    --selector=app.kubernetes.io/name=ingress-nginx \
    --namespace "$NGINX_NAMESPACE" \
    --timeout=120s 2>/dev/null || true
  log "NGINX removed."
}

# ── Install Traefik ───────────────────────────────────────────────────────────
install_traefik() {
  log "Adding Traefik Helm repository..."
  helm repo add traefik https://traefik.github.io/charts
  helm repo update

  log "Creating namespace '$TRAEFIK_NAMESPACE' (if it does not exist)..."
  kubectl get namespace "$TRAEFIK_NAMESPACE" &>/dev/null \
    || kubectl create namespace "$TRAEFIK_NAMESPACE"

  # Check whether the dynamic config ConfigMap exists to mount it
  local extra_args=()
  if kubectl get configmap "$DYNAMIC_CONFIG_CM" --namespace "$TRAEFIK_NAMESPACE" &>/dev/null; then
    log "Found ConfigMap '$DYNAMIC_CONFIG_CM' — enabling file provider mount."
    extra_args+=(
      "--set" "additionalVolumes[0].name=dynamic-config"
      "--set" "additionalVolumes[0].configMap.name=${DYNAMIC_CONFIG_CM}"
      "--set" "additionalVolumeMounts[0].name=dynamic-config"
      "--set" "additionalVolumeMounts[0].mountPath=/etc/traefik/dynamic"
      "--set" "additionalVolumeMounts[0].readOnly=true"
      "--set" "additionalArguments[0]=--providers.file.directory=/etc/traefik/dynamic"
      "--set" "additionalArguments[1]=--providers.file.watch=true"
    )
  else
    warn "ConfigMap '$DYNAMIC_CONFIG_CM' not found in namespace '$TRAEFIK_NAMESPACE'."
    warn "Traefik will be installed without the file provider. Apply the ConfigMap and run 'helm upgrade' to enable it."
  fi

  local version_flag=""
  if [[ -n "$TRAEFIK_CHART_VERSION" ]]; then
    version_flag="--version $TRAEFIK_CHART_VERSION"
  fi

  log "Installing Traefik (release: $TRAEFIK_RELEASE_NAME, namespace: $TRAEFIK_NAMESPACE)..."
  # shellcheck disable=SC2086
  helm install "$TRAEFIK_RELEASE_NAME" traefik/traefik \
    --namespace "$TRAEFIK_NAMESPACE" \
    $version_flag \
    --set ingressClass.enabled=false \
    --set providers.kubernetesIngress.enabled=false \
    --set providers.kubernetesCRD.enabled=true \
    --set logs.general.level=INFO \
    "${extra_args[@]}" \
    --wait

  log "Traefik installed successfully."
}

verify_traefik() {
  log "Verifying Traefik deployment..."
  kubectl rollout status deployment/"$TRAEFIK_RELEASE_NAME" \
    --namespace "$TRAEFIK_NAMESPACE" \
    --timeout=120s
  log "Traefik is running."

  local lb_ip
  lb_ip=$(kubectl get svc "$TRAEFIK_RELEASE_NAME" \
    --namespace "$TRAEFIK_NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  log "Traefik LoadBalancer IP: ${lb_ip:-pending (may take a few minutes)}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  check_dependencies

  if nginx_is_installed; then
    uninstall_nginx
  else
    warn "NGINX not found (release '$NGINX_RELEASE_NAME' in namespace '$NGINX_NAMESPACE'). Skipping uninstall."
  fi

  if helm status "$TRAEFIK_RELEASE_NAME" --namespace "$TRAEFIK_NAMESPACE" &>/dev/null; then
    log "Traefik is already installed (release: $TRAEFIK_RELEASE_NAME). Skipping install."
  else
    install_traefik
  fi

  verify_traefik

  log "Migration complete."
  log "Next steps:"
  log "  1. Apply your Middleware CRDs:  kubectl apply -f middlewares/"
  log "  2. Apply your dynamic config:   kubectl apply -f traefik-dynamic-config.yaml"
  log "  3. Verify routes in the Traefik dashboard (kubectl port-forward -n $TRAEFIK_NAMESPACE svc/$TRAEFIK_RELEASE_NAME 8080:8080)"
}

main "$@"
```

### Script Usage

```bash
# Make the script executable
chmod +x migrate-to-traefik.sh

# Run with defaults
./migrate-to-traefik.sh

# Override release names or namespaces via environment variables
NGINX_RELEASE_NAME=my-nginx \
NGINX_NAMESPACE=ingress \
TRAEFIK_NAMESPACE=traefik-system \
TRAEFIK_CHART_VERSION=28.3.0 \
DYNAMIC_CONFIG_CM=traefik-routes \
./migrate-to-traefik.sh
```

### What the Script Does

1. **Checks dependencies** — verifies `helm` and `kubectl` are available.
2. **Detects NGINX** — uses `helm status` to check whether the NGINX release exists in the expected namespace.
3. **Uninstalls NGINX** — if found, runs `helm uninstall` and waits for pods to terminate.
4. **Installs Traefik** — adds the official Helm repo, creates the namespace if needed, and installs Traefik with:
   - **Kubernetes CRD provider** enabled (for `Middleware` CRDs).
   - **Kubernetes Ingress provider disabled by default** in this migration script.
   - **File provider** mounted from the `traefik-dynamic-config` ConfigMap (if it exists in the namespace).
5. **Verifies deployment** — waits for the rollout to complete and reports the LoadBalancer IP.

> If you need Ingress resources and custom certificate file mounting, use the Helm values pattern in **Step 3** of the previous section.

---

## Verification

After migration, verify that Traefik is routing traffic correctly.

### Check Traefik pods

```bash
kubectl get pods -n traefik
```

### Confirm file provider is loaded

```bash
kubectl logs -n traefik -l app.kubernetes.io/name=traefik | grep -i "file provider\|dynamic"
```

### Verify custom certificate files are mounted

```bash
kubectl exec -n traefik deploy/traefik -- ls /mnt/certs
```

### Verify Ingress resources are picked up (if enabled)

```bash
kubectl get ingress -A
kubectl logs -n traefik -l app.kubernetes.io/name=traefik | grep -i ingress
```

### Access the Traefik dashboard

By default, the dashboard is available on port `8080`. Forward it locally:

```bash
kubectl port-forward -n traefik svc/traefik 8080:8080
```

Open `http://localhost:8080/dashboard/` in your browser. The **HTTP → Routers** tab shows all routes loaded from the file provider.

### Verify Middleware CRDs are registered

```bash
kubectl get middleware --all-namespaces
```

### Check Traefik logs for routing or middleware errors

```bash
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=100
```

---

## Rollback Procedure

If issues are encountered, roll back to NGINX:

```bash
# 1. Uninstall Traefik
helm uninstall traefik --namespace traefik

# 2. Re-add the ingress-nginx Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# 3. Reinstall NGINX
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace

# 4. Restore NGINX configuration
kubectl apply -f nginx-config-backup.yaml
```

---

## Troubleshooting

### Routes Not Appearing in the Dashboard

- Confirm the dynamic config ConfigMap is mounted correctly:
  ```bash
  kubectl exec -n traefik deploy/traefik -- ls /dynamic
  ```
- Confirm the file provider argument is set:
  ```bash
  kubectl exec -n traefik deploy/traefik -- traefik version
  kubectl get deploy traefik -n traefik -o jsonpath='{.spec.template.spec.containers[0].args}'
  ```
- Check for YAML parse errors in the Traefik logs:
  ```bash
  kubectl logs -n traefik -l app.kubernetes.io/name=traefik | grep -i "error\|warn"
  ```

### Middleware Not Applied

- Verify the Middleware CRD exists in the correct namespace:
  ```bash
  kubectl get middleware -n <YOUR_NAMESPACE>
  ```
- Confirm the reference format from the file provider uses `<namespace>-<name>@kubernetescrd`:
  ```yaml
  middlewares:
    - production-cors-headers@kubernetescrd
  ```
- If using Kubernetes `Ingress` annotations, confirm the same pattern in `traefik.ingress.kubernetes.io/router.middlewares`:
  ```yaml
  traefik.ingress.kubernetes.io/router.middlewares: production-rewrite-api-path@kubernetescrd,production-cors-headers@kubernetescrd
  ```
- Common annotation mistakes:
  - Using `/` instead of `-` between namespace and middleware name.
  - Missing `@kubernetescrd` suffix.
  - Referencing a middleware from the wrong namespace.
  - Adding spaces around commas in middleware chains.
- If using inline file provider middlewares, use `@file` instead:
  ```yaml
  middlewares:
    - cors-headers@file
  ```
- Check Traefik logs for middleware errors:
  ```bash
  kubectl logs -n traefik -l app.kubernetes.io/name=traefik | grep -i middleware
  ```

### Custom Certificate Not Applied

- Verify certificate files exist in the pod:
  ```bash
  kubectl exec -n traefik deploy/traefik -- ls /mnt/certs
  ```
- Verify the TLS file-provider ConfigMap is mounted:
  ```bash
  kubectl exec -n traefik deploy/traefik -- ls /dynamic
  ```
- Verify `tls.yaml` points to valid cert and key file paths:
  ```yaml
  tls:
    certificates:
      - certFile: /mnt/certs/tls.crt
        keyFile: /mnt/certs/tls.key
  ```
- Check logs for certificate load errors:
  ```bash
  kubectl logs -n traefik -l app.kubernetes.io/name=traefik | grep -i "tls\|certificate\|x509"
  ```

### CORS Errors in Browser

- Ensure `addVaryHeader: true` is set in the `headers` Middleware.
- For preflight (`OPTIONS`) requests, verify the backend service handles `OPTIONS` and that a `stripPrefix` / `replacePathRegex` middleware is not stripping path segments that the backend needs.
- Confirm the allowed origins list exactly matches the requesting origin (scheme, hostname, and port).

### 404 After Path Rewrite

- Check whether `replacePathRegex` or `stripPrefix` is removing too much of the path.
- Enable Traefik debug logs temporarily to trace the rewritten path:
  ```bash
  helm upgrade traefik traefik/traefik \
    --namespace traefik \
    --reuse-values \
    --set logs.general.level=DEBUG
  ```

### LoadBalancer IP Stuck in `<pending>`

- In AKS, ensure the cluster has the ability to provision a public or internal load balancer.
- Check events on the Traefik service:
  ```bash
  kubectl describe svc traefik -n traefik
  ```

---

## References

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Traefik File Provider Documentation](https://doc.traefik.io/traefik/providers/file/)
- [Traefik Middleware Reference](https://doc.traefik.io/traefik/middlewares/overview/)
- [Traefik Headers Middleware (CORS)](https://doc.traefik.io/traefik/middlewares/http/headers/)
- [Traefik StripPrefix Middleware](https://doc.traefik.io/traefik/middlewares/http/stripprefix/)
- [Traefik ReplacePathRegex Middleware](https://doc.traefik.io/traefik/middlewares/http/replacepathregex/)
- [Traefik Routers (HTTP)](https://doc.traefik.io/traefik/routing/routers/)
- [Traefik Helm Chart](https://github.com/traefik/traefik-helm-chart)
- [Traefik Kubernetes CRD Provider](https://doc.traefik.io/traefik/providers/kubernetes-crd/)
- [Traefik Kubernetes Ingress Provider](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)
- [Traefik TLS Certificates](https://doc.traefik.io/traefik/https/tls/)
- [NGINX Ingress Controller — End of Life Announcement](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes Gateway API (replacement for Ingress)](https://gateway-api.sigs.k8s.io/)
- [Kubernetes Ingress API — Legacy Status](https://kubernetes.io/docs/concepts/services-networking/ingress/)
