#ifndef SENSORS_C_H
#define SENSORS_C_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opens a read-only connection to the Apple SMC. Returns 0 on success.
int sensors_smc_open(void);
void sensors_smc_close(void);

/// Enumerates every SMC key that starts with 'T' (temperature) and holds a float value.
/// Writes 4-char keys (NUL-terminated, 5 bytes each) into `keys`. Returns the count written.
int sensors_smc_temperature_keys(char *keys, int maxKeys);

/// Reads a float SMC key. Returns a value < -900 on failure.
double sensors_smc_read(const char *key);

/// Reads all HID temperature sensors (works on Apple Silicon without root).
/// `names` receives NUL-terminated strings of up to 64 bytes each.
/// Returns the number of sensors written.
int sensors_hid_temperatures(char *names, double *values, int maxSensors);

#ifdef __cplusplus
}
#endif

#endif
