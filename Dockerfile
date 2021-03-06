FROM jenkins/inbound-agent:4.3-4-alpine
USER root
# https://github.com/docker-library/docker/blob/094faa88f437cafef7aeb0cc36e75b59046cc4b9/20.10/Dockerfile
RUN apk add --no-cache \
		ca-certificates \
		openssh-client
RUN [ ! -e /etc/nsswitch.conf ] && echo 'hosts: files dns' > /etc/nsswitch.conf

ENV DOCKER_VERSION 19.03.13
# TODO ENV DOCKER_SHA256
# https://github.com/docker/docker-ce/blob/5b073ee2cf564edee5adca05eee574142f7627bb/components/packaging/static/hash_files !!
# (no SHA file artifacts on download.docker.com yet as of 2017-06-07 though)

RUN set -eux; \
	\
	apkArch="$(apk --print-arch)"; \
	case "$apkArch" in \
		'x86_64') \
			url='https://download.docker.com/linux/static/stable/x86_64/docker-19.03.13.tgz'; \
			;; \
		'armhf') \
			url='https://download.docker.com/linux/static/stable/armel/docker-19.03.13.tgz'; \
			;; \
		'armv7') \
			url='https://download.docker.com/linux/static/stable/armhf/docker-19.03.13.tgz'; \
			;; \
		'aarch64') \
			url='https://download.docker.com/linux/static/stable/aarch64/docker-19.03.13.tgz'; \
			;; \
		*) echo >&2 "error: unsupported architecture ($apkArch)"; exit 1 ;; \
	esac; \
	\
	wget -O docker.tgz "$url"; \
	\
	tar --extract \
		--file docker.tgz \
		--strip-components 1 \
		--directory /usr/local/bin/ \
	; \
	rm docker.tgz; \
	\
	dockerd --version; \
	docker --version

COPY modprobe.sh /usr/local/bin/modprobe
COPY docker-entrypoint.sh /usr/local/bin/

# https://github.com/docker-library/docker/pull/166
#   dockerd-entrypoint.sh uses DOCKER_TLS_CERTDIR for auto-generating TLS certificates
#   docker-entrypoint.sh uses DOCKER_TLS_CERTDIR for auto-setting DOCKER_TLS_VERIFY and DOCKER_CERT_PATH
# (For this to work, at least the "client" subdirectory of this path needs to be shared between the client and server containers via a volume, "docker cp", or other means of data sharing.)
ENV DOCKER_TLS_CERTDIR=/certs
# also, ensure the directory pre-exists and has wide enough permissions for "dockerd-entrypoint.sh" to create subdirectories, even when run in "rootless" mode
RUN mkdir /certs /certs/client && chmod 1777 /certs /certs/client
# (doing both /certs and /certs/client so that if Docker does a "copy-up" into a volume defined on /certs/client, it will "do the right thing" by default in a way that still works for rootless users)

# dind Dockerfile
RUN set -eux; \
	apk add --no-cache \
		btrfs-progs \
		e2fsprogs \
		e2fsprogs-extra \
		ip6tables \
		iptables \
		openssl \
		shadow-uidmap \
		xfsprogs \
		xz \
		pigz \
	; \
	if zfs="$(apk info --no-cache --quiet zfs)" && [ -n "$zfs" ]; then \
		apk add --no-cache zfs; \
	fi

RUN set -eux; \
	addgroup -S dockremap; \
	adduser -S -G dockremap dockremap; \
	echo 'dockremap:165536:65536' >> /etc/subuid; \
	echo 'dockremap:165536:65536' >> /etc/subgid

ENV DIND_COMMIT ed89041433a031cafc0a0f19cfe573c31688d377

RUN set -eux; \
	wget -O /usr/local/bin/dind "https://raw.githubusercontent.com/docker/docker/${DIND_COMMIT}/hack/dind"; \
	chmod +x /usr/local/bin/dind

COPY dockerd-entrypoint.sh /usr/local/bin/


VOLUME /var/lib/docker

# dind Dockerfile End

# dind rootless
# RUN apk add --no-cache iproute2
# RUN mkdir /run/user && chmod 1777 /run/user
# RUN set -eux; \
# 	adduser -h /home/rootless -g 'Rootless' -D -u 1000 rootless; \
# 	echo 'rootless:100000:65536' >> /etc/subuid; \
# 	echo 'rootless:100000:65536' >> /etc/subgid

# RUN set -eux; \
# 	\
# 	apkArch="$(apk --print-arch)"; \
# 	case "$apkArch" in \
# 		'x86_64') \
# 			url='https://download.docker.com/linux/static/stable/x86_64/docker-rootless-extras-20.10.0.tgz'; \
# 			;; \
# 		*) echo >&2 "error: unsupported architecture ($apkArch)"; exit 1 ;; \
# 	esac; \
# 	\
# 	wget -O rootless.tgz "$url"; \
# 	\
# 	tar --extract \
# 		--file rootless.tgz \
# 		--strip-components 1 \
# 		--directory /usr/local/bin/ \
# 		'docker-rootless-extras/rootlesskit' \
# 		'docker-rootless-extras/rootlesskit-docker-proxy' \
# 		'docker-rootless-extras/vpnkit' \
# 	; \
# 	rm rootless.tgz; \
# 	\
# 	rootlesskit --version; \
# 	vpnkit --version

# # pre-create "/var/lib/docker" for our rootless user
# RUN set -eux; \
# 	mkdir -p /home/rootless/.local/share/docker; \
# 	chown -R rootless:rootless /home/rootless/.local/share/docker

# VOLUME /home/rootless/.local/share/docker

# USER rootless


# RUN apk add supervisor

# RUN mkdir -p /var/log/supervisor
# COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

CMD ["entrypoint.sh"]