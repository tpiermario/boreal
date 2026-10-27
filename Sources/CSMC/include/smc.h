#ifndef BOREAL_SMC_H
#define BOREAL_SMC_H
#include <stdint.h>
#include <stddef.h>
typedef struct {
    char key[5];
    char type[5];
    uint8_t bytes[32];
    uint32_t size;
} BFValue;
int bf_open(void);
int bf_intel_hardware(void);
void bf_close(void);
int bf_read(const char *key, BFValue *value);
int bf_key_at(uint32_t index, char key[5]);
int bf_number(const char *key, double *value);
int bf_fan_count(void);
int bf_fan_bounds(int fan, double *minimum, double *maximum);
int bf_fan_set(int fan, double rpm);
int bf_fan_auto(int fan);
int bf_fan_mode(int fan);
uint16_t bf_mode_bits(uint16_t bits, int fan, int manual);
int bf_restore_all(void);
int bf_can_control(int fan);
double bf_request_timeout(const char *command);
int bf_request(const char *socket_path, const char *command, char *response, size_t capacity);
double bf_curve(double temperature, double start, double full, double minimum, double maximum);
int bf_valid_target(double rpm, double minimum, double maximum);
int bf_parse_targets(const char *command, int count, double targets[10]);
#endif
