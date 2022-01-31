FROM debian:buster-slim



#
# Get needed base tools in Debian
#
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl            \
        gawk            \
        git             \
        gnupg           \
        jq              \
        lsof            \
        lynx            \
        make            \
        rsync           \
        shellcheck      \
        sqlite3         \
        tree            \
        unzip           \
        vim             \
        wget            \
        openssh-server  \
    && rm -rf /var/lib/apt/lists/*



#
# Make workdir where to store the files
#
ARG localUser=sbe
ARG workdir=/home/$localUser
RUN useradd --create-home --shell /bin/bash $localUser \
	&& mkdir -p $workdir \
	&& chown $localUser $workdir
WORKDIR $workdir

EXPOSE 22

RUN  echo 'sbe:test' | chpasswd
RUN echo "root:root" | chpasswd

RUN service ssh start

CMD ["/usr/sbin/sshd","-D"]
