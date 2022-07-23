//
//  help.h
//  NMLIVM
//
//  Created by nomadli on 2022/7/22.
//

#ifndef __HELP_H__
#define __HELP_H__

#define NMLI_LOG_COLOR_DEFAULT      "\x1b[0m"
#define NMLI_LOG_COLOR_BLACK        "\x1b[30m"
#define NMLI_LOG_COLOR_RED          "\x1b[31m"
#define NMLI_LOG_COLOR_GREEN        "\x1b[32m"
#define NMLI_LOG_COLOR_YELLOW       "\x1b[33m"
#define NMLI_LOG_COLOR_BLUE         "\x1b[34m"
#define NMLI_LOG_COLOR_VIOLET       "\x1b[35m"
#define NMLI_LOG_COLOR_SKYBLUE      "\x1b[36m"
#define NMLI_LOG_COLOR_WHITE        "\x1b[37m"
#define NMLI_LOG(msg)               printf(NMLI_LOG_COLOR_RED msg NMLI_LOG_COLOR_DEFAULT)
#define NMLI_LOG_VAR(format, ...)   printf(NMLI_LOG_COLOR_RED format NMLI_LOG_COLOR_DEFAULT, ##__VA_ARGS__)

#define NMLI_MACOS_MIN_CPU          (2)
#define NMLI_MACOS_MIN_MEM          (4ull * 1024ull * 1024ull * 1024ull)

#define NMLI_VM_AUX(base)           [base URLByAppendingPathComponent:@"AuxDisk"]
#define NMLI_VM_EFI(base)           [base URLByAppendingPathComponent:@"EFIDisk"]
#define NMLI_VM_HARDWARE(base)      [base URLByAppendingPathComponent:@"hardware"]
#define NMLI_VM_MACHID(base)        [base URLByAppendingPathComponent:@"machineID"]
#define NMLI_VM_DISK(base)          [base URLByAppendingPathComponent:@"Disk.nmvm"]
#define NMLI_VM_CFG(base)           [base URLByAppendingPathComponent:@"config"]


static __inline__ __attribute__((always_inline)) char* nmli_absolute_path(const char *relative, char *absolute) {
    if (relative == NULL || absolute == NULL) {
        return NULL;
    }
    if (relative[0] == '~') {
        strcpy(absolute, getenv("HOME"));
        strcat(absolute, relative + 1);
        return absolute;
    }
    return realpath(relative, absolute);
}

#endif /* __HELP_H__ */
