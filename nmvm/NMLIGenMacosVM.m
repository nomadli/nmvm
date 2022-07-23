//
//  NMLIGenMacosVM.m
//  NMLIVM
//
//  Created by nomadli on 2022/7/21.
//

#import <Foundation/Foundation.h>
#import <Virtualization/Virtualization.h>
#import "NMLIVM.h"

#ifdef __arm64__

NS_ASSUME_NONNULL_BEGIN

@interface NMLIMacosInstallDelegate : NSObject<VZVirtualMachineDelegate>
@property(nonatomic, assign) int code;
@end

NS_ASSUME_NONNULL_END

@implementation NMLIMacosInstallDelegate

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"fractionCompleted"] && [object isKindOfClass:[NSProgress class]]) {
        NSProgress *prg = (NSProgress*)object;
        printf("\033[A\033[KInstallation progress: %f%%.\n", prg.fractionCompleted * 100);

        if (prg.finished) {
            [prg removeObserver:self forKeyPath:@"fractionCompleted"];
        }
    }
}

- (void)virtualMachine:(VZVirtualMachine*)vm didStopWithError:(NSError*)err
{
    NMLI_LOG_VAR("Virtual Machine did stop with error. %s\n", err.localizedDescription.UTF8String);
    _code = -1;
    CFRunLoopStop(CFRunLoopGetMain());
}

- (void)guestDidStopVirtualMachine:(VZVirtualMachine*)vm
{
    NMLI_LOG("Guest did stop virtual machine.\n");
    _code = 0;
    CFRunLoopStop(CFRunLoopGetMain());
}
@end

extern VZMacPlatformConfiguration* gen_vm_platform_cfg(NSURL *base, VZMacOSConfigurationRequirements *cfg) {
    VZMacPlatformConfiguration *ret = [[VZMacPlatformConfiguration alloc] init];
    VZMacHardwareModel *hardwareModel = nil;
    NSError *err;
    if (cfg != nil) {
        hardwareModel = cfg.hardwareModel;
    } else {
        NSMutableDictionary *dic = [NSMutableDictionary dictionary];
        [dic setObject:@(1) forKey:@"DataRepresentationVersion"];
        [dic setObject:@[@(12), @(0), @(0)] forKey:@"MinimumSupportedOS"];
        [dic setObject:@(2) forKey:@"PlatformVersion"];
        NSData *model = [NSPropertyListSerialization dataWithPropertyList:dic
                                                                   format:NSPropertyListBinaryFormat_v1_0
                                                                  options:0
                                                                    error:&err];
        if (model == nil || err != nil) {
            NMLI_LOG_VAR("Failed to gen default hardware model. %s\n", err.localizedDescription.UTF8String);
            return nil;
        }
        hardwareModel = [[VZMacHardwareModel alloc] initWithDataRepresentation:model];
    }
    ret.auxiliaryStorage =
    [[VZMacAuxiliaryStorage alloc] initCreatingStorageAtURL:NMLI_VM_AUX(base)
                                              hardwareModel:hardwareModel
                                                    options:VZMacAuxiliaryStorageInitializationOptionAllowOverwrite
                                                      error:&err];
    if (ret.auxiliaryStorage == nil) {
        NMLI_LOG_VAR("Failed to create auxiliary storage. %s\n", err.localizedDescription.UTF8String);
        return nil;
    }
    
    ret.hardwareModel = hardwareModel;
    ret.machineIdentifier = [[VZMacMachineIdentifier alloc] init];
    
    [ret.hardwareModel.dataRepresentation writeToURL:NMLI_VM_HARDWARE(base) atomically:YES];
    [ret.machineIdentifier.dataRepresentation writeToURL:NMLI_VM_MACHID(base) atomically:YES];
    
    return ret;
}

