#! /bin/bash

# curl -X POST \
#   'http://localhost:3002/convert-arrow-into-ndjson' \
#   -H 'accept: application/x-ndjson' \
#   -H 'Content-Type: multipart/form-data' \
#   -F 'file=@flights-1m.arrow' \
#   -o flights-1m.ndjson

curl -X GET \
  'http://localhost:3003/ndjson' \
  -H 'accept: application/x-ndjson' \
  -o ../data/testing/flights-2m.ndjson
