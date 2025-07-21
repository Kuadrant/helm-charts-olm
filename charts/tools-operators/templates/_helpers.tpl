{{/* OLM wait for installplan; approves installplan */}}
{{- define "operators.olm-wait" }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: post-install-hook-{{ .subscription }}
  namespace: {{ .namespace }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: post-install-hook-{{ .subscription }}-role
  namespace: {{ .namespace }}
rules:
- apiGroups:
  - operators.coreos.com 
  resources:
  - subscriptions
  - installplans
  verbs:
  - get
  - patch
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: post-install-hook-{{ .subscription }}-rb
  namespace: {{ .namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: post-install-hook-{{ .subscription }}-role
subjects:
- kind: ServiceAccount
  name: post-install-hook-{{ .subscription }}
  namespace: {{ .namespace }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: post-install-hook-{{ .subscription }}
  namespace: {{ .namespace }}
data:
  "run.sh": |
    #/bin/bash
    set -xe
    kubectl wait --for=jsonpath={.status.installPlanRef.name} subscription {{ .subscription }} --timeout=10s
    ip=$(kubectl get subscription {{ .subscription }} -o=jsonpath={.status.installPlanRef.name})
    kubectl patch installplan ${ip} --type merge --patch '{"spec":{"approved":true}}'
    kubectl wait --for=condition=Installed installplan ${ip} --timeout=60s
---
apiVersion: batch/v1
kind: Job
metadata:
  name: post-install-hook-{{ .subscription }}
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
            name: post-install-hook-{{ .subscription }}
      serviceAccount: post-install-hook-{{ .subscription }}
      restartPolicy: OnFailure
{{- end }}
