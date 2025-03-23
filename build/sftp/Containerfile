# Use the official Alpine base image
FROM alpine:latest

# Install necessary packages
RUN apk update && \
    apk add --no-cache openssh-server openssh-sftp-server && \
    rm -rf /var/cache/apk/*

# Create scanner user for SFTP, '988' is nfs mapped uid/gid for mounted dir
RUN adduser -u 988 -D -s /sbin/nologin scanner && \
    echo 'scanner:*' | chpasswd

# Create scanner homedir
RUN mkdir -p /home/scanner/in && \
    chown root:root -R /home/scanner && \
    chmod 755 -R /home/scanner && \
    ssh-keygen -A

# Copy Authorized Keys
COPY files/authorized_keys /etc/ssh/authorized_keys
RUN chmod 644 /etc/ssh/authorized_keys

# Configure SSH
COPY files/sshd_config /etc/ssh/sshd_config.d/sftp.conf

# Expose the SFTP port
EXPOSE 22

# Start the SSH daemon
CMD ["/usr/sbin/sshd", "-D", "-e", "-f", "/etc/ssh/sshd_config.d/sftp.conf"]
