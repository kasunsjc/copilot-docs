# Migrating from NGINX Ingress to Traefik Ingress

## Overview

This document describes the process of migrating from **NGINX Ingress Controller** to **Traefik Ingress Controller** in a Kubernetes environment. It covers the key differences in configuration, how to map NGINX annotations to Traefik middlewares (including URL rewrite rules and CORS), and the automated installation script that handles the transition safely.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Key Differences](#key-differences)
3. [Annotation Mapping Reference](#annotation-mapping-reference)
4. [Traefik Middlewares](#traefik-middlewares)
   - [URL Rewrite Rules](#url-rewrite-rules)
   - [CORS Configuration](#cors-configuration)
   - [Combining Middlewares](#combining-middlewares)
5. [Ingress Resource Migration](#ingress-resource-migration)
6. [Installation Script](#installation-script)
7. [Verification](#verification)
8. [Rollback Procedure](#rollback-procedure)
9. [Troubleshooting](#troubleshooting)
10. [References](#references)

---

## Prerequisites

Before starting the migration, ensure the following are in place:

| Requirement | Details |
|---|---|
| AKS / Kubernetes Cluster | Version 1.24 or later |
| kubectl | Configured to target the cluster |
| Helm | Version 3.x |
| Cluster Admin permissions | Required to install/remove cluster-wide controllers |
| Existing NGINX Ingress | Installed via Helm (`ingress-nginx` chart) |
| Backed-up Ingress manifests | Export all current Ingress resources before starting |

Back up all existing Ingress resources before proceeding:

```bash
kubectl get ingress --all-namespaces -o yaml > ingress-backup.yaml
```

---

## Key Differences

| Feature | NGINX Ingress | Traefik Ingress |
|---|---|---|
| Configuration method | Annotations on Ingress resources | `Middleware` CRDs referenced in Ingress annotations |
| URL rewrites | `nginx.ingress.kubernetes.io/rewrite-target` | `TraefikService` or `stripPrefix` / `replacePathRegex` Middlewares |
| CORS | `nginx.ingress.kubernetes.io/enable-cors` + related annotations | `headers` Middleware with CORS fields |
| Rate limiting | `nginx.ingress.kubernetes.io/limit-rps` | `rateLimit` Middleware |
| Authentication | `nginx.ingress.kubernetes.io/auth-*` | `basicAuth` / `forwardAuth` Middleware |
| Dashboard | Not built-in | Built-in web UI on port `8080` (configurable) |
| TCP/UDP routing | Separate ConfigMap | Native `IngressRouteTCP` / `IngressRouteUDP` CRDs |

---

## Annotation Mapping Reference

The table below maps the most common NGINX annotations to their Traefik equivalents.

| NGINX Annotation | Traefik Equivalent |
|---|---|
| `nginx.ingress.kubernetes.io/rewrite-target: /` | `replacePathRegex` or `stripPrefix` Middleware |
| `nginx.ingress.kubernetes.io/use-regex: "true"` | Native regex support in Traefik router rules |
| `nginx.ingress.kubernetes.io/enable-cors: "true"` | `headers` Middleware with `accessControlAllowOriginList` |
| `nginx.ingress.kubernetes.io/cors-allow-methods` | `accessControlAllowMethods` in `headers` Middleware |
| `nginx.ingress.kubernetes.io/cors-allow-headers` | `accessControlAllowHeaders` in `headers` Middleware |
| `nginx.ingress.kubernetes.io/proxy-body-size` | `buffering` Middleware with `maxRequestBodyBytes` |
| `nginx.ingress.kubernetes.io/ssl-redirect: "true"` | `redirectScheme` Middleware |
| `nginx.ingress.kubernetes.io/limit-rps` | `rateLimit` Middleware |
| `nginx.ingress.kubernetes.io/auth-type: basic` | `basicAuth` Middleware |
| `nginx.ingress.kubernetes.io/auth-url` | `forwardAuth` Middleware |
| `nginx.ingress.kubernetes.io/configuration-snippet` | Inline Middleware (no direct equivalent — use specific Middleware types) |

---

## Traefik Middlewares

Traefik uses `Middleware` Custom Resources (CRDs) to handle request/response transformations. Middlewares are defined independently and then referenced in Ingress annotations or `IngressRoute` resources.

### URL Rewrite Rules

#### Strip a Path Prefix

Use the `stripPrefix` middleware to remove a path prefix before forwarding the request to the backend.

**NGINX equivalent:**
```yaml
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /
  nginx.ingress.kubernetes.io/use-regex: "true"
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

Use `replacePathRegex` for more complex rewrite rules.

**NGINX equivalent:**
```yaml
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /$2
  nginx.ingress.kubernetes.io/use-regex: "true"
# path: /api(/|$)(.*)
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

**NGINX equivalent:**
```yaml
annotations:
  nginx.ingress.kubernetes.io/enable-cors: "true"
  nginx.ingress.kubernetes.io/cors-allow-origin: "https://example.com"
  nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, DELETE, OPTIONS"
  nginx.ingress.kubernetes.io/cors-allow-headers: "DNT,X-CustomHeader,Keep-Alive,User-Agent,Authorization,Content-Type"
  nginx.ingress.kubernetes.io/cors-allow-credentials: "true"
  nginx.ingress.kubernetes.io/cors-max-age: "1728000"
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
      - DNT
      - X-CustomHeader
      - Keep-Alive
      - User-Agent
      - Authorization
      - Content-Type
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

### Combining Middlewares

Multiple middlewares can be applied to a single Ingress by listing them in the annotation, separated by commas.

**Ingress resource referencing multiple middlewares:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: <YOUR_NAMESPACE>
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: >-
      <YOUR_NAMESPACE>-strip-api-prefix@kubernetescrd,
      <YOUR_NAMESPACE>-cors-headers@kubernetescrd
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

> **Important:** Middleware references in annotations follow the format `<namespace>-<middleware-name>@kubernetescrd`.

---

## Ingress Resource Migration

### Before (NGINX)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: production
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://example.com"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, OPTIONS"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  rules:
    - host: my-app.example.com
      http:
        paths:
          - path: /api(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: my-app-service
                port:
                  number: 80
```

### After (Traefik)

**Step 1 — Create the Middlewares:**

```yaml
# rewrite-middleware.yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rewrite-api-path
  namespace: production
spec:
  replacePathRegex:
    regex: ^/api(/|$)(.*)
    replacement: /$2
---
# cors-middleware.yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: cors-headers
  namespace: production
spec:
  headers:
    accessControlAllowOriginList:
      - "https://example.com"
    accessControlAllowMethods:
      - GET
      - POST
      - OPTIONS
    accessControlAllowCredentials: false
    addVaryHeader: true
---
# redirect-middleware.yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: https-redirect
  namespace: production
spec:
  redirectScheme:
    scheme: https
    permanent: true
```

**Step 2 — Apply the Middlewares:**

```bash
kubectl apply -f rewrite-middleware.yaml
kubectl apply -f cors-middleware.yaml
kubectl apply -f redirect-middleware.yaml
```

**Step 3 — Update the Ingress resource:**

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: production
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: >-
      production-rewrite-api-path@kubernetescrd,
      production-cors-headers@kubernetescrd,
      production-https-redirect@kubernetescrd
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - my-app.example.com
      secretName: my-app-tls
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

```bash
kubectl apply -f ingress.yaml
```

---

## Installation Script

The following script automates the migration. It checks whether NGINX Ingress is installed, removes it if found, and then installs Traefik via Helm.

> **Warning:** Removing NGINX Ingress will cause a brief downtime for all services that depend on it. Plan this during a maintenance window or after routing traffic away (e.g., at the DNS/load balancer level).

```bash
#!/usr/bin/env bash
# migrate-ingress.sh
# Migrates from NGINX Ingress Controller to Traefik Ingress Controller.
# Usage: ./migrate-ingress.sh [--namespace <ns>] [--traefik-version <version>]

set -euo pipefail

# ── Configurable defaults ────────────────────────────────────────────────────
NGINX_RELEASE_NAME="${NGINX_RELEASE_NAME:-ingress-nginx}"
NGINX_NAMESPACE="${NGINX_NAMESPACE:-ingress-nginx}"
TRAEFIK_RELEASE_NAME="${TRAEFIK_RELEASE_NAME:-traefik}"
TRAEFIK_NAMESPACE="${TRAEFIK_NAMESPACE:-traefik}"
TRAEFIK_CHART_VERSION="${TRAEFIK_CHART_VERSION:-}"   # leave empty for latest

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

check_dependencies() {
  for cmd in helm kubectl; do
    command -v "$cmd" &>/dev/null || die "'$cmd' is required but not installed."
  done
}

# ── Check if NGINX Ingress is installed ──────────────────────────────────────
nginx_is_installed() {
  helm status "$NGINX_RELEASE_NAME" --namespace "$NGINX_NAMESPACE" &>/dev/null
}

uninstall_nginx() {
  log "NGINX Ingress Controller detected (release: $NGINX_RELEASE_NAME, namespace: $NGINX_NAMESPACE)."
  log "Uninstalling NGINX Ingress Controller..."
  helm uninstall "$NGINX_RELEASE_NAME" --namespace "$NGINX_NAMESPACE"
  log "Waiting for NGINX pods to terminate..."
  kubectl wait --for=delete pod \
    --selector=app.kubernetes.io/name=ingress-nginx \
    --namespace "$NGINX_NAMESPACE" \
    --timeout=120s 2>/dev/null || true
  log "NGINX Ingress Controller removed."
}

# ── Install Traefik ───────────────────────────────────────────────────────────
install_traefik() {
  log "Adding Traefik Helm repository..."
  helm repo add traefik https://traefik.github.io/charts
  helm repo update

  log "Creating namespace '$TRAEFIK_NAMESPACE' (if it does not exist)..."
  kubectl get namespace "$TRAEFIK_NAMESPACE" &>/dev/null \
    || kubectl create namespace "$TRAEFIK_NAMESPACE"

  local version_flag=""
  if [[ -n "$TRAEFIK_CHART_VERSION" ]]; then
    version_flag="--version $TRAEFIK_CHART_VERSION"
  fi

  log "Installing Traefik (release: $TRAEFIK_RELEASE_NAME, namespace: $TRAEFIK_NAMESPACE)..."
  # shellcheck disable=SC2086
  helm install "$TRAEFIK_RELEASE_NAME" traefik/traefik \
    --namespace "$TRAEFIK_NAMESPACE" \
    $version_flag \
    --set ingressClass.enabled=true \
    --set ingressClass.isDefaultClass=true \
    --set providers.kubernetesIngress.enabled=true \
    --set providers.kubernetesCRD.enabled=true \
    --set logs.general.level=INFO \
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
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
  log "Traefik LoadBalancer IP: ${lb_ip:-pending (may take a few minutes)}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  check_dependencies

  if nginx_is_installed; then
    uninstall_nginx
  else
    warn "NGINX Ingress Controller not found (release '$NGINX_RELEASE_NAME' in namespace '$NGINX_NAMESPACE'). Skipping uninstall."
  fi

  if helm status "$TRAEFIK_RELEASE_NAME" --namespace "$TRAEFIK_NAMESPACE" &>/dev/null; then
    log "Traefik is already installed (release: $TRAEFIK_RELEASE_NAME). Skipping install."
  else
    install_traefik
  fi

  verify_traefik

  log "Migration complete. Update your Ingress resources to use 'ingressClassName: traefik' and replace NGINX annotations with Traefik Middlewares."
}

main "$@"
```

### Script Usage

```bash
# Make the script executable
chmod +x migrate-ingress.sh

# Run with defaults
./migrate-ingress.sh

# Override release names or namespaces via environment variables
NGINX_RELEASE_NAME=my-nginx \
NGINX_NAMESPACE=ingress \
TRAEFIK_NAMESPACE=traefik-system \
TRAEFIK_CHART_VERSION=28.3.0 \
./migrate-ingress.sh
```

### What the Script Does

1. **Checks dependencies** — verifies `helm` and `kubectl` are available.
2. **Detects NGINX** — uses `helm status` to check whether the NGINX Ingress release exists in the expected namespace.
3. **Uninstalls NGINX** — if found, runs `helm uninstall` and waits for pods to terminate.
4. **Installs Traefik** — adds the official Helm repo, creates the namespace if needed, and installs Traefik with Kubernetes Ingress and CRD providers enabled and set as the default IngressClass.
5. **Verifies deployment** — waits for the rollout to complete and reports the LoadBalancer IP.

---

## Verification

After migration, verify that Traefik is routing traffic correctly.

### Check Traefik pods

```bash
kubectl get pods -n traefik
```

### Check the IngressClass

```bash
kubectl get ingressclass
# Expected output includes traefik as the default class
```

### Check Traefik is picking up Ingress resources

```bash
kubectl get ingress --all-namespaces
```

### Access the Traefik dashboard

By default, the dashboard is available on port `8080` of the Traefik pod. Forward it locally:

```bash
kubectl port-forward -n traefik $(kubectl get pods -n traefik -o name | head -1) 8080:8080
```

Open `http://localhost:8080/dashboard/` in your browser.

### Verify Middleware is applied

```bash
kubectl get middleware --all-namespaces
```

Check the Traefik logs for any routing or middleware errors:

```bash
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=100
```

---

## Rollback Procedure

If issues are encountered, roll back to NGINX Ingress:

```bash
# 1. Uninstall Traefik
helm uninstall traefik --namespace traefik

# 2. Re-add the ingress-nginx Helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# 3. Reinstall NGINX Ingress
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace

# 4. Restore Ingress resources from backup
kubectl apply -f ingress-backup.yaml
```

---

## Troubleshooting

### Middleware Not Applied

- Verify the Middleware exists in the correct namespace:
  ```bash
  kubectl get middleware -n <YOUR_NAMESPACE>
  ```
- Confirm the annotation format uses `<namespace>-<name>@kubernetescrd`:
  ```yaml
  traefik.ingress.kubernetes.io/router.middlewares: production-cors-headers@kubernetescrd
  ```
- Check Traefik logs for middleware errors:
  ```bash
  kubectl logs -n traefik -l app.kubernetes.io/name=traefik | grep -i middleware
  ```

### CORS Errors in Browser

- Ensure `addVaryHeader: true` is set in the `headers` Middleware.
- For preflight (`OPTIONS`) requests, verify the backend service handles `OPTIONS` or that a `stripPrefix` middleware is not accidentally stripping needed path segments.
- Confirm the allowed origins list exactly matches the requesting origin (scheme, hostname, and port).

### 404 After Path Rewrite

- Check whether `replacePathRegex` or `stripPrefix` is removing too much of the path.
- Enable Traefik debug logs temporarily to trace the rewritten path:
  ```bash
  helm upgrade traefik traefik/traefik \
    --namespace traefik \
    --set logs.general.level=DEBUG
  ```

### `ingressClassName` Not Recognised

- Confirm the `IngressClass` resource exists:
  ```bash
  kubectl get ingressclass traefik
  ```
- If not present, ensure Traefik was installed with `--set ingressClass.enabled=true`.

### LoadBalancer IP Stuck in `<pending>`

- In AKS, ensure the cluster has the ability to provision a public or internal load balancer.
- Check events on the Traefik service:
  ```bash
  kubectl describe svc traefik -n traefik
  ```

---

## References

- [Traefik Kubernetes Ingress Documentation](https://doc.traefik.io/traefik/providers/kubernetes-ingress/)
- [Traefik Middleware Reference](https://doc.traefik.io/traefik/middlewares/overview/)
- [Traefik Headers Middleware (CORS)](https://doc.traefik.io/traefik/middlewares/http/headers/)
- [Traefik StripPrefix Middleware](https://doc.traefik.io/traefik/middlewares/http/stripprefix/)
- [Traefik ReplacePathRegex Middleware](https://doc.traefik.io/traefik/middlewares/http/replacepathregex/)
- [Traefik Helm Chart](https://github.com/traefik/traefik-helm-chart)
- [NGINX Ingress Controller Annotations](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
- [Kubernetes IngressClass](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-class)
