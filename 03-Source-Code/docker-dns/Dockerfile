FROM alpine:3.23
RUN apk add --no-cache dnsmasq bind-tools
COPY entrypoint.sh /usr/local/bin/project-dns
RUN chmod +x /usr/local/bin/project-dns
EXPOSE 53/udp 53/tcp
ENTRYPOINT ["/usr/local/bin/project-dns"]
