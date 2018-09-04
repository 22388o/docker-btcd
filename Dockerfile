FROM golang:1.10-stretch as builder

MAINTAINER Tom Kirkpatrick <tkp@kirkdesigns.co.uk>

# Install build dependencies such as git and glide.
RUN go get -u github.com/Masterminds/glide

WORKDIR $GOPATH/src/github.com/btcsuite/btcd

# Grab and install the latest version of btcd and all related dependencies.
RUN git clone https://github.com/btcsuite/btcd . \
&& git reset --hard cff30e1d23fc9e800b2b5b4b41ef1817dda07e9f \
&&  glide install \
&&  go install . ./cmd/...

FROM ubuntu:xenial
MAINTAINER Tom Kirkpatrick <tkp@kirkdesigns.co.uk>

ARG USER_ID
ARG GROUP_ID

ENV HOME /btcd

# add user with specified (or default) user/group ids
ENV USER_ID ${USER_ID:-1000}
ENV GROUP_ID ${GROUP_ID:-1000}

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -g ${GROUP_ID} btcd \
	&& useradd -u ${USER_ID} -g btcd -s /bin/bash -m -d /btcd btcd

# Copy the compiled binaries from the builder image.
COPY --from=builder /go/bin/addblock /bin/
COPY --from=builder /go/bin/btcctl /bin/
COPY --from=builder /go/bin/btcd /bin/
COPY --from=builder /go/bin/findcheckpoint /bin/
COPY --from=builder /go/bin/gencerts /bin/

# grab gosu for easy step-down from root
ENV GOSU_VERSION 1.10
RUN set -ex; \
	\
	fetchDeps=' \
		ca-certificates \
		wget \
	'; \
	apt-get update; \
	apt-get install -y --no-install-recommends $fetchDeps; \
	rm -rf /var/lib/apt/lists/*; \
	\
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	\
# verify the signature
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	\
	chmod +x /usr/local/bin/gosu; \
# verify that the binary works
	gosu nobody true; \
	\
	apt-get purge -y --auto-remove $fetchDeps

ADD ./bin /usr/local/bin

# Create a volume to house btcd data
VOLUME ["/btcd"]

# Expose mainnet ports (server, rpc)
EXPOSE 8333 8334

# Expose testnet ports (server, rpc)
EXPOSE 18333 18334

# Expose simnet ports (server, rpc)
EXPOSE 18555 18556

# Expose segnet ports (server, rpc)
EXPOSE 28901 28902

WORKDIR /btcd

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["btcd_oneshot"]
