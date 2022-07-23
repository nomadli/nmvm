//
//  NMLIRunVM.m
//  NMLIVM
//
//  Created by nomadli on 2022/7/23.
//

#import <Cocoa/Cocoa.h>
#import <Virtualization/Virtualization.h>
#import "NMLIVM.h"

#ifdef __arm64__

NS_ASSUME_NONNULL_BEGIN

@interface NMLIMacosVM : NSObject<NSApplicationDelegate, VZVirtualMachineDelegate>
@property(nonatomic, strong) NSURL              *path;
@property(nonatomic, strong) NSURL              *iso;
@property(nonatomic, assign) BOOL               recovery;
@property(nonatomic, strong) NSWindow           *window;
@property(nonatomic, strong) VZVirtualMachine   *machine;
@end

NS_ASSUME_NONNULL_END

@implementation NMLIMacosVM

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
    
    
    VZMacPlatformConfiguration *pcfg = [[VZMacPlatformConfiguration alloc] init];
    
    //machineIdentifier
    NSData *machineIdentifierData = [[NSData alloc] initWithContentsOfURL:NMLI_VM_MACHID(_path)];
    if (!machineIdentifierData) {
        [self showAlert:@"Virtual machine identifier not found." abort:YES];
    }
    VZMacMachineIdentifier *machineIdentifier = [[VZMacMachineIdentifier alloc] initWithDataRepresentation:machineIdentifierData];
    if (!machineIdentifier) {
        [self showAlert:@"Failed to create Virtual machine identifier." abort:YES];
    }
    pcfg.machineIdentifier = machineIdentifier;
    
    //macHardwareModel
    NSData *hardwareModelData = [[NSData alloc] initWithContentsOfURL:NMLI_VM_HARDWARE(_path)];
    if (hardwareModelData == nil) {
        [self showAlert:@"Virtual machine hardware mode info not found" abort:YES];
    }
    VZMacHardwareModel *hardwareModel = [[VZMacHardwareModel alloc] initWithDataRepresentation:hardwareModelData];
    if (hardwareModel == nil) {
        [self showAlert:@"Virtual machine hardware mode info error" abort:YES];
    }
    if (!hardwareModel.supported) {
        [self showAlert:@"The hardware model isn't supported on the current host" abort:YES];
    }
    pcfg.hardwareModel = hardwareModel;
    
    //auxiliaryStorage
    VZMacAuxiliaryStorage *auxiliaryDisk = [[VZMacAuxiliaryStorage alloc] initWithContentsOfURL:NMLI_VM_AUX(_path)];
    if (auxiliaryDisk == nil) {
        [self showAlert:@"Virtual machine auxiliary img not found" abort:YES];
    }
    pcfg.auxiliaryStorage = auxiliaryDisk;

    
    VZVirtualMachineConfiguration *cfg = [[VZVirtualMachineConfiguration alloc] init];
    cfg.platform = pcfg;
    
    cfg.CPUCount = vm.cpu;
    cfg.memorySize = vm.mem;
    cfg.bootLoader = [[VZMacOSBootLoader alloc] init];
    
    VZMacGraphicsDeviceConfiguration *graphic = [[VZMacGraphicsDeviceConfiguration alloc] init];
    graphic.displays = @[
        [[VZMacGraphicsDisplayConfiguration alloc] initWithWidthInPixels:vm.graphics_width_pixels
                                                          heightInPixels:vm.graphics_height_pixels
                                                           pixelsPerInch:vm.graphics_pixels_per_inch]
    ];
    cfg.graphicsDevices = @[graphic];
    
    NSError *err;
    VZDiskImageStorageDeviceAttachment *attach =
    [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:NMLI_VM_DISK(_path) readOnly:NO error:&err];
    if (attach == nil) {
        [self showAlert:@"Virtual machine disk not found" abort:YES];
    }
    NSMutableArray *storages = [NSMutableArray arrayWithCapacity:2];
    [storages addObject: [[VZVirtioBlockDeviceConfiguration alloc] initWithAttachment:attach]];
    if (@available(macOS 13.0, *)) {
        for (; _iso != nil; ) {
            attach = [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:_iso readOnly:YES error:&err];
            if (attach == nil || err != nil) {
                NMLI_LOG_VAR("Failed to load %s store. %s\n", _iso.path.UTF8String, err.localizedDescription.UTF8String);
                break;
            }
            [storages addObject: [[VZUSBMassStorageDeviceConfiguration alloc] initWithAttachment:attach]];
        }
    }
    cfg.storageDevices = [storages copy];
    
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
    
    cfg.pointingDevices = @[[[VZUSBScreenCoordinatePointingDeviceConfiguration alloc] init]];
    cfg.keyboards = @[[[VZUSBKeyboardConfiguration alloc] init]];
    
    VZVirtioSoundDeviceConfiguration *audiocfg = [[VZVirtioSoundDeviceConfiguration alloc] init];
    VZVirtioSoundDeviceInputStreamConfiguration *audioInStream = [[VZVirtioSoundDeviceInputStreamConfiguration alloc] init];
    audioInStream.source = [[VZHostAudioInputStreamSource alloc] init];
    VZVirtioSoundDeviceOutputStreamConfiguration *audioOutStream = [[VZVirtioSoundDeviceOutputStreamConfiguration alloc] init];
    audioOutStream.sink = [[VZHostAudioOutputStreamSink alloc] init];
    audiocfg.streams = @[audioInStream, audioOutStream];
    cfg.audioDevices = @[audiocfg];
    
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
        if (@available(macOS 13.0, *)) {
            VZMacOSVirtualMachineStartOptions *option = [[VZMacOSVirtualMachineStartOptions alloc] init];
            option.startUpFromMacOSRecovery = NO;
            if (sself.recovery) {
                option.startUpFromMacOSRecovery = YES;
            }
            [sself.machine startWithOptions:option completionHandler:^(NSError *err) {
                if (err != nil) {
                    [self showAlert:err.localizedDescription abort:YES];
                }
            }];
        } else {
            if (sself.recovery) {
                [self showAlert:@"Only Macos Version >= 13.0 super boot to recovery!" abort:NO];
            }
            [sself.machine startWithCompletionHandler:^(NSError *err) {
                if (err != nil) {
                    [self showAlert:err.localizedDescription abort:YES];
                }
            }];
        }
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

extern void run_macos_vm(NMLIVM *vm, bool recovery) {
    NMLIMacosVM *macos = [[NMLIMacosVM alloc] init];
    macos.path = [NSURL fileURLWithPath:[NSString stringWithUTF8String:vm->vm]];
    if (vm->rimg[0] != '\0') {
        macos.iso = [NSURL fileURLWithPath:[NSString stringWithUTF8String:vm->rimg]];
    }
    macos.recovery = recovery;
    NSApplication *app = [NSApplication sharedApplication];
    app.activationPolicy = NSApplicationActivationPolicyRegular;//NSApplicationActivationPolicyAccessory
    app.delegate = macos;
    [app run];
}

#else

extern void run_macos_vm(const char *path) {}

#endif//__arm64__
