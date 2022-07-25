//
//  NMLIVM.c
//  NMLIVM
//
//  Created by nomadli on 2022/7/21.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <sys/stat.h>
#import <dirent.h>
#import "NMLIVM.h"

static int get_path(NMLIVM *vm, char *ret, size_t max, bool create) {
    for (char path[1024]; ; ) {
        vm->cmd = readline(vm->tips);
        if (vm->cmd == NULL) {
            printf("\033[A\033[K\033[A\033[K");
            continue;
        }
        if (vm->cmd[0] == '\0') {
            free(vm->cmd);
            return -1;
        }
        nmli_absolute_path(vm->cmd, path);
        add_history(vm->cmd);
        free(vm->cmd);
        
        if (access(path, W_OK | R_OK) == -1) {
            if (create) {
                size_t len = strlen(path);
                path[len] = '/';
                for (size_t i = 1; i <= len; ++i) {
                    if (path[i] != '/') {
                        continue;
                    }
                    path[i] = '\0';
                    
                    if (access(path, F_OK) == -1) {
                        if (mkdir(path, S_IRWXU | S_IRWXG | S_IRWXO) != 0) {
                            NMLI_LOG_VAR("create path %s err %d:%s\n\n", path, errno, strerror(errno));
                            path[i] = '/';
                            break;
                        }
                    }
                    path[i] = '/';
                }
                path[len] = '\0';
                if (access(path, W_OK | R_OK) == 0) {
                    strncpy(ret, path, max);
                    break;
                }
            }
            NMLI_LOG_VAR("%s : write|read Permission denied!\n\n", path);
            continue;
        }
        strncpy(ret, path, max);
        break;
    }
    return 0;
}

static int setting_vm_graphics(NMLIVM *vm) {
    CGDirectDisplayID gid = CGMainDisplayID();
    size_t width = CGDisplayPixelsWide(gid);
    size_t height = CGDisplayPixelsHigh(gid);
    size_t per_inch = width / (size_t)CGDisplayScreenSize(gid).width;
    bool same = (width == 1920) && (height == 1200) && (per_inch == 80);
    for ( ; ; ) {
        if (same) {
            sprintf(vm->tips,
                    "Setting graphics device width * height pixels and pixels per inch:\n"
                    "1. 1920*1200*80\n"
                    "2. Manual set width_pixels * height_pixels * pixels_per_inch\n"
                    "3. Back to upper menu\n%s> ", vm->who);
        } else {
            sprintf(vm->tips,
                    "Setting graphics device width * height pixels and pixels per inch:\n"
                    "1. %zu*%zu*%zu\n"
                    "2. 1920*1200*80\n"
                    "3. Manual set width_pixels * height_pixels * pixels_per_inch\n"
                    "4. Back to upper menu\n%s> ", width, height, per_inch, vm->who);
        }
        vm->cmd = readline(vm->tips);
        if (vm->cmd == NULL || vm->cmd[1] != '\0' || vm->cmd[0] == '\0') {
            if (vm->cmd != NULL) {
                free(vm->cmd);
            }
            if (same) {
                printf("\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K");
            } else {
                printf("\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K");
            }
            continue;
        }
        
        if (vm->cmd[0] == '1') {
            vm->graphics_width_pixels = (unsigned int)width;
            vm->graphics_height_pixels = (unsigned int)height;
            vm->graphics_pixels_per_inch = (unsigned int)per_inch;
            free(vm->cmd);
            return 0;
        }
        if (vm->cmd[0] == '2' && !same) {
            vm->graphics_width_pixels = 1920;
            vm->graphics_height_pixels = 1200;
            vm->graphics_pixels_per_inch = 80;
            free(vm->cmd);
            return 0;
        }
        if ((vm->cmd[0] == '3' && same) || (vm->cmd[0] == '4' && !same)) {
            free(vm->cmd);
            return -1;
        }
        
        char *p = vm->cmd + 1;
        for (; p[0] != '*' && p[0] != '\0'; ++p);
        if (p[0] == '\0') {
            if (same) {
                printf("\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K");
            } else {
                printf("\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K");
            }
            free(vm->cmd);
            continue;
        }
        p[0] = '\0';
        vm->graphics_width_pixels = atoi(vm->cmd);
        
        vm->cmd = ++p;
        for (; p[0] != '*' && p[0] != '\0'; ++p);
        if (p[0] == '\0') {
            if (same) {
                printf("\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K");
            } else {
                printf("\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K");
            }
            free(vm->cmd);
            continue;
        }
        p[0] = '\0';
        vm->graphics_height_pixels = atoi(vm->cmd);
        vm->cmd = ++p;
        
        vm->graphics_pixels_per_inch = atoi(vm->cmd);
        free(vm->cmd);
        if (vm->graphics_width_pixels < 800 || vm->graphics_height_pixels < 600 ||
            vm->graphics_pixels_per_inch <= 0) {
            NMLI_LOG("graphics widht >= 800 && height>= 600 && pixels_per_inch > 0\n");
            continue;
        }
        return 0;
    }
}

