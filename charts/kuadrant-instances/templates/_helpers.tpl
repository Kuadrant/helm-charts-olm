{{/* Restarts Kuadrant Operator if needed. Waits for Kuadrant, Limitador and Authorino CRs and patch them to enable observability (debug logging, tracing, monitoring) if desired. Also patches limitador subscription with OTEL env vars if observability is enabled. */}}
{{- define "kuadrant.post-install-helm-hook" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: post-install-helm-hook
  namespace: {{ .namespace }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: post-install-helm-hook-role
  namespace: {{ .namespace }}
rules:
- apiGroups:
  - kuadrant.io
  resources:
  - kuadrants
  verbs:
  - get
  - patch
  - list
  - watch
- apiGroups:
  - limitador.kuadrant.io
  resources:
  - limitadors
  verbs:
  - get
  - patch
  - list
  - watch
- apiGroups:
  - operator.authorino.kuadrant.io
  resources:
  - authorinos
  verbs:
  - get
  - patch
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - patch
  - delete
- apiGroups:
  - operators.coreos.com
  resources:
  - subscriptions
  verbs:
  - get
  - patch
  - list
- apiGroups:
  - apps
  resources:
  - deployments
  verbs:
  - get
  - patch
  - list
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: post-install-helm-hook-rb
  namespace: {{ .namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: post-install-helm-hook-role
subjects:
- kind: ServiceAccount
  name: post-install-helm-hook
  namespace: {{ .namespace }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: post-install-helm-hook-cluster-role
rules:
- apiGroups:
  - operator.openshift.io
  resources:
  - consoles
  verbs:
  - get
  - patch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: post-install-helm-hook-cluster-rb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: post-install-helm-hook-cluster-role
subjects:
- kind: ServiceAccount
  name: post-install-helm-hook
  namespace: {{ .namespace }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: post-install-helm-hook
  namespace: {{ .namespace }}
data:
  "run.sh": |
    #!/bin/bash
    set -xe

    # First restart Kuadrant operator if needed
    MESSAGE=$(kubectl get kuadrant kuadrant-sample --namespace {{ .namespace }} -o jsonpath='{.status.conditions[*].message}')
    if [[ "$MESSAGE" == *"please restart Kuadrant Operator pod"* ]]; then
        kubectl delete pod -l app=kuadrant --wait=true --namespace {{ .namespace }}
    fi
    kubectl wait --for=condition=Ready kuadrant kuadrant-sample --namespace {{ .namespace }} --timeout=300s

    ENABLE_OBSERVABILITY="{{ .enableObservability }}"
    # Patch limitador subscription (older Kuadrant versions) or limitador-operator
    # deployment (newer versions) with OTEL env vars if observability is enabled
    # Patch limitador and authorino CRs to enable debug logging and wait for ready status
    if [[ "$ENABLE_OBSERVABILITY" == "true" ]]; then
        LIMITADOR_SUB=$(kubectl get subscription --namespace {{ .namespace }} -o json | jq -r '.items[] | select(.spec.name=="limitador-operator") | .metadata.name')
        if [[ -n "$LIMITADOR_SUB" ]]; then
            kubectl patch subscription "$LIMITADOR_SUB" --namespace {{ .namespace }} --type merge --patch '{
              "spec": {
                "config": {
                  "env": [
                    {
                      "name": "OTEL_EXPORTER_OTLP_ENDPOINT",
                      "value": "rpc://jaeger-collector.tools.svc.cluster.local:4317"
                    },
                    {
                      "name": "OTEL_EXPORTER_OTLP_INSECURE",
                      "value": "true"
                    }
                  ]
                }
              }
            }'
        elif kubectl get deployment limitador-operator-controller-manager --namespace {{ .namespace }} &>/dev/null; then
            kubectl patch deployment limitador-operator-controller-manager --namespace {{ .namespace }} --type strategic --patch '{
              "spec": {
                "template": {
                  "spec": {
                    "containers": [
                      {
                        "name": "manager",
                        "env": [
                          {
                            "name": "OTEL_EXPORTER_OTLP_ENDPOINT",
                            "value": "rpc://jaeger-collector.tools.svc.cluster.local:4317"
                          },
                          {
                            "name": "OTEL_EXPORTER_OTLP_INSECURE",
                            "value": "true"
                          }
                        ]
                      }
                    ]
                  }
                }
              }
            }'
        else
            echo "Warning: limitador-operator subscription and limitador-operator-controller-manager deployment not found in namespace {{ .namespace }}"
        fi

        kubectl patch limitador limitador --namespace {{ .namespace }} --type merge --patch '{"spec":{"verbosity":3}}'
        kubectl patch authorino authorino --namespace {{ .namespace }} --type merge --patch '{"spec":{"logLevel":"debug", "logMode": "development"}}'
        kubectl wait --for=jsonpath={.status.observedGeneration}=$(kubectl get limitador limitador --namespace {{ .namespace }} -o jsonpath={.metadata.generation}) limitador limitador --namespace {{ .namespace }} --timeout=300s
        kubectl wait --for=condition=Ready limitador limitador --namespace {{ .namespace }} --timeout=300s
        # Authorino CR does not have `.status.observedGeneration` defined hence just this simple wait
        kubectl wait --for=condition=Ready authorino authorino --namespace {{ .namespace }} --timeout=300s
    fi

    # Another wait for Kuadrant to get ready just to be on the safe side
    kubectl wait --for=jsonpath={.status.observedGeneration}=$(kubectl get kuadrant kuadrant-sample --namespace {{ .namespace }} -o jsonpath={.metadata.generation}) kuadrant kuadrant-sample --namespace {{ .namespace }} --timeout=300s
    kubectl wait --for=condition=Ready kuadrant kuadrant-sample --namespace {{ .namespace }} --timeout=300s

    # Enable Kuadrant console plugin if not already enabled
    if ! kubectl get console.operator.openshift.io/cluster -o jsonpath='{.spec.plugins[*]}' | grep -q "kuadrant-console-plugin"; then
        kubectl patch console.operator.openshift.io/cluster --type=json -p '[{"op": "add", "path": "/spec/plugins/-", "value": "kuadrant-console-plugin"}]'
    fi
---
apiVersion: batch/v1
kind: Job
metadata:
  name: post-install-helm-hook
  namespace: {{ .namespace }}
  annotations:
    "helm.sh/hook": post-install
spec:
  backoffLimit: 10
  template:
    spec:
      containers:
      - command:
        - /bin/bash
        - /scripts/run.sh
        image: quay.io/kuadrant/testsuite-pipelines-tools:latest
        name: post-install
        volumeMounts:
        - name: script-volume
          mountPath: /scripts
        resources: {}
      volumes:
        - name: script-volume
          configMap:
            name: post-install-helm-hook
      serviceAccount: post-install-helm-hook
      restartPolicy: OnFailure
{{- end -}}