extern VZVirtualMachineConfiguration* gen_vm_config(NMLIVM *vm, VZMacOSConfigurationRequirements *cfg) {
    VZVirtualMachineConfiguration *ret = [[VZVirtualMachineConfiguration alloc] init];
    NSURL *base = [NSURL fileURLWithPath:[NSString stringWithUTF8String:vm->vm]];
    ret.platform = gen_vm_platform_cfg(base, cfg);
    if (ret.platform == nil) {
        return nil;
    }
    
    ret.CPUCount = vm->cpu;
    if (cfg != nil && ret.CPUCount < cfg.minimumSupportedCPUCount) {
        NMLI_LOG_VAR("CPUCount is not supported by the macOS configuration. cpu must >= %lu\n", cfg.minimumSupportedCPUCount);
        return nil;
    }
    if (cfg == nil && ret.CPUCount < NMLI_MACOS_MIN_CPU) {
        NMLI_LOG_VAR("CPUCount is not supported by the macOS configuration. cpu must >= %d\n", NMLI_MACOS_MIN_CPU);
        return nil;
    }
    
    ret.memorySize = vm->mem;
    if (cfg != nil && ret.memorySize < cfg.minimumSupportedMemorySize) {
        NMLI_LOG_VAR("memorySize is not supported by the macOS configuration. mem must > %lluG\n",
               cfg.minimumSupportedMemorySize / (1024ull * 1024ull * 1024ull));
        return nil;
    }
    if (cfg == nil && ret.memorySize < NMLI_MACOS_MIN_MEM) {
        NMLI_LOG_VAR("memorySize is not supported by the macOS configuration. mem must > %lluG\n",
                     NMLI_MACOS_MIN_MEM / (1024ull * 1024ull * 1024ull));
        return nil;
    }
    
    NSURL *disk = NMLI_VM_DISK(base);
    int fd = open(disk.fileSystemRepresentation, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR);
    if (fd == -1) {
        NMLI_LOG_VAR("Cannot create disk %s disk.\n", disk.fileSystemRepresentation);
        return nil;
    }
    if (ftruncate(fd, vm->disk) != 0) {
        NMLI_LOG_VAR("ftruncate() failed. %d %s\n", errno, strerror(errno));
        close(fd);
        return nil;
    }
    close(fd);
    
    ret.bootLoader = [[VZMacOSBootLoader alloc] init];
    
    VZMacGraphicsDeviceConfiguration *graphic = [[VZMacGraphicsDeviceConfiguration alloc] init];
    graphic.displays = @[
        [[VZMacGraphicsDisplayConfiguration alloc] initWithWidthInPixels:vm->graphics_width_pixels
                                                          heightInPixels:vm->graphics_height_pixels
                                                           pixelsPerInch:vm->graphics_pixels_per_inch]
    ];
    ret.graphicsDevices = @[graphic];
    
    NSError *err;
    VZDiskImageStorageDeviceAttachment *attach =
    [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:disk readOnly:NO error:&err];
    if (attach == nil) {
        NMLI_LOG_VAR("Failed to create VZDiskImageStorageDeviceAttachment. %s\n", err.localizedDescription.UTF8String);
        return nil;
    }
    ret.storageDevices = @[[[VZVirtioBlockDeviceConfiguration alloc] initWithAttachment:attach]];
    
    if (vm->net == NMLIVM_NET_NAT) {
        VZVirtioNetworkDeviceConfiguration *net = [[VZVirtioNetworkDeviceConfiguration alloc] init];
        net.attachment = [[VZNATNetworkDeviceAttachment alloc] init];
        ret.networkDevices = @[net];
    } else {
        NSMutableArray *array = [NSMutableArray arrayWithCapacity:VZBridgedNetworkInterface.networkInterfaces.count];
        for (NSUInteger i = 0; i < VZBridgedNetworkInterface.networkInterfaces.count; ++i) {
            VZVirtioNetworkDeviceConfiguration *net = [[VZVirtioNetworkDeviceConfiguration alloc] init];
            net.attachment = [[VZBridgedNetworkDeviceAttachment alloc] initWithInterface:VZBridgedNetworkInterface.networkInterfaces[i]];
            [array addObject:net];
        }
        ret.networkDevices = [array copy];
    }
    
    ret.pointingDevices = @[[[VZUSBScreenCoordinatePointingDeviceConfiguration alloc] init]];
    ret.keyboards = @[[[VZUSBKeyboardConfiguration alloc] init]];
    
    VZVirtioSoundDeviceConfiguration *audiocfg = [[VZVirtioSoundDeviceConfiguration alloc] init];
    VZVirtioSoundDeviceInputStreamConfiguration *audioInStream = [[VZVirtioSoundDeviceInputStreamConfiguration alloc] init];
    audioInStream.source = [[VZHostAudioInputStreamSource alloc] init];
    VZVirtioSoundDeviceOutputStreamConfiguration *audioOutStream = [[VZVirtioSoundDeviceOutputStreamConfiguration alloc] init];
    audioOutStream.sink = [[VZHostAudioOutputStreamSink alloc] init];
    audiocfg.streams = @[audioInStream, audioOutStream];
    ret.audioDevices = @[audiocfg];
    
    if (![ret validateWithError:&err]) {
        NMLI_LOG_VAR("No supported Mac configuration. %s\n", err.localizedDescription.UTF8String);
        return nil;
    }
    
    disk = NMLI_VM_CFG(base);
    FILE *f = fopen(disk.fileSystemRepresentation, "wb");
    if (f == NULL) {
        NMLI_LOG_VAR("write config to %s err %d %s\n", disk.fileSystemRepresentation, errno, strerror(errno));
        return nil;
    }
    size_t len = ((char*)vm) + sizeof(NMLIVM) - (char*)&(vm->system);
    if (fwrite((char*)&(vm->system), sizeof(char), len, f) != len) {
        NMLI_LOG_VAR("write config to %s err %d %s\n", disk.fileSystemRepresentation, errno, strerror(errno));
        fclose(f);
        return nil;
    }
    fclose(f);
    
    return ret;
}

