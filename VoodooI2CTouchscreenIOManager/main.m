//
//  VoodooI2CTouchscreenIOManager main.m
//  Polyfills the removed properties for tablet stylus events
//  Created by HY on 5/27/20.
//  Copyright © 2020 Bitruvian. All rights reserved.
//
//  Installation:
//      - Copy `VoodooI2CTouchscreenIOManager` executable to `/Applications/Utilities/VoodooI2CTouchscreenIOManager`
//      - Copy `com.alexandred.VoodooI2CTouchscreenIOManager.plist` to `~/Library/LaunchAgents` (or `/System/Library/LaunchAgents` for all users)
//      - `launchctl load /path/to/com.alexandred.VoodooI2CTouchscreenIOManager.plist` to test immediately
//      - `launchctl list | grep VoodooI2CTouchscreenIOManager` to confirm that it's running
//      Reference: https://www.launchd.info/
//  References:
//  Wacom Dev Guide: https://developer-docs.wacom.com/display/DevDocs/macOS+Developer%27s+Guide+to+the+Wacom+Tablet
//
//  What's missing:
//  TODO: add entering and leaving (if we have that info)
//  TODO: add twist support
//  TODO: add tilt support: I don't have a device with a stylus that reports tilt or twist, so I'm unsure how to format the values



#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#include <CoreGraphics/CGEvent.h>
#include <Cocoa/Cocoa.h>
#include <Carbon/Carbon.h>


#include "SharedData.h"
#include "./Wacom.h"

static io_service_t serviceObject;

//# https://developer-docs.wacom.com/display/DevDocs/macOS+Developer%27s+Guide+to+the+Wacom+Tablet
struct stylusSpec {
    Boolean isActive;
    double stylus_pressure; //# NOTE 0-1
    double barrel_pressure; //# NOTE 0-1
    //# TODO: twist? is this rotation?
    double tilt_x; //# NOTE 0-1 (doesn't seem to differentiate -1 and 1)
    double tilt_y; //# NOTE 0-1 (doesn't seem to differentiate -1 and 1)
};



static int cacheDevice() {
    kern_return_t    kernResult;
    mach_port_t        masterPort;
    io_iterator_t    iterator;
    CFDictionaryRef    classToMatch;
    
    
    // Returns the mach port used to initiate communication with IOKit.
    kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
    
    if (kernResult != kIOReturnSuccess)
    {
        printf("IOMasterPort returned %x\n", kernResult);
        return 0;
    }
    
    classToMatch = IOServiceMatching("VoodooI2CTouchscreenHIDEventDriver");
    
    if (classToMatch == NULL)
    {
        printf("IOServiceMatching returned a NULL dictionary.\n");
        return 0;
    }
    
    
    // This creates an io_iterator_t of all instances of our drivers class that exist in the IORegistry.
    kernResult = IOServiceGetMatchingServices(masterPort, classToMatch, &iterator);
    
    if (kernResult != kIOReturnSuccess)
    {
        printf("IOServiceGetMatchingServices returned %x\n", kernResult);
        return 0;
    }
    
    
    // Get the first item in the iterator.
    serviceObject = IOIteratorNext(iterator);
    
    // Release the io_iterator_t now that we're done with it.
    IOObjectRelease(iterator);
    
        
    if (!serviceObject)
    {
        printf("Couldn't find any matches.\n");
        return 0;
    }
    
    printf("Found device\n");
    return 1;
    
}

static struct stylusSpec getStylusSpec() {
    struct stylusSpec currentSpec = {false, 0,0,0,0};
    
    if (!serviceObject) {
        if (!cacheDevice()) {
            //# for some reason the device is not available, so we try to retrieve it again
            
            return currentSpec;
        }
    }
    

