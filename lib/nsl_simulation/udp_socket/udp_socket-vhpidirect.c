#include <sys/ioctl.h>
#include <unistd.h>
#include <stdio.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <vhpidirect_user.h>

static
void hexdump(const void *data, size_t size)
{
    const uint8_t *d = data;
    size_t point;

    for (point = 0; point < size; ++point) {
        if ((point % 16) == 0)
            printf("%04zu |", point);
        if ((point % 16) == 8)
            printf(" ");

        printf(" %02x", d[point]);

        if ((point % 16) == 15)
            printf("\n");
    }

    if (point % 16)
        printf("\n");
}

static void sockaddr_in_from_vhdl(
    struct sockaddr_in *dst,
    const int32_t ip[4],
    int32_t port)
{
    uint32_t tmp = 0;
    for (int i = 0; i < 4; ++i) {
        tmp <<= 8;
        tmp |= ip[i];
    }
    memset(dst, 0, sizeof(*dst));
    dst->sin_addr.s_addr = htonl(tmp);
    dst->sin_port = htons(port);
    dst->sin_family = AF_INET;
}

static void sockaddr_in_to_vhdl(
    int32_t ip[4],
    int32_t *port,
    const struct sockaddr_in *src)
{
    uint32_t tmp = ntohl(src->sin_addr.s_addr);
    for (int i = 3; i >= 0; --i) {
        ip[i] = tmp & 0xff;
        tmp >>= 8;
    }
    *port = ntohs(src->sin_port);
}

void udp_socket_create(
    const int32_t ip[4],
    int32_t port,
    int *rfd)
{
    struct sockaddr_in addr;
    *rfd = -1;
  
    sockaddr_in_from_vhdl(&addr, ip, port);

    /* printf("Bind to %08x:%d\n", addr.sin_addr.s_addr, htons(addr.sin_port)); */

    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);

    int ret = bind(fd, (const struct sockaddr*)&addr, sizeof(addr));
    if (ret < 0)
        perror("bind");

    *rfd = fd;
}

int udp_socket_sendto(
    int fd,
    const int32_t ip[4],
    int32_t port,
    const struct vhpidirect_array *data)
{
    size_t data_len = data->range->len;
    const uint8_t *data_ptr = data->data;
    struct sockaddr_in addr;

    sockaddr_in_from_vhdl(&addr, ip, port);

    /* printf("Send to %08x:%d\n", addr.sin_addr.s_addr, htons(addr.sin_port)); */
    
    return sendto(fd, data_ptr, data_len, 0,
                  (const struct sockaddr*)&addr, sizeof(addr));
}

int udp_socket_recv_len(
    int fd)
{
    fd_set read_set;
    int n_ready;
    struct timeval tv = {};

    FD_ZERO(&read_set);
    FD_SET(fd, &read_set);
    n_ready = select(fd + 1, &read_set, NULL, NULL, &tv);

    if (n_ready <= 0)
        return 0;

    int nbytes, ret;

    ret = ioctl(fd, FIONREAD, &nbytes);

    if(ret < 0)
        return -1;

    /* printf("FIONREAD says %d\n", nbytes); */
    
    return nbytes;
}

void udp_socket_recv_data(
    int fd,
    int32_t ip[4],
    int32_t *port,
    struct vhpidirect_array *rdata,
    int *rlen)
{
    struct sockaddr_in addr;
    socklen_t addr_size = sizeof(addr);
    *rlen = recvfrom(fd, rdata->data, rdata->range->len, 0,
                     (struct sockaddr *)&addr, &addr_size);
    
    /* printf("Received from %08x:%d\n", addr.sin_addr.s_addr, htons(addr.sin_port)); */

    sockaddr_in_to_vhdl(ip, port, &addr);
}
