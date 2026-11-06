// gcc -shared -fPIC -o libruntime.so runtime.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static uint64_t double_to_uint64(double d) {
    uint64_t u;
    memcpy(&u, &d, sizeof(u));
    return u;
}

static double uint64_to_double(uint64_t u) {
    double d;
    memcpy(&d, &u, sizeof(d));
    return d;
}

static uint64_t num_to_uint64(double d) {
    return (uint64_t)(d * 8.0);
}

double print(double x) { printf("%f\n", x); return 0.0 / 0.0; }

double memalloc(double s) {
    if (s < 0 || s > (double)(SIZE_MAX / 8)) return 0.0 / 0.0;
    uint64_t n = num_to_uint64(s);           /* s * 8 байт */
    void *p = malloc(n);
    return uint64_to_double((uint64_t)(uintptr_t)p);
}

double memfree(double p) {
    void *ptr = (void *)(uintptr_t)double_to_uint64(p);
    free(ptr);
    return 0.0 / 0.0;
}

double memstore(double p, double v) {
    void *ptr = (void *)(uintptr_t)double_to_uint64(p);
    memcpy(ptr, &v, sizeof(v));
    return 0.0 / 0.0;
}

double memload(double p) {
    void *ptr = (void *)(uintptr_t)double_to_uint64(p);
    double v;
    memcpy(&v, ptr, sizeof(v));
    return v;
}

double memadd(double a, double b) {
    uint64_t r = double_to_uint64(a) + double_to_uint64(b);
    return uint64_to_double(r);
}

double memmul(double a, double b) {
    uint64_t r = double_to_uint64(a) * double_to_uint64(b);
    return uint64_to_double(r);
}

double memeq(double a, double b)  { return (double_to_uint64(a) == double_to_uint64(b)) ? 1.0 : 0.0; }
double memneq(double a, double b) { return (double_to_uint64(a) != double_to_uint64(b)) ? 1.0 : 0.0; }
double memgt(double a, double b)  { return (double_to_uint64(a) >  double_to_uint64(b)) ? 1.0 : 0.0; }
double memlt(double a, double b)  { return (double_to_uint64(a) <  double_to_uint64(b)) ? 1.0 : 0.0; }
double memgte(double a, double b) { return (double_to_uint64(a) >= double_to_uint64(b)) ? 1.0 : 0.0; }
double memlte(double a, double b) { return (double_to_uint64(a) <= double_to_uint64(b)) ? 1.0 : 0.0; }

double memptr(double d) {
    return uint64_to_double((uint64_t)d * 8);
}