extern int gen_macos_vm(NMLIVM *vm) {
    NMLI_LOG_VAR("install macos from %s to %s\n", vm->rimg, vm->vm);
    @autoreleasepool {
        if (vm->is_macos_restore == 0) {
            return gen_vm_config(vm, nil) != nil ? 0 : -1;
        }
        
        __block NMLIMacosInstallDelegate *delegate = [[NMLIMacosInstallDelegate alloc] init];
        NSURL *rimg = [NSURL fileURLWithPath:[NSString stringWithUTF8String:vm->rimg]];
        [VZMacOSRestoreImage loadFileURL:rimg completionHandler:^(VZMacOSRestoreImage *img, NSError *err) {
            if (err != nil) {
                NMLI_LOG_VAR("install err %s\n", err.localizedDescription.UTF8String);
                delegate.code = -1;
                CFRunLoopStop(CFRunLoopGetMain());
                return;
            }
            
            VZMacOSConfigurationRequirements *cfg = img.mostFeaturefulSupportedConfiguration;
            if (cfg == nil || !cfg.hardwareModel.supported) {
                NMLI_LOG("ipsw no have supported Mac configuration! use default configuration.\n");
            }
            VZVirtualMachineConfiguration *vcfg = gen_vm_config(vm, cfg);
            if (vcfg == nil) {
                delegate.code = -3;
                CFRunLoopStop(CFRunLoopGetMain());
                return;
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                VZVirtualMachine *vm_mac = [[VZVirtualMachine alloc] initWithConfiguration:vcfg];
                vm_mac.delegate = delegate;
                VZMacOSInstaller *installer = [[VZMacOSInstaller alloc] initWithVirtualMachine:vm_mac restoreImageURL:rimg];
                printf("Starting installation.\n");
                [installer installWithCompletionHandler:^(NSError *err) {
                    if (err != nil) {
                        NMLI_LOG_VAR("install err %s\n", err.localizedDescription.UTF8String);
                        delegate.code = -4;
                    } else {
                        NMLI_LOG("Installation succeeded.\n");
                        delegate.code = 0;
                    }
                    CFRunLoopStop(CFRunLoopGetMain());
                    return;
                }];

                printf("Installation progress: %f%%.\n", 0.0);
                [installer.progress addObserver:delegate forKeyPath:@"fractionCompleted" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:nil];
            });
        }];
        
        CFRunLoopRun();
        return delegate.code;
    }
}

#else

extern int gen_macos_vm(NMLIVM *vm) {return 0;}

#endif//__arm64__
