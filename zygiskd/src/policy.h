#ifndef POLICY_H
#define POLICY_H

#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>

/* Returns true when the given process should not receive Zygisk modules. */
bool policy_process_skipped(uid_t uid, const char *process);

/* Returns true when the module id is disabled or quarantined. */
bool policy_module_disabled(const char *name);

/* Appends one bounded, machine-readable telemetry event. */
void telemetry_event(const char *event, const char *abi, uid_t uid,
                     const char *process, uint32_t flags, bool skipped);

#endif /* POLICY_H */
