#!/bin/bash
# Tested in 2024-03-24
## From both:
# https://min.io/docs/minio/kubernetes/upstream/
# https://gist.github.com/balamurugana/c59e868a36bb8a549fe863d22d6f0678

# git clone https://github.com/OpenMaxIO/openmaxio-object-browser.git
# cp Dockerfile openmaxio-object-browser/Dockerfile
# cd openmaxio-object-browser
# docker build -t openmaxio-object-browser:local .
# docker tag openmaxio-object-browser:local openmaxio-object-browser:1.1.0
# docker save openmaxio-object-browser:local -o /tmp/openmaxio-object-browser.tar
# sudo ctr -n k8s.io images import /tmp/openmaxio-object-browser.tar
# docker save openmaxio-object-browser:1.1.0 -o /tmp/openmaxio-object-browser-1.1.0.tar
# sudo ctr -n k8s.io images import /tmp/openmaxio-object-browser-1.1.0.tar
# cd ..

## Live baseline
kubectl apply -f minio-resources.yaml

echo "ℹ️  T-150 preparation artifacts are versioned but intentionally not auto-applied:"
echo "   - components/minio/minio-longhorn-preflight.yaml"
echo "   - components/minio/minio-longhorn-target.yaml"
echo "   - components/minio/minio-longhorn-cutover.md"
echo "   Gate: keep hostPath-backed MinIO live until /data/minio fits the validated Longhorn envelope."
