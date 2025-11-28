{{/* Wait for Kuadrant, Limitador and Authorino CRs and patch them to enable observability and debug logging */}}
{{- define "kuadrant.enable-debug" }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: post-install-hook-enable-debug
  namespace: {{ .namespace }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: post-install-hook-enable-debug-role
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
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: post-install-hook-enable-debug-rb
  namespace: {{ .namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: post-install-hook-enable-debug-role
subjects:
- kind: ServiceAccount
  name: post-install-hook-enable-debug
  namespace: {{ .namespace }}
---
apiVersion: v1
data:
  "run.sh": |
    #!/bin/bash
    set -xe
    kubectl wait --for=condition=Ready kuadrant kuadrant-sample --namespace {{ .namespace }} --timeout=300s
    kubectl patch limitador limitador --namespace {{ .namespace }} --type merge --patch '{"spec":{"verbosity":3}}'
    kubectl patch authorino authorino --namespace {{ .namespace }} --type merge --patch '{"spec":{"logLevel":"debug", "logMode": "development"}}'
    kubectl wait --for=condition=Ready kuadrant kuadrant-sample --namespace {{ .namespace }} --timeout=300s
    kubectl wait --for=condition=Ready authorino authorino --namespace {{ .namespace }} --timeout=300s
kind: ConfigMap
metadata:
  name: post-install-hook-enable-debug
  namespace: {{ .namespace }}
---
apiVersion: batch/v1
kind: Job
metadata:
  name: post-install-hook-enable-debug
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
            name: post-install-hook-enable-debug
      serviceAccount: post-install-hook-enable-debug
      restartPolicy: OnFailure
{{- end }}
