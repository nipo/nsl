#include <sys/ioctl.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <sys/socket.h>
#include <arpa/inet.h>

#if 0
#define dprintf printf
#define dperror perror
#else
#define dprintf(...) do{}while(0)
#define dperror(...) do{}while(0)
#endif

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
void tcp_socket_ctor(void)
{
    dprintf("tcp_socket plugin loaded\n");
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

struct ghdl_tcp_socket_t
{
    int listen_fd;
    int sock_fd;
};

void tcp_socket_create_listener(
    struct ghdl_sockaddr_in_t *local,
    struct ghdl_tcp_socket_t *handle)
{
    struct sockaddr_in addr;
    handle->listen_fd = handle->sock_fd = -1;
  
    sockaddr_in_from_ghdl(&addr, local);

    dprintf("Binding to %08x:%d\n", addr.sin_addr.s_addr, htons(addr.sin_port));

    int fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0) {
        dperror("socket");
        return;
    }

    const int enable = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &enable, sizeof(int));

    int ret = bind(fd, (const struct sockaddr*)&addr, sizeof(addr));
    if (ret < 0) {
        dperror("bind");
        close(fd);
        return;
    }

    ret = listen(fd, 1);
    if (ret < 0) {
        dperror("listen");
        close(fd);
        return;
    }

    handle->listen_fd = fd;
}

void tcp_socket_create_connect(
    struct ghdl_sockaddr_in_t *remote,
    struct ghdl_tcp_socket_t *handle)
{
    struct sockaddr_in addr;
    handle->listen_fd = handle->sock_fd = -1;
  
    sockaddr_in_from_ghdl(&addr, remote);

    dprintf("Connecting to %08x:%d\n", addr.sin_addr.s_addr, htons(addr.sin_port));

    int fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0) {
        dperror("socket");
        return;
    }

    int ret = connect(fd, (const struct sockaddr*)&addr, sizeof(addr));
    if (ret < 0) {
        dperror("connect");
        close(fd);
        return;
    }

    handle->sock_fd = fd;

    int on = 1;
    ioctl(handle->sock_fd, FIONBIO, &on);
}

static void maybe_accept(
    struct ghdl_tcp_socket_t *handle)
{
    struct sockaddr_in addr;
    socklen_t slen = sizeof(addr);

    if (handle->listen_fd < 0)
        return;

    if (handle->sock_fd >= 0)
        return;

    fd_set read_set;
    int n_ready;
    struct timeval tv = {};

    FD_ZERO(&read_set);
    FD_SET(handle->listen_fd, &read_set);
    n_ready = select(handle->listen_fd + 1, &read_set, NULL, NULL, &tv);

    if (n_ready <= 0)
        return;
    
    handle->sock_fd = accept(handle->listen_fd, (struct sockaddr *)&addr, &slen);

    int on = 1;
    ioctl(handle->sock_fd, FIONBIO, &on);
    
    dprintf("Connection accepted from %08x:%d\n", addr.sin_addr.s_addr, htons(addr.sin_port));
}

void tcp_socket_is_connected(
    struct ghdl_tcp_socket_t *handle,
    uint32_t *status)
{
    maybe_accept(handle);

    *status = handle->sock_fd != -1;
}

void tcp_socket_send(
    struct ghdl_tcp_socket_t *handle,
    const struct ghdl_array *data)
{
    maybe_accept(handle);

    size_t data_len = ghdl_array_length(data);
    const uint8_t *data_ptr = ghdl_array_const_data(data);

    if (handle->sock_fd == -1) {
        dprintf("Trying to send to an unconnected socket\n");
        return;
    }

    dprintf("Sending %zu bytes\n", data_len);
    
    int ret = send(handle->sock_fd, data_ptr, data_len, 0);
    if (ret == 0) {
        dprintf("Write returned 0, socket is closed\n");
        close(handle->sock_fd);
        handle->sock_fd = -1;
    }
}

void tcp_socket_recv_len(
    struct ghdl_tcp_socket_t *handle,
    int *rlen)
{
    maybe_accept(handle);

    *rlen = 0;

    if (handle->sock_fd == -1)
        return;

    char c;
    ssize_t s = recv(handle->sock_fd, &c, 1, MSG_PEEK);
    if (s == 0) {
        dprintf("Peek returned 0, socket is closed\n");
        close(handle->sock_fd);
        handle->sock_fd = -1;
        return;
    } else if (s < 0 && errno != EAGAIN) {
        dprintf("Peek returned -1, socket is error\n");
        close(handle->sock_fd);
        handle->sock_fd = -1;
        return;
    }
    int nbytes;
    int ret = ioctl(handle->sock_fd, FIONREAD, &nbytes);
    if(ret < 0) {
        dprintf("FIONREAD failed %d\n", errno);
        return;
    }

    if (nbytes)
        dprintf("%d bytes waiting\n", nbytes);

    *rlen = nbytes;
    return;
}

void tcp_socket_recv_data(
    struct ghdl_tcp_socket_t *handle,
    struct ghdl_array *rdata,
    int *rlen)
{
    maybe_accept(handle);

    if (handle->sock_fd == -1) {
        *rlen = 0;
        return;
    }

    struct sockaddr_in addr;
    socklen_t addr_size = sizeof(addr);
    ssize_t readlen = recv(handle->sock_fd, rdata->data, rdata->range->len, 0);

    if (readlen == 0) {
        dprintf("Connection closed\n");

        close(handle->sock_fd);
        handle->sock_fd = -1;
    }
    
    dprintf("Received %zu bytes\n", (size_t)readlen);

    *rlen = readlen;
}