    //# REF: https://comp.sys.mac.programmer.help.narkive.com/bPLZZDuC/cfdictionarygetvalue-and-cfrelease
    //# get properties for VoodooI2CTouchscreenHIDEventDriver;
    CFMutableDictionaryRef regProperties;
    IORegistryEntryCreateCFProperties(serviceObject, &regProperties, kCFAllocatorDefault, kNilOptions);
       
      
    //# get stylus active
    CFBooleanRef isActive_CFBoolRef = (CFBooleanRef)CFDictionaryGetValue(regProperties, CFSTR(vdStylusActive));
    Boolean isActive = CFBooleanGetValue(isActive_CFBoolRef);
    
    currentSpec.isActive = isActive;
    
    if (!isActive) {
        CFRelease(regProperties);
        
        return currentSpec;
    }
    
    //CFShow(CFDictionaryGetValue(regProperties, CFSTR(vdStylusPressureKey)));
       
    //# get stylus pressure
    CFNumberRef stylusPressure_CFNumberRef = (CFNumberRef)CFDictionaryGetValue(regProperties, CFSTR(vdStylusPressureKey));
    int32_t stylusPressure;
    CFNumberGetValue(stylusPressure_CFNumberRef, kCFNumberSInt32Type, &stylusPressure);
    currentSpec.stylus_pressure = (stylusPressure * 1.0f)/65535;
    
    //# get barrel_pressure
    CFNumberRef barrelPressure_CFNumberRef = (CFNumberRef)CFDictionaryGetValue(regProperties, CFSTR(vdBarrelPressureKey));
    int32_t barrelPressure;
    CFNumberGetValue(barrelPressure_CFNumberRef, kCFNumberSInt32Type, &barrelPressure);
    currentSpec.barrel_pressure = (barrelPressure * 1.0f)/65535;
    
    printf("[Stylus Pressure: %f] [Barrel Pressure: %f]\n", currentSpec.stylus_pressure, currentSpec.barrel_pressure);
    
    CFRelease(regProperties);
    return currentSpec;
}


