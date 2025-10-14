#ifndef VHPIDIRECT_USER_H_
#define VHPIDIRECT_USER_H_

struct vhpidirect_range
{
    int32_t left, right, dir, len;
};

struct vhpidirect_array
{
    char *data;
    struct vhpidirect_range *range;
};

struct vhpidirect_access
{
    struct vhpidirect_range range;
    uint8_t data[0];
};

static
char *vhpidirect_c_string_p(const struct vhpidirect_array *str)
{
    if (!str)
        return NULL;

    size_t sz = str->range->len;
    char *ret = malloc(sz+1);

    memcpy(ret, str->data, sz);
    ret[sz] = 0;
    return ret;
}

typedef long long unsigned vhpidirect_time_t;

#endif
