# Lab 3 — Gateway API: Path & Subdomain Routing

## Before this lab

```bash
# Verify Gateway API CRDs are installed
kubectl get crd gateways.gateway.networking.k8s.io

# Verify NGINX Gateway Fabric is running
kubectl get pods -n nginx-gateway
kubectl get gatewayclass

# Set your name if you haven't already
export STUDENT_NAME=yourname
```

---

## What is this lab about?

You'll achieve the same routing as Lab 1 — path-based and subdomain-based — but using **Gateway API** instead of Ingress. The end result is the same URLs:

```
http://YOURNAME.eks.ironlabs.online/blue   → Blue app
http://YOURNAME.eks.ironlabs.online/green  → Green app
http://blue.YOURNAME.eks.ironlabs.online   → Blue app
http://green.YOURNAME.eks.ironlabs.online  → Green app
```

The difference is in how you define the routing and who owns each piece.

---

## Concepts

### Why Gateway API? What's wrong with Ingress?

You just used Ingress in Labs 1 and 2. Here's what you might have noticed:

**Non-standard features need non-standard annotations.** In Lab 1 you used `nginx.ingress.kubernetes.io/rewrite-target: /` to strip the path prefix. That annotation is specific to NGINX. If you switch to Traefik, AWS ALB, or any other Ingress controller, that annotation doesn't exist — you rewrite all your YAML.

**There's no role separation.** In a real company, the team that manages infrastructure (which load balancers exist, which TLS policies apply) and the team that deploys applications (which paths route to which services) are often different people. With Ingress, they both touch the same resource type. There's no clean boundary.

**The API stops at HTTP/HTTPS.** gRPC, TCP, UDP, traffic splitting for canary deployments — none of these are in the Ingress spec. They require proprietary annotations or separate CRDs.

**Gateway API** was designed by Kubernetes SIG Network to fix all of this. It's been stable (v1) since Kubernetes 1.28 and is now implemented by NGINX, Envoy, Cilium, Istio, AWS, GKE, and every other major Kubernetes networking vendor.

### The role-oriented model

Gateway API splits routing into three resources, each with a clear owner:

```
GatewayClass  ─── Platform/Infrastructure team
                  "Which controller handles traffic? NGINX Gateway Fabric."
                  Created once per cluster. You don't touch this.
      │
      ▼
  Gateway  ─── Cluster Admin (or you, since it's your cluster)
               "I want an entry point on port 80 accepting traffic
                for my hostnames."
                One Gateway per lab, you create this.
      │
      ▼
  HTTPRoute  ─── Application Developer
                 "Route /blue to app-blue, /green to app-green."
                 One or more per app, you create these.
```

In a company with a shared cluster, this separation means developers can manage their own HTTPRoutes without getting access to infrastructure-level resources. On your own cluster it's all you, but understanding the model matters for how production systems are structured.

### HTTPRoute vs Ingress: same goal, different API

| Concept | Ingress | HTTPRoute |
|---------|---------|-----------|
| Path prefix strip | `nginx.ingress.kubernetes.io/rewrite-target: /` | `URLRewrite` filter — standardized |
| Host matching | `spec.rules[].host` | `spec.hostnames[]` |
| Portability | NGINX-specific annotations | Same syntax on every implementation |
| Traffic splitting | Not supported | `backendRefs` with `weight` field |

### How external-dns works with Gateway API

In Lab 1, external-dns read hostnames from the Ingress `spec.rules[].host` field. With Gateway API, there's no equivalent — HTTPRoutes don't trigger DNS by themselves. Instead, you add an annotation to the **Gateway** listing the hostnames you want DNS records for. external-dns reads the annotation and creates the records when the Gateway gets an address.

---

## Step-by-step

### Step 1 — Set your name

```bash
export STUDENT_NAME=yourname
```

### Step 2 — Deploy the two apps

```bash
kubectl apply -f apps.yaml
```

Creates the `lab3` namespace plus the same blue/green apps as Lab 1. No `envsubst` needed.

```bash
kubectl get pods -n lab3
```

---

### Step 3 — Create the Gateway

The Gateway is your entry point. It tells NGINX Gateway Fabric: "create a listener on port 80, accept routes from this namespace."

```bash
envsubst < gateway.yaml | kubectl apply -f -
```

The Gateway YAML (in `gateway.yaml`):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
  namespace: lab3
  annotations:
    # Tell external-dns which DNS records to create for this Gateway.
    # external-dns creates a CNAME for each hostname pointing at the Gateway's NLB address.
    # This is how Gateway API integrates with DNS — the Gateway, not the HTTPRoute, carries this.
    external-dns.alpha.kubernetes.io/hostname: >-
      YOUR_STUDENT_NAME.eks.ironlabs.online,
      blue.YOUR_STUDENT_NAME.eks.ironlabs.online,
      green.YOUR_STUDENT_NAME.eks.ironlabs.online
