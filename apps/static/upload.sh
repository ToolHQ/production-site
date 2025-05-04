#! /bin/sh
aws --endpoint-url http://minio.localhost s3 sync ./static s3://my-site/static/