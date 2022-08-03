//
//  NMLIVM.h
//  NMLIVM
//
//  Created by nomadli on 2022/7/21.
//

#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <errno.h>
#import <unistd.h>
#import <readline/readline.h>
#import <Availability.h>
#import "help.h"

typedef enum {
    NMLIVM_MACOS = 0,
    NMLIVM_LINUX
} NMLIVMType;

typedef enum {
    NMLIVM_NET_NAT = 0,
    NMLIVM_NET_BRIDGE
} NMLIVMNetType;

typedef struct {
    char                who[128];
    char                rimg[512];
    char                vm[512];
    char                tips[1024];
    char                *cmd;
    const char          *self_path;
    NMLIVMType          system;
    NMLIVMNetType       net;
    unsigned int        cpu;
    unsigned int        graphics_width_pixels;
    unsigned int        graphics_height_pixels;
    unsigned int        graphics_pixels_per_inch;
    unsigned long long  mem;
    unsigned long long  min_mem;
    unsigned long long  disk;
    unsigned long long  min_disk;
} NMLIVM;

extern void start_menu(NMLIVM*);
extern int download_macos_restore_image(NMLIVM*);
extern int gen_macos_vm(NMLIVM*);
extern int gen_linux_vm(NMLIVM*);
extern void run_vm(int argc, const char* const *argv);
