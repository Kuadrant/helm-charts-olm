{{/* Restarts Kuadrant Operator if needed. Waits for Kuadrant, Limitador and Authorino CRs and patch them to enable observability and debug logging if desired */}}
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

    ENABLE_DEBUG="{{ .enableDebug }}"
    if [[ "$ENABLE_DEBUG" == "true" ]]; then
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
