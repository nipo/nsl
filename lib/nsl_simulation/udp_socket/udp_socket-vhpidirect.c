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

static
struct timespec simulation_origin;

struct ghdl_range
{
    int32_t left, right, dir, len;
};

struct ghdl_array
{
    char *data;
    struct ghdl_range *range;
};

struct ghdl_signal
{
    char *data;
    struct ghdl_range *range;
};

struct ghdl_access
{
    struct ghdl_range range;
    uint8_t data[0];
};

static
void *ghdl_array_data(struct ghdl_array *s)
{
    return s->data;
}

static
const void *ghdl_array_const_data(const struct ghdl_array *s)
{
    return s->data;
}

static
size_t ghdl_array_length(const struct ghdl_array *s)
{
    return s->range->len;
}

static
char *ghdl_c_string_p(const struct ghdl_array *str)
{
    if (!str)
        return NULL;

    size_t sz = ghdl_array_length(str);
    char *ret = malloc(sz+1);

    memcpy(ret, ghdl_array_const_data(str), sz);
    ret[sz] = 0;
    return ret;
}

typedef long long unsigned ghdl_time_t;

static
__attribute__((constructor))
void udp_socket_ctor(void)
{
    printf("udp_socket plugin loaded\n");
}


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

struct ghdl_sockaddr_in_t
{
    int ip[4];
    int port;
};

static void sockaddr_in_from_ghdl(
    struct sockaddr_in *dst,
    const struct ghdl_sockaddr_in_t *src)
{
    uint32_t tmp = 0;
    for (int i = 0; i < 4; ++i) {
        tmp <<= 8;
        tmp |= src->ip[i];
    }
    dst->sin_addr.s_addr = htonl(tmp);
    dst->sin_port = htons(src->port);
    dst->sin_family = AF_INET;
}

static void sockaddr_in_to_ghdl(
    struct ghdl_sockaddr_in_t *dst,
    const struct sockaddr_in *src)
{
    uint32_t tmp = htonl(src->sin_addr.s_addr);
    for (int i = 3; i >= 0; --i) {
        dst->ip[i] = tmp & 0xff;
        tmp >>= 8;
    }
    dst->port = htons(src->sin_port);
}

void udp_socket_create(
    struct ghdl_sockaddr_in_t *local,
    int *rfd)
{
    struct sockaddr_in addr;
    *rfd = -1;
  
    sockaddr_in_from_ghdl(&addr, local);

    /* printf("Bind to %08x:%d\n", addr.sin_addr.s_addr, htons(addr.sin_port)); */

    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);

    int ret = bind(fd, (const struct sockaddr*)&addr, sizeof(addr));
    if (ret < 0)
        perror("bind");

    *rfd = fd;
}

int udp_socket_sendto(
    int fd,
    struct ghdl_sockaddr_in_t *remote,
    const struct ghdl_array *data)
{
    size_t data_len = ghdl_array_length(data);
    const uint8_t *data_ptr = ghdl_array_const_data(data);
    struct sockaddr_in addr;

    sockaddr_in_from_ghdl(&addr, remote);

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
    struct ghdl_sockaddr_in_t *remote,
    struct ghdl_array *rdata,
    int *rlen)
{
    struct sockaddr_in addr;
    socklen_t addr_size = sizeof(addr);
    *rlen = recvfrom(fd, rdata->data, rdata->range->len, 0,
                     (struct sockaddr *)&addr, &addr_size);
    
    /* printf("Received from %08x:%d\n", addr.sin_addr.s_addr, htons(addr.sin_port)); */

    sockaddr_in_to_ghdl(remote, &addr);
}
