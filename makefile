PLATFORM=$(shell uname -s | tr '[:upper:]' '[:lower:]')
VERSION := $(shell grep -Eo '(v[0-9]+[\.][0-9]+[\.][0-9]+(-[a-zA-Z0-9]*)?)' version.go)

.PHONY: build build-server docker release check

build: check build-server build-webui

build-server:
	CGO_ENABLED=1 go build -o ./bin/server github.com/moov-io/imagecashletter/cmd/server

build-webui:
	cp $(shell go env GOROOT)/misc/wasm/wasm_exec.js ./cmd/webui/assets/wasm_exec.js
	GOOS=js GOARCH=wasm go build -o ./cmd/webui/assets/imagecashletter.wasm github.com/moov-io/imagecashletter/cmd/webui/icl/
	CGO_ENABLED=0 go build -o ./bin/webui ./cmd/webui

.PHONY: check
check:
ifeq ($(OS),Windows_NT)
	@echo "Skipping checks on Windows, currently unsupported."
else
	@wget -O lint-project.sh https://raw.githubusercontent.com/moov-io/infra/master/go/lint-project.sh
	@chmod +x ./lint-project.sh
	DISABLE_XMLENCODERCLOSE=true GOOS=js GOARCH=wasm COVER_THRESHOLD=85.0 ./lint-project.sh
endif

.PHONY: client
client:
	@grep -rnwl './client/' -e 'Generated by: OpenAPI Generator' | xargs -n1 rm

# Generate all the new go code.
	java -jar openapi-generator-cli.jar generate \
		--input-spec ./openapi.yaml \
		--output ./client \
		--generator-name go \
		--additional-properties isGoSubmodule=true,enumClassPrefix=true \
		--package-name openapi
	rm -f client/go.mod client/go.sum client/.travis.yml

# Format it and ensure that its good
	go fmt ./...
	go build github.com/moov-io/imagecashletter/client
	go test ./client


.PHONY: clean
clean:
ifeq ($(OS),Windows_NT)
	@echo "Skipping cleanup on Windows, currently unsupported."
else
	@rm -rf ./bin/ openapi-generator-cli-*.jar
endif

dist: clean client build
ifeq ($(OS),Windows_NT)
	CGO_ENABLED=1 GOOS=windows go build -o bin/imagecashletter.exe github.com/moov-io/imagecashletter/cmd/server
else
	CGO_ENABLED=1 GOOS=$(PLATFORM) go build -o bin/imagecashletter-$(PLATFORM)-amd64 github.com/moov-io/imagecashletter/cmd/server
endif

docker: clean docker-hub docker-openshift docker-webui

docker-hub:
	docker build --pull -t moov/imagecashletter:$(VERSION) -f Dockerfile .
	docker tag moov/imagecashletter:$(VERSION) moov/imagecashletter:latest

docker-openshift:
	docker build --pull -t quay.io/moov/imagecashletter:$(VERSION) -f Dockerfile.openshift --build-arg VERSION=$(VERSION) .
	docker tag quay.io/moov/imagecashletter:$(VERSION) quay.io/moov/imagecashletter:latest

docker-webui:
	docker build --pull -t moov/imagecashletter-webui:$(VERSION) -f Dockerfile.webui .
	docker tag moov/imagecashletter-webui:$(VERSION) moov/imagecashletter-webui:latest

release: docker AUTHORS
	go vet ./...
	go test -coverprofile=cover-$(VERSION).out ./...
	git tag -f $(VERSION)

release-push:
	docker push moov/imagecashletter:$(VERSION)
	docker push moov/imagecashletter:latest
	docker push moov/imagecashletter-webui:$(VERSION)
	docker push moov/imagecashletter-webui:latest

quay-push:
	docker push quay.io/moov/imagecashletter:$(VERSION)
	docker push quay.io/moov/imagecashletter:latest

.PHONY: cover-test cover-web
cover-test:
	go test -coverprofile=cover.out ./...
cover-web:
	go tool cover -html=cover.out

# From https://github.com/genuinetools/img
.PHONY: AUTHORS
AUTHORS:
	@$(file >$@,# This file lists all individuals having contributed content to the repository.)
	@$(file >>$@,# For how it is generated, see `make AUTHORS`.)
	@echo "$(shell git log --format='\n%aN <%aE>' | LC_ALL=C.UTF-8 sort -uf)" >> $@

.PHONY: tagged-release
tagged-release:
	@./tagged-release.sh $(VERSION)
