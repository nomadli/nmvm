//
//  NMLILinuxVM.m
//  NMLIVM
//
//  Created by nomadli on 2022/7/23.
//

#import <Cocoa/Cocoa.h>
#import <Virtualization/Virtualization.h>
#import <termios.h>
#import "NMLIVM.h"

NS_ASSUME_NONNULL_BEGIN

@interface NMLILinuxVM : NSObject<NSApplicationDelegate, VZVirtualMachineDelegate>
@property(nonatomic, strong) NSURL              *path;
@property(nonatomic, strong) NSURL              *iso;
@property(nonatomic, strong) NSWindow           *window;
@property(nonatomic, strong) VZVirtualMachine   *machine;
@end

NS_ASSUME_NONNULL_END

@implementation NMLILinuxVM

- (void)showAlert:(NSString*)msg abort:(BOOL)abort {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = msg;
    [alert addButtonWithTitle:@"ok"];
    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse modal) {
        //if (modal == NSAlertFirstButtonReturn) {}
        if (abort) {
            [NSApp performSelectorOnMainThread:@selector(terminate:) withObject:self waitUntilDone:NO];
        }
    }];
}

- (void)vmInit {
    NSURL *config = NMLI_VM_CFG(_path);
    FILE *f = fopen(config.fileSystemRepresentation, "rb");
    if (f == NULL) {
        [self showAlert:@"Virtual machine configuration not found." abort:YES];
    }
    
    NMLIVM vm;
    size_t len = ((char*)&vm) + sizeof(NMLIVM) - (char*)&(vm.system);
    if (fread((char*)&(vm.system), sizeof(char), len, f) != len) {
        fclose(f);
        [self showAlert:@"Virtual machine configuration read error." abort:YES];
    }
    fclose(f);
    
    VZVirtualMachineConfiguration *cfg = [[VZVirtualMachineConfiguration alloc] init];
    cfg.CPUCount = vm.cpu;
    cfg.memorySize = vm.mem;
    
    if (@available(macOS 13.0, *)) {
        VZGenericPlatformConfiguration *pcfg = [[VZGenericPlatformConfiguration alloc] init];
        NSData *machineIdentifierData = [[NSData alloc] initWithContentsOfURL:NMLI_VM_MACHID(_path)];
        if (machineIdentifierData == nil) {
            [self showAlert:@"Virtual machine identifier not found." abort:YES];
        }
        VZGenericMachineIdentifier *machineIdentifier = [[VZGenericMachineIdentifier alloc] initWithDataRepresentation:machineIdentifierData];
        if (machineIdentifier == nil) {
            [self showAlert:@"Failed to create Virtual machine identifier." abort:YES];
        }
        pcfg.machineIdentifier = machineIdentifier;
        cfg.platform = pcfg;
    }

    if (@available(macOS 13.0, *)) {
        VZEFIVariableStore *efi = [[VZEFIVariableStore alloc] initWithURL:NMLI_VM_EFI(_path)];
        if (efi == nil) {
            [self showAlert:@"Failed to load EFI store." abort:YES];
        }
        VZEFIBootLoader *bootloader = [[VZEFIBootLoader alloc] init];
        bootloader.variableStore = efi;
        cfg.bootLoader = bootloader;
    } else {
//      VZLinuxBootLoader *loader = [[VZLinuxBootLoader alloc] initWithKernelURL:base];
//      loader.initialRamdiskURL = base;
//      loader.commandLine = @"console=hvc0 rd.break=initqueue";
//      cfg.bootLoader = loader;
        [self showAlert:@"Macos 13.0 supper instll linux frome iso, nmvm not suppor linux kernel image file." abort:YES];
    }
    
    NSError *err;
    NSMutableArray *storageDevices = [NSMutableArray arrayWithCapacity:2];
    VZDiskImageStorageDeviceAttachment *attach = [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:NMLI_VM_DISK(_path) readOnly:NO error:&err];
    if (attach == nil || err != nil) {
        [self showAlert:err.localizedDescription abort:YES];
    }
    [storageDevices addObject:[[VZVirtioBlockDeviceConfiguration alloc] initWithAttachment:attach]];
    
    if (@available(macOS 13.0, *)) {
        if (_iso != nil) {
            attach = [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:_iso readOnly:YES error:&err];
            if (attach == nil || err != nil) {
                [self showAlert:err.localizedDescription abort:NO];
            } else {
                [storageDevices addObject:[[VZUSBMassStorageDeviceConfiguration alloc] initWithAttachment:attach]];
            }
        }
    }
    cfg.storageDevices = [storageDevices copy];
    
    if (vm.net == NMLIVM_NET_NAT) {
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
            [[VZVirtioGraphicsScanoutConfiguration alloc] initWithWidthInPixels:vm.graphics_width_pixels
                                                                 heightInPixels:vm.graphics_height_pixels]
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
        [self showAlert:err.localizedDescription abort:YES];
    }

    _machine = [[VZVirtualMachine alloc] initWithConfiguration:cfg];
    _machine.delegate = self;
}

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
    [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(10, 10, 1024, 768)
                                          styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|
              NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setOpaque:NO];
    [_window setTitle:_path.lastPathComponent.stringByDeletingPathExtension];
    
    if (![NSApp mainMenu]) {
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Window"], *mainMenu = [[NSMenu alloc] init];

        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
        [menu addItem:menuItem];

        menuItem = [[NSMenuItem alloc] initWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
        [menu addItem:menuItem];

        menuItem = [[NSMenuItem alloc] initWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"q"];
        [menu addItem:menuItem];

        [NSApp setMainMenu:mainMenu];
    }
    
    if (![[NSRunningApplication currentApplication] isActive]) {
        [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateAllWindows];
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    void CPSEnableForegroundOperation(ProcessSerialNumber* psn);
    ProcessSerialNumber pid;
    if (GetCurrentProcess(&pid) == noErr) {
        CPSEnableForegroundOperation(&pid);
    }
#pragma clang diagnostic pop
    
    __weak __typeof(self) wself = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong __typeof(wself) sself = wself;
        if (sself == nil) {
            return;
        }

        [sself vmInit];
        VZVirtualMachineView* view = [[VZVirtualMachineView alloc] init];
        view.capturesSystemKeys = YES;
        view.virtualMachine = sself.machine;
        [sself.window setContentView:view];
        [sself.window setInitialFirstResponder:view];
        [sself.window makeKeyAndOrderFront:view];
        [sself.machine startWithCompletionHandler:^(NSError *err) {
            if (err != nil) {
                [self showAlert:err.localizedDescription abort:YES];
            }
        }];
    });
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (void)guestDidStopVirtualMachine:(VZVirtualMachine*)virtualMachine {
    [self showAlert:@"Virtual machine guest stopped" abort:YES];
}

- (void)virtualMachine:(VZVirtualMachine*)virtualMachine didStopWithError:(NSError*)err {
    [self showAlert:err.localizedDescription abort:YES];
}

- (void)virtualMachine:(VZVirtualMachine*)virtualMachine networkDevice:(VZNetworkDevice*)networkDevice
attachmentWasDisconnectedWithError:(NSError*)err {
    [self showAlert:err.localizedDescription abort:NO];
}

@end

extern void run_linux_vm(NMLIVM *vm) {
    NMLILinuxVM *macos = [[NMLILinuxVM alloc] init];
    macos.path = [NSURL fileURLWithPath:[NSString stringWithUTF8String:vm->vm]];
    if (vm->rimg[0] != '\0') {
        macos.iso = [NSURL fileURLWithPath:[NSString stringWithUTF8String:vm->rimg]];
    }
    NSApplication *app = [NSApplication sharedApplication];
    app.activationPolicy = NSApplicationActivationPolicyRegular;//NSApplicationActivationPolicyAccessory
    app.delegate = macos;
    [app run];
}
