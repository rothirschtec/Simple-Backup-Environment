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
        pwgen           \
        cryptsetup      \
        mailutils       \
        msmtp           \
        msmtp-mta       \
    && rm -rf /var/lib/apt/lists/*


ARG workdir=/opt/SBE/SBE_data
ARG reportdir=/opt/SBE/SBE_reports
RUN mkdir -p $workdir \
	&& mkdir -p $reportdir
WORKDIR $workdir

CMD ["/opt/SBE/SBE_data/main.sh"]