static int setting_vm_net(NMLIVM *vm) {
    for ( ; ; ) {
        sprintf(vm->tips,
                "1. Network translation(nat)\n"
                "2. Network bridge mode\n"
                "3. Back to upper menu\n%s> ", vm->who);
        vm->cmd = readline(vm->tips);
        if (vm->cmd == NULL || vm->cmd[1] != '\0' ||
            (vm->cmd[0] != '1' && vm->cmd[0] != '2' && vm->cmd[0] != '3')) {
            if (vm->cmd != NULL) {
                free(vm->cmd);
            }
            printf("\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K");
            continue;
        }
        
        if (vm->cmd[0] == '1') {
            vm->net = NMLIVM_NET_NAT;
        } else if (vm->cmd[0] == '2') {
            vm->net = NMLIVM_NET_BRIDGE;
        } else {
            free(vm->cmd);
            return -1;
        }
        free(vm->cmd);
        if (setting_vm_graphics(vm) != 0) {
            continue;
        }
        return 0;
    }
}

static int setting_vm_disk(NMLIVM *vm) {
    for ( ; ; ) {
        sprintf(vm->tips, "Size of disk(G):\n%s> ", vm->who);
        vm->cmd = readline(vm->tips);
        if (vm->cmd == NULL) {
            printf("\033[A\033[K\033[A\033[K");
            continue;
        }
        if (vm->cmd[0] == '\0') {
            free(vm->cmd);
            return -1;
        }
        vm->disk = atoll(vm->cmd) * 1024llu * 1024llu * 1024llu;
        free(vm->cmd);
        if (vm->disk <= vm->min_disk) {
            NMLI_LOG_VAR("disk must >= %lluG\n", vm->min_disk / (1024llu * 1024llu * 1024llu));
            continue;
        }
        if (setting_vm_net(vm) != 0) {
            continue;
        }
        return 0;
    }
}

static int setting_vm_mem(NMLIVM *vm) {
    for ( ; ; ) {
        sprintf(vm->tips, "Size of memory(G):\n%s> ", vm->who);
        vm->cmd = readline(vm->tips);
        if (vm->cmd == NULL) {
            printf("\033[A\033[K\033[A\033[K");
            continue;
        }
        if (vm->cmd[0] == '\0') {
            free(vm->cmd);
            return -1;
        }
        vm->mem = atoll(vm->cmd) * 1024llu * 1024llu * 1024llu;
        free(vm->cmd);
        if (vm->mem < vm->min_mem) {
            NMLI_LOG_VAR("memory must >= %lluG\n", vm->min_mem / (1024llu * 1024llu * 1024llu));
            continue;
        }
        if (setting_vm_disk(vm) != 0) {
            continue;
        }
        return 0;
    }
}

static int setting_vm_cpu(NMLIVM *vm) {
    NSUInteger cpu = [[NSProcessInfo processInfo] processorCount];
    for ( ; ; ) {
        sprintf(vm->tips, "Number of CPU cores(total %ld):\n%s> ", cpu, vm->who);
        vm->cmd = readline(vm->tips);
        if (vm->cmd == NULL) {
            printf("\033[A\033[K\033[A\033[K");
            continue;
        }
        if (vm->cmd[0] == '\0') {
            free(vm->cmd);
            return -1;
        }
        vm->cpu = atoi(vm->cmd);
        free(vm->cmd);
        if (vm->cpu <= 0 || vm->cpu >= cpu) {
            NMLI_LOG_VAR("cpu must [1 - %ld]\n", cpu - 1);
            continue;
        }
        if (setting_vm_mem(vm) != 0) {
            continue;
        }
        return 0;
    }
}

static int get_vm_save_path(NMLIVM *vm) {
    for ( ; ; ) {
        sprintf(vm->tips, "Input diretory path to save vm:\n%s> ", vm->who);
        if (get_path(vm, vm->vm, sizeof(vm->vm), true) != 0) {
            return -1;
        }
        
        DIR *dir = opendir(vm->vm);
        if (dir == NULL) {
            NMLI_LOG_VAR("%s not a diretory!\n\n", vm->vm);
            vm->vm[0] = '\0';
            continue;
        }
        int count = 0;
        for (; count < 3 && readdir(dir) != NULL; ++count);
        closedir(dir);
        if (count >= 3) {
            NMLI_LOG_VAR("%s not empty!\n", vm->vm);
            vm->vm[0] = '\0';
            continue;
        }
        
        return 0;
    }
}

