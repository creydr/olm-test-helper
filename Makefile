VERSION ?= 0.0.1

REGISTRY ?= quay.io
REGISTRY_USER ?= creydr

IMAGE_NAME = ${REGISTRY}/${REGISTRY_USER}/hello-world-go
IMAGE = ${IMAGE_NAME}:${VERSION}
BUNDLE_IMAGE = ${IMAGE}-bundle
CATALOG_IMAGE_TAG ?= catalog
CATALOG_IMAGE = ${IMAGE_NAME}:${CATALOG_IMAGE_TAG}

CHANNELS ?= stable
DEFAULT_CHANNEL ?= stable

NAMESPACE ?= default

build-image:
	docker build --build-arg VERSION=${VERSION} -t ${IMAGE} .

push-image: build-image
	docker push ${IMAGE}

deploy: push-image
	kubectl -n ${NAMESPACE} apply -f deployment.yaml
	kubectl -n ${NAMESPACE} set image deployment/hello-world app=${IMAGE}

generate-bundle-manifests:
	@test ! -s ./operator-bundle/${VERSION}/manifests/clusterserviceversion.yaml && \
	mkdir -p ./operator-bundle/${VERSION}/manifests && \
	cp ./operator-bundle/template/clusterserviceversion.yaml ./operator-bundle/${VERSION}/manifests/ && \
	yq -i '.spec.install.spec.deployments[].spec.template.spec.containers[].image = "${IMAGE}"' ./operator-bundle/${VERSION}/manifests/clusterserviceversion.yaml && \
	yq -i '.spec.install.spec.deployments[].name = "hello-world-operator-v${VERSION}"' ./operator-bundle/${VERSION}/manifests/clusterserviceversion.yaml && \
	yq -i '.spec.version = "${VERSION}"' ./operator-bundle/${VERSION}/manifests/clusterserviceversion.yaml && \
	yq -i '.metadata.name = "hello-world-operator-v${VERSION}"' ./operator-bundle/${VERSION}/manifests/clusterserviceversion.yaml || \
	echo "skipping to generate bundle manifests as the CSV file exists already"

generate-bundle: generate-bundle-manifests
	cd operator-bundle/${VERSION}/ && \
	../../${OPM} alpha bundle generate --directory manifests --package hello-world --channels ${CHANNELS} --default ${DEFAULT_CHANNEL} && \
	cd ..

build-bundle: push-image generate-bundle
	docker build -t ${BUNDLE_IMAGE} -f operator-bundle/${VERSION}/bundle.Dockerfile operator-bundle/${VERSION}/

push-bundle: build-bundle
	docker push ${BUNDLE_IMAGE}

validate-bundle: generate-bundle build-bundle push-bundle
	${OPM} alpha bundle validate --tag ${BUNDLE_IMAGE}

generate-catalog-dockerfile:
	cd ./operator-catalog && \
	../$(OPM) generate dockerfile ./catalog && \
	cd ..

generate-catalog:
	cd ./operator-catalog && \
	../$(OPM) alpha render-veneer semver ./operator-veneer.yaml -o yaml > ./catalog/catalog.yaml && \
	cd ..

generate-mermaid-graph:
	$(OPM) alpha render-veneer semver ./operator-catalog/operator-veneer.yaml -o mermaid

validate-catalog:
	$(OPM) validate ./operator-catalog/catalog

build-catalog: #generate-catalog
	docker build -t ${CATALOG_IMAGE} -f ./operator-catalog/catalog.Dockerfile ./operator-catalog/

push-catalog: build-catalog
	docker push ${CATALOG_IMAGE}

apply-catalog: push-catalog
	yq '.spec.image = "${CATALOG_IMAGE}"' ./catalogsource.yaml | kubectl -n ${NAMESPACE} apply -f -

apply-operator-group:
	kubectl -n ${NAMESPACE} apply -f operatorgroup.yaml

apply-subscription: apply-catalog apply-operator-group
	yq '.spec.channel = "${DEFAULT_CHANNEL}"' subscription.yaml | \
	yq '.spec.sourceNamespace = "${NAMESPACE}"' | kubectl -n ${NAMESPACE} apply -f -

install-olm:
	kubectl apply -f https://raw.githubusercontent.com/operator-framework/operator-lifecycle-manager/master/deploy/upstream/quickstart/crds.yaml
	kubectl apply -f https://raw.githubusercontent.com/operator-framework/operator-lifecycle-manager/master/deploy/upstream/quickstart/olm.yaml

.PHONY: opm
OPM = ./bin/opm
opm: ## Download opm locally if necessary.
ifeq (,$(wildcard $(OPM)))
ifeq (,$(shell which opm 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPM)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPM) https://github.com/operator-framework/operator-registry/releases/download/v1.26.2/$${OS}-$${ARCH}-opm ;\
	chmod +x $(OPM) ;\
	}
else
OPM = $(shell which opm)
endif
endif
