FROM debian:buster-slim

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
        sendmail        \
    && rm -rf /var/lib/apt/lists/*
#

# Make workdir where to store the files
#
ARG workdir=/media/SBE
WORKDIR $workdir

EXPOSE 22

ARG workdir=/root/SBE/SBE_data
ARG reportdir=/root/SBE/SBE_reports
RUN mkdir -p $workdir \
	&& mkdir -p $reportdir
WORKDIR $workdir

RUN service ssh start

CMD ["/usr/sbin/sshd","-D"]
