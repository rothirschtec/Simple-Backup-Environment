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
        #cron            \
        sendmail        \
    && rm -rf /var/lib/apt/lists/*


# Configure cronjob
#RUN echo '# SBE backup each minute' >> /var/spool/cron/crontabs/root
#RUN echo '*/1 * * * * bash /opt/SBE/SBE_data/main.sh' >> /var/spool/cron/crontabs/root
#RUN echo '# SBE checker' >> /var/spool/cron/crontabs/root
#RUN echo '0 6 * * * bash /opt/SBE/SBE_data/tools/checker.sh' >> /var/spool/cron/crontabs/root

ARG workdir=/opt/SBE/SBE_data
ARG reportdir=/opt/SBE/SBE_reports
RUN mkdir -p $workdir \
	&& mkdir -p $reportdir
WORKDIR $workdir

CMD ["/opt/SBE/SBE_data/main.sh"]
#EXPOSE 22
#RUN service ssh start
#CMD ["/usr/sbin/sshd","-D"]
