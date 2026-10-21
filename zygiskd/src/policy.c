#include "policy.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <sys/stat.h>

#define ORIGIN_ZYGISK_DIR "/data/adb/ksu/originzygisk"
#define SKIP_PACKAGES_PATH ORIGIN_ZYGISK_DIR "/skip_packages.txt"
#define SKIP_UIDS_PATH ORIGIN_ZYGISK_DIR "/skip_uids.txt"
#define DISABLED_MODULES_PATH ORIGIN_ZYGISK_DIR "/disabled_modules.txt"
#define QUARANTINE_PATH ORIGIN_ZYGISK_DIR "/quarantine.txt"
#define TELEMETRY_PATH ORIGIN_ZYGISK_DIR "/telemetry.jsonl"
#define TELEMETRY_OLD_PATH ORIGIN_ZYGISK_DIR "/telemetry.jsonl.1"
#define TELEMETRY_MAX_BYTES (128 * 1024)

static void trim_line(char *line) {
  if (line == NULL) return;

  char *start = line;
  while (*start != '\0' && isspace((unsigned char)*start)) start++;

  size_t len = strlen(start);
  while (len > 0 && isspace((unsigned char)start[len - 1])) len--;
  start[len] = '\0';

  if (start != line) memmove(line, start, len + 1);
}

static bool uid_file_matches(uid_t uid) {
  FILE *file = fopen(SKIP_UIDS_PATH, "r");
  if (file == NULL) return false;

  bool matched = false;
  char line[128];
  while (fgets(line, sizeof(line), file) != NULL) {
    trim_line(line);
    if (line[0] == '\0' || line[0] == '#') continue;

    char *end = NULL;
    unsigned long value = strtoul(line, &end, 10);
    if (end != NULL && *end == '\0' && (uid_t)value == uid) {
      matched = true;
      break;
    }
  }

  fclose(file);

  return matched;
}

static bool package_file_matches(const char *process) {
  if (process == NULL || process[0] == '\0') return false;

  FILE *file = fopen(SKIP_PACKAGES_PATH, "r");
  if (file == NULL) return false;

  bool matched = false;
  char line[256];
  while (fgets(line, sizeof(line), file) != NULL) {
    trim_line(line);
    if (line[0] == '\0' || line[0] == '#') continue;

    size_t len = strlen(line);
    if (strncmp(process, line, len) != 0) continue;
    if (process[len] != '\0' && process[len] != ':') continue;

    matched = true;
    break;
  }

  fclose(file);

  return matched;
}

bool policy_process_skipped(uid_t uid, const char *process) {
  if (uid_file_matches(uid)) return true;

  return package_file_matches(process);
}

static bool module_file_matches(const char *path, const char *name) {
  if (name == NULL || name[0] == '\0') return false;

  FILE *file = fopen(path, "r");
  if (file == NULL) return false;

  bool matched = false;
  char line[256];
  while (fgets(line, sizeof(line), file) != NULL) {
    trim_line(line);
    if (line[0] == '\0' || line[0] == '#') continue;

    if (strcmp(line, name) == 0) {
      matched = true;
      break;
    }
  }

  fclose(file);

  return matched;
}

bool policy_module_disabled(const char *name) {
  if (module_file_matches(DISABLED_MODULES_PATH, name)) return true;

  return module_file_matches(QUARANTINE_PATH, name);
}

static void write_json_escaped(FILE *out, const char *value) {
  if (value == NULL) return;

  for (const unsigned char *p = (const unsigned char *)value; *p != '\0'; p++) {
    switch (*p) {
      case '"': fputs("\\\"", out); break;
      case '\\': fputs("\\\\", out); break;
      case '\b': fputs("\\b", out); break;
      case '\f': fputs("\\f", out); break;
      case '\n': fputs("\\n", out); break;
      case '\r': fputs("\\r", out); break;
      case '\t': fputs("\\t", out); break;
      default:
        if (*p < 0x20) fprintf(out, "\\u%04x", (unsigned int)*p);
        else fputc((int)*p, out);
    }
  }
}

void telemetry_event(const char *event, const char *abi, uid_t uid,
                     const char *process, uint32_t flags, bool skipped) {
  struct stat st;
  if (stat(TELEMETRY_PATH, &st) == 0 && st.st_size > TELEMETRY_MAX_BYTES) {
    remove(TELEMETRY_OLD_PATH);
    rename(TELEMETRY_PATH, TELEMETRY_OLD_PATH);
  }

  FILE *file = fopen(TELEMETRY_PATH, "a");
  if (file == NULL) return;

  fprintf(file,
          "{\"ts\":%lld,\"event\":\"%s\",\"abi\":\"%s\",\"uid\":%lu,\"process\":\"",
          (long long)time(NULL),
          event != NULL ? event : "",
          abi != NULL ? abi : "",
          (unsigned long)uid);
  write_json_escaped(file, process);
  fprintf(file, "\",\"flags\":%lu,\"skip\":%s}\n",
          (unsigned long)flags,
          skipped ? "true" : "false");

  fclose(file);
}
