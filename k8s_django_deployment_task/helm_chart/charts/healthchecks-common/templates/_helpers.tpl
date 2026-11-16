{{- define "healthchecks-common.image" -}}
{{- $image := .Values.image | default dict -}}
{{- $repository := required "image.repository is required" ($image.repository | default "" | trim) -}}
{{- $tag := required "image.tag is required" $image.tag -}}
{{- printf "%s:%v" $repository $tag -}}
{{- end -}}
