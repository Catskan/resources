## Fluentbit

This tool is configured to read logs from the pods in k8s and push them to a Azure Storage Account.

The image for fluentbit is pushed to the cbmtqa registry. But, if it ever needs to be re-built, here are the steps:

```
git clone https://github.com/fluent/fluent-bit.git

cd fluent-bit

docker build --no-cache  --build-arg FLUENTBIT_VERSION=1.6.10 -t fluent/fluent-bit:1.6.10 -f Dockerfile.windows .

docker tag fluent/fluent-bin:1.6.0 cbmtqa.azurecr.io/fluent-bit:1.6.10

docker login cbmtqa.azurecr.io

docker push cbmtqa.azurecr.io/fluent-bit:1.6.10

```

Then, on the jumpbox, you can apply this yaml to deploy FluentBit to each windows node in the cluster

```
kubectl apply -f fluent-bit-all.yaml
```

For the linux version, pull from docker.io and push to our repo:

```
docker pull fluent/fluent-bin:1.8.11
docker tag fluent/fluent-bin:1.8.11 cbmtdev.azurecr.io/fluent-bit-linux:1.8.11
docker login cbmtdev.azurecr.io # use the admin login you can get from Azure portal on the container registry
docker push cbmtdev.azurecr.io/fluent-bit-linux:1.8.11
```

Now, this linux-based container is available in our azure registry.


### Testing locally

The fluentbit config can be a giant pain. Testing locally can help get the parsers and filters setup. However, it will miss the kubernetes metadata.

The files in the *test* directory are purely for local development. Feel free to modify or add any example logs to test with.

To run it, modify `test/fluent-bit.conf` and `test/parser.conf` to test a particular log type by uncommenting the test log to use as input. Then, run the following at the command line from inside this fluentbit directory:
```
docker run --network="host" -v `pwd`/test:/tmp -ti fluent/fluent-bit:1.8.11 /fluent-bit/bin/fluent-bit -c /tmp/fluent-bit.conf -R /tmp/parser.conf
```
The format of the data that will be sent to the output will be sent to standard output (the default output in test/fluent-bit.conf).
Press Ctrl-C to stop the container.

### pushing the logs to elasticsearch

Get a local version of es and kibana running

```
docker-compose -f test/es-kibana-compose.yaml up -d
```

Edit the `test/fluent-bit.conf` to make the `es` output plugin used instead of `stdout`. Then run the docker command above. It will push the sample logs to elasticsearch.

You can view the logs by opening a browser to http://127.0.0.1:5601/.  Then, you can "Discover", create an index pattern for 'fluent-bit' and start to see the logs in kibana.

If you want to clear the fluent-bit index to prevent sending the same logs over and over again, run this command:
```
curl -XDELETE 'localhost:9200/fluent-bit'
```