__attribute__((__unused__)) static void create_macos_vm(NMLIVM *vm) {
    vm->system = NMLIVM_MACOS;
    vm->min_mem = 2llu * 1024llu * 1024llu * 1024llu;
    vm->min_disk = 64llu * 1024llu * 1024llu * 1024llu;
    
    for (bool start = false; ; ) {
        if (setting_vm_cpu(vm) != 0) {
            return;
        }
        
        for ( ; ; ) {
            sprintf(vm->tips,
                    "1. download the last macos system restore image *.ipws\n"
                    "2. select a macos system restore image *.ipws\n"
                    "3. Back to upper menu\n%s> ", vm->who);
            vm->cmd = readline(vm->tips);
            if (vm->cmd == NULL || vm->cmd[1] != '\0' ||
                (vm->cmd[0] != '1' && vm->cmd[0] != '2' && vm->cmd[0] != '3')) {
                if (vm->cmd != NULL) {
                    free(vm->cmd);
                }
                printf("\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K");
                continue;
            }
            if (vm->cmd[0] == '1') {
                free(vm->cmd);
                sprintf(vm->tips, "download save path:\n%s> ", vm->who);
                if (get_path(vm, vm->rimg, sizeof(vm->rimg), false) != 0) {
                    break;
                }
                if (download_macos_restore_image(vm) == 0) {
                    start = true;
                }
                break;
            }
            if (vm->cmd[0] == '2') {
                free(vm->cmd);
                sprintf(vm->tips, "Select a macos restore image *.ipws\n%s> ", vm->who);
                if (get_path(vm, vm->rimg, sizeof(vm->rimg), false) == 0) {
                    start = true;
                }
                break;
            }
            free(vm->cmd);
            break;
        }
        if (start) {
            break;
        }
    }
    
    for (; ; ) {
        if (get_vm_save_path(vm) != 0) {
            return;
        }
        if (gen_macos_vm(vm) != 0) {
            return;
        }
        sprintf(vm->tips, "%s %s &", vm->self_path, vm->vm);
        system(vm->tips);
        exit(0);
    }
}

static void create_linux_vm(NMLIVM *vm) {
    vm->system = NMLIVM_LINUX;
    vm->min_mem = 32llu * 1024llu * 1024llu;
    vm->min_disk = 512llu * 1024llu * 1024llu;
    
    for ( ; ; ) {
        sprintf(vm->tips,
                "1. select a linux install iso\n"
                "2. Back to upper menu\n%s> ", vm->who);
        vm->cmd = readline(vm->tips);
        if (vm->cmd == NULL || vm->cmd[1] != '\0' || (vm->cmd[0] != '1' && vm->cmd[0] != '2')) {
            if (vm->cmd != NULL) {
                free(vm->cmd);
            }
            printf("\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K");
            continue;
        }
        if (vm->cmd[0] == '1') {
            free(vm->cmd);
            sprintf(vm->tips, "Select a linux install iso\n%s> ", vm->who);
            if (get_path(vm, vm->rimg, sizeof(vm->rimg), false) != 0) {
                return;
            }
            if (setting_vm_cpu(vm) != 0) {
                continue;
            }
            if (get_vm_save_path(vm) != 0) {
                continue;
            }
            if (gen_linux_vm(vm) != 0) {
                continue;
            }
            sprintf(vm->tips, "%s %s %s &", vm->self_path, vm->vm, vm->rimg);
            system(vm->tips);
            exit(0);
        }
        free(vm->cmd);
        return;
    }
}

extern void start_menu(NMLIVM *vm) {
    if (vm == NULL) {
        NMLI_LOG("logic err, vm == NULL\n");
        exit(-1);
    }
    for (; ; ) {
#ifdef __arm64__
        sprintf(vm->tips,
                "1. open a vm\n"
                "2. create macos vm\n"
                "3. create linux vm\n"
                "4. boot macos vm in recovery\n%s> ", vm->who);
#else
        sprintf(vm->tips,
                "1. open a vm\n"
                "2. create linux vm\n%s> ", vm->who);
#endif
        
        vm->cmd = readline(vm->tips);
        if (vm->cmd == NULL || vm->cmd[1] != '\0' ||
#ifdef __arm64__
            (vm->cmd[0] != '1' && vm->cmd[0] != '2' && vm->cmd[0] != '3' && vm->cmd[0] != '4')) {
#else
            (vm->cmd[0] != '1' && vm->cmd[0] != '2')) {
#endif
                if (vm->cmd != NULL) {
                    free(vm->cmd);
                }
                printf("\033[A\033[K\033[A\033[K\033[A\033[K\033[A\033[K");
                continue;
        }
            
        if (vm->cmd[0] == '1') {
            free(vm->cmd);
            sprintf(vm->tips, "Select a NMLIVM directory\n%s> ", vm->who);
            if (get_path(vm, vm->vm, sizeof(vm->vm), false) != 0) {
                continue;;
            }
            sprintf(vm->tips, "attach a iso as dvd?\n%s> ", vm->who);
            if (get_path(vm, vm->rimg, sizeof(vm->rimg), false) != 0) {
                vm->rimg[0] = '\0';
            }
            sprintf(vm->tips, "%s %s %s &", vm->self_path, vm->vm, vm->rimg);
            system(vm->tips);
            exit(0);
        }
#ifdef __arm64__
        if (vm->cmd[0] == '2') {
            free(vm->cmd);
            create_macos_vm(vm);
            continue;
        }
            
        if (vm->cmd[0] == '3') {
            free(vm->cmd);
            create_linux_vm(vm);
            exit(0);
        }
            
        free(vm->cmd);
        sprintf(vm->tips, "Select a NMLIVM directory\n%s> ", vm->who);
        if (get_path(vm, vm->vm, sizeof(vm->vm), false) != 0) {
            continue;;
        }
        sprintf(vm->tips, "%s %s 1 &", vm->self_path, vm->vm);
        system(vm->tips);
        exit(0);
#else
        free(vm->cmd);
        create_linux_vm(vm);
#endif
    }
}