static uint16 DEVICE_ID = 0x6;
CGEventRef myCGEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef cgEvent, void *refcon) {
    //# Do some sanity check.
        
    if (type != kCGEventMouseMoved
        && type != kCGEventLeftMouseDown
        && type != kCGEventLeftMouseDragged
    ) return cgEvent;
    
    //printf("type: %x, [mv: %x, dn: %x, drg: %x]", type, kCGEventMouseMoved, kCGEventLeftMouseDown, kCGEventLeftMouseDragged);
    
    /*
    CGPoint location = CGEventGetLocation(event);
    double_t TabletPointPressure = CGEventGetDoubleValueField(event, kCGTabletEventPointPressure);
    double_t TabletTangentialPressure = CGEventGetDoubleValueField(event, kCGTabletEventTangentialPressure);
    double_t MousePressure = CGEventGetDoubleValueField(event, kCGMouseEventPressure);
    int64_t TabletEventPointZ = CGEventGetIntegerValueField(event, kCGTabletEventPointZ);
    */
    
    struct stylusSpec currentSpec = getStylusSpec();
    if (!currentSpec.isActive) {
        //# stylus isn't active so we exit early
        printf("Stylus isn't active, exiting early\n");
        return cgEvent;
    }
    
    printf("Stylus is active... continuing\n");
    
    
    if (type == kCGEventMouseMoved) {
        CGEventSetIntegerValueField(cgEvent, kCGMouseEventSubtype, kCGEventMouseSubtypeTabletProximity);
        //# set eventDeviceId
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventDeviceID, DEVICE_ID);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventPointerType, NX_TABLET_POINTER_PEN);
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventVendorPointerType, wcmGeneralStylus); 
        CGEventSetIntegerValueField(cgEvent, kCGTabletProximityEventCapabilityMask
                                    , NX_TABLET_CAPABILITY_DEVICEIDMASK | NX_TABLET_CAPABILITY_PRESSUREMASK |
                                    NX_TABLET_CAPABILITY_BUTTONSMASK | NX_TABLET_CAPABILITY_TANGENTIALPRESSUREMASK);

    } else {
        CGEventSetIntegerValueField(cgEvent, kCGMouseEventSubtype, kCGEventMouseSubtypeTabletPoint);
        CGEventSetIntegerValueField(cgEvent, kCGTabletEventDeviceID, DEVICE_ID);
        CGEventSetDoubleValueField(cgEvent, kCGMouseEventPressure, currentSpec.stylus_pressure);
            //# NOTE: don't need this but still setting it in case certain applications expect a mouseEventPressure
            //# and not tabletEventPointPressure
        CGEventSetDoubleValueField(cgEvent, kCGTabletEventPointPressure, currentSpec.stylus_pressure);
        CGEventSetDoubleValueField(cgEvent, kCGTabletEventTangentialPressure, currentSpec.barrel_pressure);
        
        //# TODO: NOTE: setting these values works, but my device does not support tilt so I cannot test
        //CGEventSetDoubleValueField(cgEvent, kCGTabletEventTiltX, 0.1);
        //CGEventSetDoubleValueField(cgEvent, kCGTabletEventTiltY, 0.1);

        //# TEST:
        //# https://developer.apple.com/documentation/coregraphics/cgeventtype?language=objc
        //# EVENT PROPERTIES
        //# https://developer.apple.com/documentation/coregraphics/cgeventfield?language=objc
        //CGEventSetType(event, kCGEventTabletPointer);
            //# try replacing kCGMouseEvent with kCGEventTabletPointer
            //# NOTE: doesn't work. mouse down and drag are not recognized
    }
    
    
    
    //# DEBUG: doublecheck that the carbon event has the expected properties;
    //# NOTE: setting the eventSubtype does set the proper `kEventParamTabletEventType`
    /*
    EventRef eventRef;
    CreateEventWithCGEvent(kCFAllocatorDefault, cgEvent, kEventAttributeNone, &eventRef);
    
    if (type == kCGEventMouseMoved) {
        TabletProximityRec proxRec;
        GetEventParameter(eventRef, kEventParamTabletProximityRec, typeTabletProximityRec, NULL, sizeof(TabletProximityRec),NULL,  &proxRec);
        printf("=== Retrieved tabletProximityRec [capability: %x] [pointerType: %x] [vendorPointerType: %x] [deviceID: %x] [enterProximity: %x] \n", proxRec.capabilityMask, proxRec.pointerType, proxRec.vendorPointerType, proxRec.deviceID, proxRec.enterProximity);
    }
    
    UInt32 gotEventType;
    GetEventParameter(eventRef, kEventParamTabletEventType, typeUInt32, NULL, sizeof(gotEventType), NULL, &gotEventType);
    
    printf("==== Retrieved eventType: %x\n", gotEventType);
    */
    
    
    //# We  must return the  event for it  to be useful.
    return cgEvent;
}


int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"VoodooI2CTouchscreenIOManager start");
        
        cacheDevice();
        

        CGEventMask eventMask = CGEventMaskBit(kCGEventMouseMoved) |
                    CGEventMaskBit(kCGEventLeftMouseDown) |
                    CGEventMaskBit(kCGEventLeftMouseDragged);
        
        CFMachPortRef eventTap = CGEventTapCreate( kCGSessionEventTap, kCGHeadInsertEventTap, 0, eventMask, myCGEventCallback, NULL);
        
        
        if  (!eventTap) {
            fprintf(stderr, "failed to create event tap\n");
            exit(1);
        }
        
        //# Create a run loop source.
        CFRunLoopSourceRef runLoopSource =  CFMachPortCreateRunLoopSource( kCFAllocatorDefault, eventTap,   0);
        
        //# Add to the current run loop.
        CFRunLoopAddSource(CFRunLoopGetCurrent(),   runLoopSource, kCFRunLoopCommonModes);
        
        //# Enable the event tap. CGEventTapEnable(eventTap,  true);
        
        //# Set it all running.
        CFRunLoopRun();
        
        
        exit(0);
    }
 
    return 0;
}