spec:
  # References the GatewayClass installed during setup.
  # This tells Kubernetes which controller (NGINX Gateway Fabric) handles this Gateway.
  gatewayClassName: nginx

  listeners:
    - name: http
      port: 80
      protocol: HTTP
      # Only HTTPRoutes in the same namespace (lab3) can attach to this listener.
      # In a multi-team cluster you'd use label selectors or "All" here.
      allowedRoutes:
        namespaces:
          from: Same
```

Watch the Gateway get an address (NGINX Gateway Fabric provisions a new NLB):

```bash
watch -n5 "kubectl get gateway -n lab3"
# Wait until PROGRAMMED=True and ADDRESS is populated
```

`PROGRAMMED=True` means NGINX Gateway Fabric has configured the proxy and the NLB is ready.

---

### Step 4 — Create the HTTPRoutes

HTTPRoutes define the actual routing rules and attach to the Gateway via `parentRefs`.

```bash
envsubst < httproutes.yaml | kubectl apply -f -
```

The HTTPRoute YAML (in `httproutes.yaml`):

```yaml
# ─── Path-based routing ───────────────────────────────────────────────────────
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: path-routing
  namespace: lab3
spec:
  parentRefs:
    # Attach this route to the Gateway above.
    # The Gateway accepts or rejects routes based on its allowedRoutes config.
    - name: my-gateway
      namespace: lab3
  hostnames:
    - "YOUR_STUDENT_NAME.eks.ironlabs.online"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /blue
      filters:
        # URLRewrite strips /blue from the path before forwarding.
        # Compare to Lab 1's "nginx.ingress.kubernetes.io/rewrite-target: /"
        # Same result, but now it's a standardized Gateway API feature, not an annotation.
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplaceFullPath
              replaceFullPath: /
      backendRefs:
        - name: app-blue
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /green
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplaceFullPath
              replaceFullPath: /
      backendRefs:
        - name: app-green
          port: 80
---
# ─── Subdomain routing (blue) ─────────────────────────────────────────────────
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: subdomain-blue
  namespace: lab3
spec:
  parentRefs:
    - name: my-gateway
      namespace: lab3
  # The hostname here must match what the Gateway's listener accepts.
  # The Gateway listener has no hostname filter, so it accepts anything
  # that's in the external-dns annotation.
  hostnames:
    - "blue.YOUR_STUDENT_NAME.eks.ironlabs.online"
  rules:
    - backendRefs:
        - name: app-blue
          port: 80
---
# ─── Subdomain routing (green) ────────────────────────────────────────────────
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: subdomain-green
  namespace: lab3
spec:
  parentRefs:
    - name: my-gateway
      namespace: lab3
  hostnames:
    - "green.YOUR_STUDENT_NAME.eks.ironlabs.online"
  rules:
    - backendRefs:
        - name: app-green
          port: 80
```

Check the routes are accepted:

```bash
kubectl get httproute -n lab3

# For detail — look for Accepted: True and ResolvedRefs: True
kubectl describe httproute path-routing -n lab3
```

---

### Step 5 — Wait for DNS (~60 seconds)

```bash
watch -n5 "nslookup ${STUDENT_NAME}.eks.ironlabs.online"
```

---

### Step 6 — Test path routing

```bash
curl http://${STUDENT_NAME}.eks.ironlabs.online/blue
curl http://${STUDENT_NAME}.eks.ironlabs.online/green
```

---

### Step 7 — Test subdomain routing

```bash
curl http://blue.${STUDENT_NAME}.eks.ironlabs.online
curl http://green.${STUDENT_NAME}.eks.ironlabs.online
```

---

## Inspect route status

```bash
# The status shows which Gateway the route is attached to and whether it's healthy
kubectl get httproute path-routing -n lab3 -o yaml | grep -A 30 "status:"
```

---

## Clean up

```bash
envsubst < httproutes.yaml | kubectl delete -f -
envsubst < gateway.yaml | kubectl delete -f -
kubectl delete -f apps.yaml
```

external-dns will remove the DNS records when the Gateway annotation disappears.

---

## Key takeaways

- **GatewayClass → Gateway → HTTPRoute** maps to platform team → cluster admin → developer
- **HTTPRoute `parentRefs`** is the attachment mechanism — the Gateway must accept the route's namespace
- **`URLRewrite` filter** does what `rewrite-target` did in Lab 1, but as a standardized Gateway API feature
- **External-dns annotation on the Gateway** (not the HTTPRoute) triggers DNS record creation
- The routing result is identical to Lab 1 — the difference is in portability and role separation

When you're done, continue to [Lab 4 →](../lab4-gateway-https/README.md)
