FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    jq \
    xorriso \
    p7zip-full \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

COPY . /work
RUN chmod +x /work/build-winiso.sh

ENTRYPOINT ["/work/build-winiso.sh"]
