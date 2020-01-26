#####################################################
### Build UI bundles
FROM node:13.7-alpine AS jsbuilder
WORKDIR /src
COPY ui/package.json ui/package-lock.json ./
RUN npm ci
COPY ui/ .
RUN npm run build


#####################################################
### Build executable
FROM golang:1.13-alpine AS gobuilder

# Download build tools
RUN mkdir -p /src/ui/build
RUN apk add -U --no-cache build-base git
RUN go get -u github.com/go-bindata/go-bindata/...

# Download and unpack static ffmpeg
ARG FFMPEG_VERSION=4.1.4
ARG FFMPEG_URL=https://www.johnvansickle.com/ffmpeg/old-releases/ffmpeg-${FFMPEG_VERSION}-amd64-static.tar.xz
RUN wget -O /tmp/ffmpeg.tar.xz ${FFMPEG_URL}
RUN cd /tmp && tar xJf ffmpeg.tar.xz && rm ffmpeg.tar.xz

# Download project dependencies
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

# Copy source and UI bundle, build executable
COPY . .
COPY --from=jsbuilder /src/build/* /src/ui/build/
COPY --from=jsbuilder /src/build/static/css/* /src/ui/build/static/css/
COPY --from=jsbuilder /src/build/static/js/* /src/ui/build/static/js/
RUN rm -rf /src/build/css /src/build/js
RUN go-bindata -fs -prefix ui/build -tags embed -nocompress -pkg assets -o assets/embedded_gen.go ui/build/...\
    && go build -ldflags="-X main.gitSha=${SOURCE_COMMIT} -X main.gitTag=${SOURCE_BRANCH}" -tags=embed

#####################################################
### Build Final Image
FROM alpine
COPY --from=gobuilder /src/navidrome /app/
COPY --from=gobuilder /tmp/ffmpeg*/ffmpeg /usr/bin/

VOLUME ["/data", "/music"]
ENV ND_MUSICFOLDER /music
ENV ND_DATAFOLDER /data
ENV ND_SCANINTERVAL 1m
ENV ND_LOGLEVEL info
ENV ND_PORT 4533
EXPOSE 4533

WORKDIR /app
CMD "/app/navidrome"
