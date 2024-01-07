# Dockerfile

FROM alpine:latest
WORKDIR /app
COPY . .

RUN apk add openjdk17
RUN apk add python3
RUN apk add ansible
#RUN echo “root:196711aa” | chpasswd
RUN apk add openrc
RUN apk add openssh
RUN apk add openssh-server
RUN apk add openssh-client
RUN apk add sshpass
RUN rc-status
RUN rc-update add sshd
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
RUN echo 'PermitEmptyPasswords yes' >> /etc/ssh/sshd_config
RUN echo 'Port 22' >> /etc/ssh/sshd_config
RUN rc-status

# Run in separate script on control and remote nodes
RUN ssh-keygen -A
RUN rc-status
RUN touch /run/openrc/softlevel
RUN /etc/init.d/sshd restart

# change root password on remote
