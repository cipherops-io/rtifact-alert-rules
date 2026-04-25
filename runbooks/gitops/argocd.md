# Runbook: ArgoCD

ArgoCD is a GitOps continuous-delivery tool for Kubernetes.

## ArgoCDDown

An ArgoCD component (server, repo-server, application-controller, dex, redis) is unreachable.

```bash
kubectl -n argocd get pods
kubectl -n argocd describe pod $POD
kubectl -n argocd logs $POD
```

If `argocd-server` is down → UI/CLI unavailable, but reconciliation continues.
If `argocd-application-controller` is down → no reconciliation; see `ArgoCDAppControllerCrashLoop`.
If `argocd-repo-server` is down → all syncs blocked; see `ArgoCDRepoServerDown`.

## ArgoCDAppOutOfSync

An application has been OutOfSync for >10 minutes. Either someone made a manual cluster change, or a sync is failing.

```bash
argocd app diff $APP
argocd app sync $APP --dry-run
```

## ArgoCDAppDegraded

The application's resources report an unhealthy state. Inspect:

```bash
argocd app get $APP
kubectl -n $TARGET_NS describe deployment $APP
```

## ArgoCDSyncFailed

Last sync failed. Look at the operation result:

```bash
argocd app get $APP -o yaml | yq .status.operationState
```

Common: pre-sync hook failed, manifests invalid, RBAC denied apply.

## ArgoCDAppSyncRunningLong / ArgoCDPendingHookLong

Sync has been running for >10 (or >15) minutes. A pre/post-sync hook is likely stuck. Check the hook job:

```bash
argocd app get $APP -o yaml | yq .status.operationState.syncResult
kubectl -n $TARGET_NS get jobs -l app.kubernetes.io/instance=$APP
```

To force-terminate:

```bash
argocd app terminate-op $APP
```

## ArgoCDRepoServerDown

repo-server clones git repos and renders manifests. Without it, no syncs work. Often OOM-killed on large repos. Increase memory limit.

## ArgoCDRepoUnreachable

ArgoCD cannot reach a configured git repo. Check credentials and network:

```bash
argocd repo list
argocd repo get $REPO_URL
# Test connectivity from inside the repo-server pod:
kubectl -n argocd exec -it deploy/argocd-repo-server -- git ls-remote $REPO_URL
```

## ArgoCDAppControllerCrashLoop

Total failure of GitOps reconciliation. Check logs and recent commits to argocd-cm.

## ArgoCDCertificateExpiring

A repository TLS cert is expiring. Either renew the cert at the source or update the cert pin in argocd.

## ArgoCDAppHealthUnknown

Health resource is missing custom health check or the app is in a state ArgoCD doesn't recognize. Often happens with custom CRDs without health-check Lua scripts.

## ArgoCDDexDown / ArgoCDRedisDown

Dex = SSO provider. Dex down → SSO login broken, local admin still works.
Redis = session/UI cache. Redis down → UI slow, but reconciliation continues.

## References

- [ArgoCD operator manual](https://argo-cd.readthedocs.io/en/stable/operator-manual/)
- [ArgoCD troubleshooting](https://argo-cd.readthedocs.io/en/stable/operator-manual/troubleshooting/)
