# OLM Test Helpers

This repository contains scripts to play arround with OLM bundles and catalogs based on [semver veneer](https://github.com/operator-framework/operator-registry/tree/master/alpha/veneer/semver).

## Prerequisites

You need to have `docker`, `kubectl` and `yq` (>= v4) installed. On your cluster should OLM be deployed (you can use `make install-olm` to install it on your cluster).

## Additional information

The deployed "operator" (`go-http-server`) is a simple http server without any CRDs only logging the deployed version and having the version in its deployment name.

## Make targets

### Parameters

Every make target can be customized using the following additional parameters:

|Parameter|Default|Description|
|---------|-------|-----------|
|VERSION|0.0.1|The version of the operator/bundle to build/deploy/use|
|REGISTRY|quay.io|The container registry where to pull/push the images to|
|REGISTRY_USER|creydr|The user for the container registry|
|NAMESPACE|default|The namespace, in which all the resources should be created (besides the one from `make install-olm`)|

Of course the defaults of these parameters can be changed in the [Makefile](Makefile) for easier use.

### Targets

In the following the most relevant targets are listed:

|Target|Description|
|------|-----------|
|push-bundle|Builds and pushes a new version of the operator, creates a bundle referencing it and pushes the bundle to the registry. This should be used with specifying the version. E.g. `VERSION=1.24.1 make push-bundle`|
|generate-catalog|This will generate/update the [catalog.yaml](operator-catalog/catalog/catalog.yaml) based on the contents of the [operator-veneer.yaml](operator-catalog/operator-veneer.yaml) file.|
|generate-mermaid-graph|This will output the mermaid source for the upgrade paths based on the contents of the [operator-veneer.yaml](operator-catalog/operator-veneer.yaml) file. These paths can be visualized for example on [https://mermaid.live](https://mermaid.live/edit)|
|validate-catalog|As the name suggests validates the catalog.yaml file|
|push-catalog|Builds and pushes a catalog based on the contents of the [catalog.yaml](operator-catalog/catalog/catalog.yaml). It will not depend on `generate-catalog` to be able to update the catalog.yaml before manually. If not the default tag for the catalog image (`catalog`) wants to be used (e.g. in case a seperate catalog for hotfixes needs to be created), the parameter `CATALOG_IMAGE_TAG` can be used (e.g. `CATALOG_IMAGE_TAG=catalog-hotfix-123` make push-catalog).|
|apply-catalog|This does the same as `push-catalog` but also creates/updates the CatalogSource in the cluster with the generated catalog.|
|apply-subscription|Creates/updates a Subscription in the cluster, for the operator, referencing the catalog. Attention: You might want to specify another channel as the default in the Subscription (`stable`) via the `DEFAULT_CHANNEL` parameter, and in case you built your catalog image with a specific tag (`CATALOG_IMAGE_TAG`), you should use this parameter here too (e.g. `CATALOG_IMAGE_TAG=catalog-hotfix-123 make apply-subscription`)|

## Examples

In the following some examples are given on working with this repository.

### Create a bundle

You can create and push a bundle for a new version like the following:

```bash
$ VERSION=1.24.0 make push-bundle
```

This will also create and push an operator with the given version for you.

The content of the bundle will also be available in ./operator-bundle/1.24.0/.

As you need for testing mostly a couple of bundles, you can create multiple with a simple for loop:

```bash
$ for i in {24..26}; do VERSION=1.$i.0 make push-bundle; done
```

### Edit the veneer file

The [operator-veneer.yaml](operator-catalog/operator-veneer.yaml) file is the source for the generated file based catalog (FBC - [catalog.yaml](operator-catalog/catalog/catalog.yaml)). Best is probably to check on the [semver veneer](https://github.com/operator-framework/operator-registry/tree/master/alpha/veneer/semver) docs for the structure of the file.

Just be aware of the current issue [1031](https://github.com/operator-framework/operator-registry/issues/1031) which does not generate update paths between minor channels.

To add a new release to one of the channels, simply add another `Image` to the `Bundles` array in one of the channels (e.g. `Candidate`). Afterwards run `make generate-catalog` to update the [catalog.yaml](operator-catalog/catalog/catalog.yaml) file.

### Add catalog as a CatalogSource

When you created and pushed your catalog (via `make push-catalog`), you can make use of the provided operator, by creating a CatalogSource referencing it. Simply use the following command to create a CatalogSource in your cluster:

```bash
$ make apply-catalog
```

In case you specified a specific tag for the catalog, use the `CATALOG_IMAGE_TAG` here too:
```bash
$ CATALOG_IMAGE_TAG=my-special-catalog-tag make apply-catalog
```

### Creating a Subscription

You can create a subscription via 

```bash
$ make apply-subscription
```

This will also make sure a CatalogSource and OperatorGroup exists.

## Example Workflow for releasing a Hotfix

### Baseline Scenario

The user has a catalog with the following structure:

Default catalog contains the following channels and versions:

* Channel: `stable-v1`
  * 1.24.0
  * 1.24.1
  * 1.25.0
  * 1.26.0
  * 1.26.1
* Channel: `stable-v1.24`
  * 1.24.0
  * 1.24.1
* Channel: `stable-v1.25`
  * 1.25.0
* Channel: `stable-v1.26`
  * 1.26.0
  * 1.26.1

To rebuild this, we do the following:

1. Create the required bundles first:

```bash
$ for i in {24..26}; do VERSION=1.$i.0 make push-bundle; done
$ VERSION=1.24.1 make push-bundle
$ VERSION=1.26.1 make push-bundle
```

2. Update the [operator-veneer.yaml](operator-catalog/operator-veneer.yaml) file with the following content (adjust the image path):

```yaml
Schema: olm.semver
GenerateMajorChannels: true
GenerateMinorChannels: true
Stable:
  Bundles:
  - Image: quay.io/creydr/hello-world-go:1.24.0-bundle
  - Image: quay.io/creydr/hello-world-go:1.24.1-bundle
  - Image: quay.io/creydr/hello-world-go:1.25.0-bundle
  - Image: quay.io/creydr/hello-world-go:1.26.0-bundle
  - Image: quay.io/creydr/hello-world-go:1.26.1-bundle
```

For ease of this go-through, we don't add additional channels (e.g. `Candidate`).

3. Create/update the FBC and push the image by running:

```bash
$ make generate-catalog
$ make push-catalog
```

Also check out the content of the generated/updated [catalog.yaml](operator-catalog/catalog/catalog.yaml) file.

4. Create a CatalogSource to make the operator available in your cluster:

```bash
$ make apply-catalog

$ kubectl get catsrc
NAME                           DISPLAY               TYPE   PUBLISHER   AGE
hello-world-operator-catalog   Hello World Catalog   grpc   creydr      7m56s
```

5. Install the operator. You can either do this via the UI (e.g. when you're on OpenShift) or create the Subscription manually:

```bash
$ make apply-subscription

$ kubectl get sub
NAME              PACKAGE       SOURCE                         CHANNEL
hello-world-sub   hello-world   hello-world-operator-catalog   stable
```

Unfortunately we have to adjust the subscription channel manually and change it from `stable` to `stable-v1.24`. You can run the following patch for this:

```bash 
$ kubectl patch sub hello-world-sub --type merge --patch '{"spec":{"channel":"stable-v1.24"}}'

$ kubectl get sub                                                                                            
NAME              PACKAGE       SOURCE                         CHANNEL
hello-world-sub   hello-world   hello-world-operator-catalog   stable-v1.24
```

6. As we set the `installPlanApproval` to manuall in the Subscription, we need to approve the install plan:

```bash
$ kubectl get ip
NAME            CSV                            APPROVAL   APPROVED
install-877jl   hello-world-operator-v1.24.1   Manual     false

$ kubectl patch installplan install-877jl --type merge --patch '{"spec":{"approved":true}}'

$ kubectl get ip
NAME            CSV                            APPROVAL   APPROVED
install-877jl   hello-world-operator-v1.24.1   Manual     true
```

7. Make sure the operator gets installed:

```bash
$ kubectl get po
NAME                                                              READY   STATUS      RESTARTS   AGE
...
hello-world-operator-v1.24.1-8954c4d44-cqqs9                      1/1     Running     0          24s
```

### Release a Hotfix

Now imagine v1.24.1 has an issue and we have to provide a hotfix only to a specific user. In this case we could create a new catalog only containing an upgrade path from the users current version to the hotfix. We do this by the following:

_Hint: as this changes a lot of the "original" files and is only temporary, it is recommended to do this on a seperate branch._

1. Create a hotfix release bundle

```bash
$ VERSION=1.24.1-hotfix-1 make push-bundle
```

2. Create a new catalog with an upgrade path for this hotfix. Update the [operator-veneer.yaml](operator-catalog/operator-veneer.yaml) file with the following content (adjust the image path):

```yaml
Schema: olm.semver
GenerateMajorChannels: true
GenerateMinorChannels: true
Stable:
  Bundles:
  - Image: quay.io/creydr/hello-world-go:1.24.0-bundle
  - Image: quay.io/creydr/hello-world-go:1.24.1-bundle
  - Image: quay.io/creydr/hello-world-go:1.24.1-hotfix-1-bundle
```

3. Create a new catalog 

```bash
$ make generate-catalog
```

Make sure the catalog.yaml has an upgrade path from `1.24.1` to `1.24.1-hotfix-1` (veneer seems at this point to model this somehow different):

```yaml
...

entries:
- name: hello-world-operator-v1.24.0
- name: hello-world-operator-v1.24.1
- name: hello-world-operator-v1.24.1-hotfix-1
  skips:
  - hello-world-operator-v1.24.0
  - hello-world-operator-v1.24.1
name: stable-v1
package: hello-world
schema: olm.channel
---
entries:
- name: hello-world-operator-v1.24.0
- name: hello-world-operator-v1.24.1
- name: hello-world-operator-v1.24.1-hotfix-1
  skips:
  - hello-world-operator-v1.24.0
  - hello-world-operator-v1.24.1
name: stable-v1.24
package: hello-world
schema: olm.channel

...
```

4. Create a catalog image with a seperate tag

```bash
$ CATALOG_IMAGE_TAG=hotfix-1-catalog make push-catalog
```

5. Create a new CatalogSource for the user referencing the new catalog image:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: hello-world-operator-hotfix-catalog
spec:
  sourceType: grpc
  image: <the image from the step before>
  displayName: Hello World Hotfix Catalog
  publisher: creydr
  updateStrategy:
    registryPoll:
      interval: 1m
EOF
```

6. Reference the new CatalogSource in the existing Subscription:

```bash
kubectl patch sub hello-world-sub --type merge --patch {"spec":{"source":"hello-world-operator-hotfix-catalog"}}
```

7. After the new catalog got pulled (according to your catalogSource every minute), the new install plan should show up:

```bash
$ kubectl get ip
NAME            CSV                                     APPROVAL   APPROVED
install-877jl   hello-world-operator-v1.24.1            Manual     true
install-tk9p9   hello-world-operator-v1.24.1-hotfix-1   Manual     false
```

8. Approve the installplan for the hotfix:

```bash
$ kubectl patch installplan install-tk9p9 --type merge --patch '{"spec":{"approved":true}}'

$ kubectl get ip
NAME            CSV                                     APPROVAL   APPROVED
install-877jl   hello-world-operator-v1.24.1            Manual     true
install-tk9p9   hello-world-operator-v1.24.1-hotfix-1   Manual     true
```

9. Make sure the hotfix version of the operator gets installed:

```bash
$ kubectl get po
NAME                                                              READY   STATUS             RESTARTS   AGE
...
hello-world-operator-v1.24.1-hotfix-1-54c94c7bdc-rmqlb            1/1     Running            0          64s
```

### Releasing a stable release with the hotfix and switching back channels

After the hotfix got verified by the user, we can release a "official" release including this hotfix. In addition to adding this to the default channel, it will be added to the hotfix-channel from the user too, to provide an upgrade path.

1. Create a "normal" release including the hotfix. This will be version `1.24.2`:

```bash
$ VERSION=1.24.2 make push-bundle
```

2. Update the hotfix channel to provide an upgrade path for the user from the hotfix to the "official" release. Then veneer file could look like the following:

```yaml
Schema: olm.semver
GenerateMajorChannels: true
GenerateMinorChannels: true
Stable:
  Bundles:
  - Image: quay.io/creydr/hello-world-go:1.24.0-bundle
  - Image: quay.io/creydr/hello-world-go:1.24.1-bundle
  - Image: quay.io/creydr/hello-world-go:1.24.1-hotfix-1-bundle
  - Image: quay.io/creydr/hello-world-go:1.24.2-bundle
```

3. Update the catalog.yaml

```bash
$ make generate-catalog 
```

As previously make sure the catalog.yaml has an upgrade path from  `1.24.1-hotfix-1` to `1.24.2` (this should be fine in this case, as `1.24.2` > `1.24.1-hotfix-1`):

```yaml
...

entries:
- name: hello-world-operator-v1.24.0
- name: hello-world-operator-v1.24.1
- name: hello-world-operator-v1.24.1-hotfix-1
- name: hello-world-operator-v1.24.2
  skips:
  - hello-world-operator-v1.24.0
  - hello-world-operator-v1.24.1
  - hello-world-operator-v1.24.1-hotfix-1
name: stable-v1
package: hello-world
schema: olm.channel
---
entries:
- name: hello-world-operator-v1.24.0
- name: hello-world-operator-v1.24.1
- name: hello-world-operator-v1.24.1-hotfix-1
- name: hello-world-operator-v1.24.2
  skips:
  - hello-world-operator-v1.24.0
  - hello-world-operator-v1.24.1
  - hello-world-operator-v1.24.1-hotfix-1
name: stable-v1.24
package: hello-world
schema: olm.channel

...
```

4. Update the hotfix catalog image:

```bash
$ CATALOG_IMAGE_TAG=hotfix-1-catalog make push-catalog
```

5. After the new catalog got pulled, the new install plan should show up:

```bash
$ kubectl get ip   
NAME            CSV                                     APPROVAL   APPROVED
install-877jl   hello-world-operator-v1.24.1            Manual     true
install-smwqh   hello-world-operator-v1.24.2            Manual     false
install-tk9p9   hello-world-operator-v1.24.1-hotfix-1   Manual     true
```

6. Approve the installplan for the `1.24.2` release:

```bash
$ kubectl patch installplan install-smwqh --type merge --patch '{"spec":{"approved":true}}'

$ kubectl get ip
NAME            CSV                                     APPROVAL   APPROVED
install-877jl   hello-world-operator-v1.24.1            Manual     true
install-smwqh   hello-world-operator-v1.24.2            Manual     true
install-tk9p9   hello-world-operator-v1.24.1-hotfix-1   Manual     true
```

7. Make sure the hotfix version of the operator gets installed:

```bash
$ kubectl get po
NAME                                                              READY   STATUS      RESTARTS   AGE
...
hello-world-operator-v1.24.2-74d4fb6579-72d7v                     1/1     Running     0          19s
```

8. Now or in parallel we can also update the "official" catalog to include the `1.24.2` release. Therefor we simply add it to our veneer file:

```yaml
Schema: olm.semver
GenerateMajorChannels: true
GenerateMinorChannels: true
Stable:
  Bundles:
  - Image: quay.io/creydr/hello-world-go:1.24.0-bundle
  - Image: quay.io/creydr/hello-world-go:1.24.1-bundle
  - Image: quay.io/creydr/hello-world-go:1.24.2-bundle
  - Image: quay.io/creydr/hello-world-go:1.25.0-bundle
  - Image: quay.io/creydr/hello-world-go:1.26.0-bundle
  - Image: quay.io/creydr/hello-world-go:1.26.1-bundle
```

And update our catalog.yaml:

```bash
$ make generate-catalog
```

9. Then we can update the "official" catalog image:

```bash
make push-catalog
```

10. Afterwards the user can switch its subscription to the "official" catalog again and delete the hotfix catalog source:

```bash
$ kubectl patch sub hello-world-sub --type merge --patch {"spec":{"source":"hello-world-operator-catalog"}}

$ kubectl get catsrc                             
NAME                                  DISPLAY                      TYPE   PUBLISHER   AGE
hello-world-operator-catalog          Hello World Catalog          grpc   Creydr      68m
hello-world-operator-hotfix-catalog   Hello World Hotfix Catalog   grpc   creydr      33m

$ kubectl delete catsrc hello-world-operator-hotfix-catalog
```
