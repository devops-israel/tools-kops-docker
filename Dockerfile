FROM alpine:3.5
LABEL maintainer="Devops Israel - <info@devops.co.il"

ENV KUBECTL_VERSION 1.6.0
ENV KOPS_VERSION 1.5.3

#install kubectl
RUN apk add --update \
    curl \
    jq \
    vim \
    bash \
    bash-doc \
    bash-completion \
    util-linux pciutils usbutils coreutils binutils findutils grep \
    ca-certificates \
    openssh-client \
    && curl -s -L https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl -o /usr/bin/kubectl \
    && chmod +x /usr/bin/kubectl

#install kops
RUN  curl -s -L https://github.com/kubernetes/kops/releases/download/${KOPS_VERSION}/kops-linux-amd64 -o /usr/bin/kops \
     && chmod +x /usr/bin/kops

#install python and dependencies
RUN apk add --update --no-cache python \
    && python -m ensurepip \
    && rm -r /usr/lib/python*/ensurepip \
    && pip install --upgrade pip setuptools \
    awscli --ignore-installed \
    && rm -r /root/.cache

WORKDIR /opt
COPY wkops.sh /opt/wkops.sh

CMD ["bash"]
