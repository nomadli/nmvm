//
//  NMLIGenLinuxVM.m
//  NMLIVM
//
//  Created by nomadli on 2022/7/23.
//

#import <Foundation/Foundation.h>
#import <Virtualization/Virtualization.h>
#import <termios.h>
#import "NMLIVM.h"


extern int gen_linux_vm(NMLIVM *vm) {
    NMLI_LOG_VAR("install linux from %s to %s\n", vm->rimg, vm->vm);
    @autoreleasepool {
        NSURL *base = [NSURL fileURLWithPath:[NSString stringWithUTF8String:vm->vm]];
        NSURL *disk = NMLI_VM_DISK(base);
        int fd = open(disk.fileSystemRepresentation, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR);
        if (fd == -1) {
            NMLI_LOG_VAR("Cannot create disk %s disk.\n", disk.fileSystemRepresentation);
            return -1;
        }
        if (ftruncate(fd, vm->disk) != 0) {
            NMLI_LOG_VAR("ftruncate() failed. %d %s\n", errno, strerror(errno));
            close(fd);
            return -2;
        }
        close(fd);
        
        VZVirtualMachineConfiguration *cfg = [[VZVirtualMachineConfiguration alloc] init];
        cfg.CPUCount = vm->cpu;
        cfg.memorySize = vm->mem;
        
        VZGenericPlatformConfiguration *pcfg = [[VZGenericPlatformConfiguration alloc] init];
        if (@available(macOS 13.0, *)) {
            pcfg.machineIdentifier = [[VZGenericMachineIdentifier alloc] init];
            [pcfg.machineIdentifier.dataRepresentation writeToURL:NMLI_VM_MACHID(base) atomically:YES];
        }
        cfg.platform = pcfg;
        
        NSError *err;
        if (@available(macOS 13.0, *)) {
            VZEFIVariableStore *efi = [[VZEFIVariableStore alloc] initCreatingVariableStoreAtURL:NMLI_VM_EFI(base)
                                                                                         options:VZEFIVariableStoreInitializationOptionAllowOverwrite
                                                                                           error:&err];
            if (efi == nil || err != nil) {
                NMLI_LOG_VAR("Failed to create the EFI variable store. %s\n", err.localizedDescription.UTF8String);
                return -3;
            }
            VZEFIBootLoader *bootloader = [[VZEFIBootLoader alloc] init];
            bootloader.variableStore = efi;
            cfg.bootLoader = bootloader;
        } else {
//            VZLinuxBootLoader *loader = [[VZLinuxBootLoader alloc] initWithKernelURL:base];
//            loader.initialRamdiskURL = base;
//            loader.commandLine = @"console=hvc0 rd.break=initqueue";
//            cfg.bootLoader = loader;
            NMLI_LOG_VAR("Macos 13.0 supper instll linux frome iso, nmvm not suppor linux kernel image file.\n");
            return -3;
        }
        
        VZDiskImageStorageDeviceAttachment *attach = [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:NMLI_VM_DISK(base) readOnly:YES error:&err];
        if (attach == nil || err != nil) {
            NMLI_LOG_VAR("Failed to create disk store. %s\n", err.localizedDescription.UTF8String);
            return -5;
        }
        NSMutableArray *storageDevices = [NSMutableArray arrayWithCapacity:2];
        [storageDevices addObject:[[VZVirtioBlockDeviceConfiguration alloc] initWithAttachment:attach]];
        if (@available(macOS 13.0, *)) {
            NSURL *iso = [[NSURL alloc] initFileURLWithPath:[NSString stringWithUTF8String:vm->rimg]];
            attach = [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:iso readOnly:YES error:&err];
            if (attach == nil || err != nil) {
                NMLI_LOG_VAR("Failed to load %s store. %s\n", vm->rimg, err.localizedDescription.UTF8String);
                return -4;
            }
            [storageDevices addObject:[[VZUSBMassStorageDeviceConfiguration alloc] initWithAttachment:attach]];
        }
        cfg.storageDevices = [storageDevices copy];
        
        if (vm->net == NMLIVM_NET_NAT) {
            VZVirtioNetworkDeviceConfiguration *net = [[VZVirtioNetworkDeviceConfiguration alloc] init];
            net.attachment = [[VZNATNetworkDeviceAttachment alloc] init];
            cfg.networkDevices = @[net];
        } else {
            NSMutableArray *array = [NSMutableArray arrayWithCapacity:VZBridgedNetworkInterface.networkInterfaces.count];
            for (NSUInteger i = 0; i < VZBridgedNetworkInterface.networkInterfaces.count; ++i) {
                VZVirtioNetworkDeviceConfiguration *net = [[VZVirtioNetworkDeviceConfiguration alloc] init];
                net.attachment = [[VZBridgedNetworkDeviceAttachment alloc] initWithInterface:VZBridgedNetworkInterface.networkInterfaces[i]];
                [array addObject:net];
            }
            cfg.networkDevices = [array copy];
        }
        
        if (@available(macOS 13.0, *)) {
            VZVirtioGraphicsDeviceConfiguration *graphics = [[VZVirtioGraphicsDeviceConfiguration alloc] init];
            graphics.scanouts = @[
                [[VZVirtioGraphicsScanoutConfiguration alloc] initWithWidthInPixels:vm->graphics_width_pixels
                                                                     heightInPixels:vm->graphics_height_pixels]
            ];
            cfg.graphicsDevices = @[graphics];
        }

        VZVirtioSoundDeviceConfiguration *audiocfg = [[VZVirtioSoundDeviceConfiguration alloc] init];
        VZVirtioSoundDeviceInputStreamConfiguration *audioInStream = [[VZVirtioSoundDeviceInputStreamConfiguration alloc] init];
        audioInStream.source = [[VZHostAudioInputStreamSource alloc] init];
        VZVirtioSoundDeviceOutputStreamConfiguration *audioOutStream = [[VZVirtioSoundDeviceOutputStreamConfiguration alloc] init];
        audioOutStream.sink = [[VZHostAudioOutputStreamSink alloc] init];
        audiocfg.streams = @[audioInStream, audioOutStream];
        cfg.audioDevices = @[audiocfg];
        
        cfg.keyboards = @[[[VZUSBKeyboardConfiguration alloc] init]];
        cfg.pointingDevices = @[[[VZUSBScreenCoordinatePointingDeviceConfiguration alloc] init]];
        
        if (@available(macOS 13.0, *)) {
            VZVirtioConsoleDeviceConfiguration *console = [[VZVirtioConsoleDeviceConfiguration alloc] init];
            VZVirtioConsolePortConfiguration *consolePort = [[VZVirtioConsolePortConfiguration alloc] init];
            consolePort.name = VZSpiceAgentPortAttachment.spiceAgentPortName;
            console.ports[0] = consolePort;
            cfg.consoleDevices = @[console];
        } else {
            NSFileHandle *input = NSFileHandle.fileHandleWithStandardInput;
            NSFileHandle *output = NSFileHandle.fileHandleWithStandardOutput;
            struct termios attr;
            tcgetattr(input.fileDescriptor, &attr);
            attr.c_iflag &= ~ICRNL;
            attr.c_lflag &= ~(ICANON | ECHO);
            tcsetattr(input.fileDescriptor, TCSANOW, &attr);
            VZFileHandleSerialPortAttachment *fattach = [[VZFileHandleSerialPortAttachment alloc] initWithFileHandleForReading:input fileHandleForWriting:output];
            VZVirtioConsoleDeviceSerialPortConfiguration *console = [[VZVirtioConsoleDeviceSerialPortConfiguration alloc] init];
            console.attachment = fattach;
            cfg.serialPorts = @[console];
        }
        
        if (![cfg validateWithError:&err]) {
            NMLI_LOG_VAR("No supported linux configuration. %s\n", err.localizedDescription.UTF8String);
            return -6;
        }
        
        base = NMLI_VM_CFG(base);
        FILE *f = fopen(base.fileSystemRepresentation, "wb");
        if (f == NULL) {
            NMLI_LOG_VAR("write config to %s err %d %s\n", base.fileSystemRepresentation, errno, strerror(errno));
            return -7;
        }
        size_t len = ((char*)vm) + sizeof(NMLIVM) - (char*)&(vm->system);
        if (fwrite((char*)&(vm->system), sizeof(char), len, f) != len) {
            NMLI_LOG_VAR("write config to %s err %d %s\n", base.fileSystemRepresentation, errno, strerror(errno));
            fclose(f);
            return -8;
        }
        fclose(f);
        return 0;
    }
}
