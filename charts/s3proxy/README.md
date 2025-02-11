
Run docker:

docker run --env-file .env --memory=250m --cpus=0.5 -p 8081:8081 andrewgaul/s3proxy

Test using aws client: `aws --endpoint-url="http://localhost:8081/" s3 ls testyacine/hf_cache/hub/`

`aws --endpoint-url="http://localhost:8081" s3 sync s3://testyacine .`

Requirements:
RAM: 250MB
CPU: 500 up to 1000

monitor with cadvisor:
sudo docker run --volume=/:/rootfs:ro \ 
--volume=/var/run:/var/run:rw \
 --volume=/sys:/sys:ro \ 
 --volume=/var/lib/docker/:/var/lib/docker:ro \ 
 --publish=8080:8080 \
 --detach=true \
 --name=cadvisor \ 
gcr.io/cadvisor/cadvisor