static int check_vm(const char *path, NMLIVM *vm) {
    NSURL *base = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
    NSURL *file = NMLI_VM_CFG(base);
    FILE *f = fopen(file.fileSystemRepresentation, "rb");
    if (f == NULL) {
        NMLI_LOG_VAR("%s virtual machine misses config!\n\n", path);
        return -1;
    }
        
    size_t len = ((char*)vm) + sizeof(NMLIVM) - (char*)&(vm->system);
    if (fread((char*)&(vm->system), sizeof(char), len, f) != len) {
        fclose(f);
        NMLI_LOG_VAR("%s virtual machine config err!\n\n", path);
        return -1;
    }
    fclose(f);
        
    if (vm->system == NMLIVM_MACOS) {
#ifdef __arm64__
        file = NMLI_VM_AUX(base);
        if (access(file.fileSystemRepresentation, W_OK | R_OK) == -1) {
            NMLI_LOG_VAR("%s virtual machine misses auxiliary storage!\n\n", path);
            return -2;
        }
#else
        NMLI_LOG_VAR("%s virtual machine only run on apple sillicon!\n\n", path);
        return -2;
#endif
            
        file = NMLI_VM_MACHID(base);
        if (access(file.fileSystemRepresentation, W_OK | R_OK) == -1) {
            NMLI_LOG_VAR("%s not a full nmlivm virtual machine!\n\n", path);
            return -3;
        }
        
        file = NMLI_VM_HARDWARE(base);
        if (access(file.fileSystemRepresentation, W_OK | R_OK) == -1) {
            NMLI_LOG_VAR("%s not a full nmlivm virtual machine!\n\n", path);
            return -4;
        }
    } else {
        file = NMLI_VM_EFI(base);
        if (access(file.fileSystemRepresentation, W_OK | R_OK) == -1) {
            NMLI_LOG_VAR("%s virtual machine misses efi storage!\n\n", path);
            return -2;
        }
            
        file = NMLI_VM_MACHID(base);
        if (access(file.fileSystemRepresentation, W_OK | R_OK) == -1) {
            NMLI_LOG_VAR("%s not a full nmlivm virtual machine!\n\n", path);
            return -3;
        }
    }
    
    file = NMLI_VM_DISK(base);
    if (access(file.fileSystemRepresentation, W_OK | R_OK) == -1) {
        NMLI_LOG_VAR("%s not a full nmlivm virtual machine!\n\n", path);
        return -5;
    }
    
    return 0;
}

extern void run_macos_vm(NMLIVM *vm, bool recovery);
extern void run_linux_vm(NMLIVM *vm);
extern void run_vm(int argc, const char* const *argv) {
    char path[512];
    nmli_absolute_path(argv[1], path);
    if (access(path, W_OK | R_OK) == -1) {
        printf("%s : write|read Permission denied!\n", argv[1]);
        exit(-1);
    }
    
    NMLIVM vm;
    memset(&vm, 0, sizeof(vm));
    if (check_vm(path, &vm) != 0) {
        exit(-2);
    }
    strcpy(vm.vm, path);
    
    bool recovery = false;
    if (argc >= 3 && argv[2][0] == '1' && argv[2][1] == '\0') {
        recovery = true;
    } else if (argc >= 3) {
        nmli_absolute_path(argv[2], path);
        if (access(path, W_OK | R_OK) == -1) {
            printf("%s : write|read Permission denied!\n", argv[2]);
            exit(-1);
        }
        strcpy(vm.rimg, path);
    }
    
    if (vm.system == NMLIVM_MACOS) {
        run_macos_vm(&vm, recovery);
    } else {
        run_linux_vm(&vm);
    }
}

