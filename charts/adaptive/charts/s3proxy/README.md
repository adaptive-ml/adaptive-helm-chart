
## s3proxy

This Helm chart is an s3 adapter for object storage providers which don't provide an s3-interoperable API. It uses [s3proxy](https://github.com/gaul/s3proxy).

To run locally:

`docker run --env-file .env --memory=250m --cpus=0.5 -p 8081:8081 andrewgaul/s3proxy:2.6.0`

below an example of .env file:
```
S3PROXY_AUTHORIZATION=none
JCLOUDS_IDENTITY=opstestadaptive
JCLOUDS_ENDPOINT=https://opstestadaptive.blob.core.windows.net
JCLOUDS_PROVIDER=azureblob
JCLOUDS_AZUREBLOB_AUTH=azureKey
S3PROXY_ENDPOINT=http://0.0.0.0:8081
S3PROXY_IGNORE_UNKNOWN_HEADERS=true
JCLOUDS_CREDENTIAL=*****
```

`JCLOUDS_CREDENTIAL` should be replaced by your azure secret key.

Test using aws client: `aws --endpoint-url="http://localhost:8081/" s3 ls testyacine/hf_cache/hub/`

`aws --endpoint-url="http://localhost:8081" s3 sync s3://testyacine .`


## Performance monitoring

Requirements:
RAM: 250MB
CPU: 0.5 core is totally ok

Monitor with cadvisor:


```
sudo docker run --volume=/:/rootfs:ro \ 
--volume=/var/run:/var/run:rw \
 --volume=/sys:/sys:ro \ 
 --volume=/var/lib/docker/:/var/lib/docker:ro \ 
 --publish=8080:8080 \
 --detach=true \
 --name=cadvisor \ 
gcr.io/cadvisor/cadvisor
```
