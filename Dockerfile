FROM golang:1.19 AS builder
ARG VERSION=unknown
WORKDIR /tmp/build
COPY main.go .
RUN CGO_ENABLED=0 go build -ldflags "-X main.version=${VERSION}" -o ./server ./main.go

FROM scratch
COPY --from=builder  /tmp/build/server /usr/bin/server
CMD ["/usr/bin/server"]
