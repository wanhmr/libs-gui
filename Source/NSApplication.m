/* 
   NSApplication.m

   The one and only application class

   Copyright (C) 1996 Free Software Foundation, Inc.

   Author:  Scott Christley <scottc@net-community.com>
   Date: 1996
   
   This file is part of the GNUstep GUI Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*/ 

#include <gnustep/gui/config.h>
#include <stdio.h>

#include <Foundation/NSArray.h>
#include <Foundation/NSNotification.h>
#include <Foundation/NSRunLoop.h>
#include <Foundation/NSAutoreleasePool.h>
#include <Foundation/NSTimer.h>

#ifndef LIB_FOUNDATION_LIBRARY
# include <Foundation/NSConnection.h>
#endif

#include <DPSClient/NSDPSContext.h>
#include <AppKit/NSApplication.h>
#include <AppKit/NSPopUpButton.h>
#include <AppKit/NSPanel.h>
#include <AppKit/NSEvent.h>
#include <AppKit/NSImage.h>
#include <AppKit/NSMenu.h>
#include <AppKit/NSMenuItem.h>
#include <AppKit/NSCursor.h>

//
// Class variables
//
static BOOL gnustep_gui_app_is_in_dealloc;
static NSEvent *gnustep_gui_null_event;
static id NSApp;

#define ASSIGN(a, b) \
  [b retain]; \
  [a release]; \
  a = b;

@implementation NSApplication

//
// Class methods
//
+ (void)initialize
{
  if (self == [NSApplication class])
    {
      NSDebugLog(@"Initialize NSApplication class\n");

      // Initial version
      [self setVersion:1];

      // So the application knows its within dealloc
      // and can prevent -release loops.
      gnustep_gui_app_is_in_dealloc = NO;
    }
}

+ (NSApplication *)sharedApplication
{
  // If the global application does not exist yet then create it
  if (!NSApp) {
    /* Don't combine the following two statements into one to avoid problems
       with some classes initialization code that tries to get the shared
       application. */
    NSApp = [self alloc];
    [NSApp init];
  }
  return NSApp;
}

//
// Instance methods
//

//
// Creating and initializing the NSApplication
//
- init
{
  [super init];

  NSDebugLog(@"Begin of NSApplication -init\n");

  // allocate the window list
  window_list = [NSMutableArray new];
  window_count = 1;

  //
  // Event handling setup
  //
  // allocate the event queue
  event_queue = [NSMutableArray new];
  // No current event
  current_event = nil;
  // The NULL event
  gnustep_gui_null_event = [NSEvent new];

  //
  // We are the end of the responder chain
  //
  [self setNextResponder:NULL];

  /* Set up the run loop object for the current thread */
  [self setupRunLoopInputSourcesForMode:NSDefaultRunLoopMode];
  [self setupRunLoopInputSourcesForMode:NSConnectionReplyMode];
  [self setupRunLoopInputSourcesForMode:NSModalPanelRunLoopMode];
  [self setupRunLoopInputSourcesForMode:NSEventTrackingRunLoopMode];

  return self;
}

- (void)finishLaunching
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

  // notify that we will finish the launching
  [nc postNotificationName: NSApplicationWillFinishLaunchingNotification
      object: self];

  // finish the launching

  // notify that the launching has finished
  [nc postNotificationName: NSApplicationDidFinishLaunchingNotification
      object: self];
}

- (void)dealloc
{
  NSDebugLog(@"Freeing NSApplication\n");

  // Let ourselves know we are within dealloc
  gnustep_gui_app_is_in_dealloc = YES;

  [window_list release];
  [event_queue release];
  [current_event release];
  [super dealloc];
}

//
// Changing the active application
//
- (void)activateIgnoringOtherApps:(BOOL)flag
{
  app_is_active = YES;
}

- (void)deactivate
{
  app_is_active = NO;
}

- (BOOL)isActive
{
  return app_is_active;
}

//
// Running the event loop
//
- (void)abortModal
{
}

- (NSModalSession)beginModalSessionForWindow:(NSWindow *)theWindow
{
  return NULL;
}

- (void)endModalSession:(NSModalSession)theSession
{
}

- (BOOL)isRunning
{
  return app_is_running;
}

- (void)run
{
  NSEvent *e;
  NSAutoreleasePool* pool;

  NSDebugLog(@"NSApplication -run\n");

  [self finishLaunching];

  app_should_quit = NO;
  app_is_running = YES;

  do
    {
      pool = [NSAutoreleasePool new];

      e = [self nextEventMatchingMask:NSAnyEventMask
		untilDate:[NSDate distantFuture]
		inMode:NSDefaultRunLoopMode dequeue:YES];
      if (e)
	[self sendEvent: e];
      else
	{
	  // Null event
	  // Call the back-end method to handle it
	  [self handleNullEvent];
	}
      [pool release];
    } while (!app_should_quit);
  app_is_running = YES;

  NSDebugLog(@"NSApplication end of run loop\n");
}

- (int)runModalForWindow:(NSWindow *)theWindow
{
  return 0;
}

- (int)runModalSession:(NSModalSession)theSession
{
  return 0;
}

- (void)sendEvent:(NSEvent *)theEvent
{
  // Don't send the null event
  if (theEvent == gnustep_gui_null_event)
    {
      NSDebugLog(@"Not sending the Null Event\n");
      return;
    }

  // What is the event type
  switch ([theEvent type])
    {

      //
      // NSApplication traps the periodic events
      //
    case NSPeriodic:
      break;

    case NSKeyDown:
      {
	NSDebugLog(@"send key down event\n");
	[[theEvent window] sendEvent:theEvent];
	break;
      }
    case NSKeyUp:
      {
	NSDebugLog(@"send key up event\n");
	[[theEvent window] sendEvent:theEvent];
	break;
      }
      //
      // All others get passed to the window
      //
    default:
      {
	NSWindow* window = [theEvent window];

	if (!theEvent) NSDebugLog(@"NSEvent is nil!\n");
	NSDebugLog(@"NSEvent type: %d", [theEvent type]);
	NSDebugLog(@"send event to window");
	NSDebugLog([window description]);
	if (!window)
	  NSDebugLog(@"no window");
	[window sendEvent:theEvent];
      }
    }
}

- (void)stop:sender
{
  app_is_running = NO;
}

- (void)stopModal
{
}

- (void)stopModalWithCode:(int)returnCode
{
}

//
// Getting, removing, and posting events
//
- (BOOL)event:(NSEvent *)theEvent matchMask:(unsigned int)mask
{
    NSEventType t;

    // If mask is for any event then return success
    if (mask == NSAnyEventMask)
        return YES;

    if (!theEvent) return NO;

    // Don't check the null event
    if (theEvent == gnustep_gui_null_event) return NO;

    t = [theEvent type];

    if ((t == NSLeftMouseDown) && (mask & NSLeftMouseDownMask))
        return YES;

    if ((t == NSLeftMouseUp) && (mask & NSLeftMouseUpMask))
        return YES;

    if ((t == NSRightMouseDown) && (mask & NSRightMouseDownMask))
        return YES;

    if ((t == NSRightMouseUp) && (mask & NSRightMouseUpMask))
        return YES;

    if ((t == NSMouseMoved) && (mask & NSMouseMovedMask))
        return YES;

    if ((t == NSMouseEntered) && (mask & NSMouseEnteredMask))
        return YES;

    if ((t == NSMouseExited) && (mask & NSMouseExitedMask))
        return YES;

    if ((t == NSLeftMouseDragged) && (mask & NSLeftMouseDraggedMask))
        return YES;

    if ((t == NSRightMouseDragged) && (mask & NSRightMouseDraggedMask))
        return YES;

    if ((t == NSKeyDown) && (mask & NSKeyDownMask))
        return YES;

    if ((t == NSKeyUp) && (mask & NSKeyUpMask))
        return YES;

    if ((t == NSFlagsChanged) && (mask & NSFlagsChangedMask))
        return YES;

    if ((t == NSPeriodic) && (mask & NSPeriodicMask))
        return YES;

    if ((t == NSCursorUpdate) && (mask & NSCursorUpdateMask))
        return YES;

    return NO;
}

- (void)setCurrentEvent:(NSEvent *)theEvent
{
    [theEvent retain];
    [current_event release];
    current_event = theEvent;
}

- (NSEvent *)currentEvent;
{
  return current_event;
}

- (void)discardEventsMatchingMask:(unsigned int)mask
		      beforeEvent:(NSEvent *)lastEvent
{
}

- (NSEvent*)_eventMatchingMask:(unsigned int)mask
{
  NSEvent* event;
  int i, count = [event_queue count];

  [self getNextEvent];

  /* Get an event from the events queue */
  if ((count = [event_queue count])) {
    for (i = 0; i < count; i++) {
      event = [event_queue objectAtIndex:i];
      if ([self event:event matchMask:mask]) {
	[event retain];
	[event_queue removeObjectAtIndex:i];
	[self setCurrentEvent:event];
	return [event autorelease];
      }
    }
  }

  return nil;
}

- (NSEvent *)nextEventMatchingMask:(unsigned int)mask
			 untilDate:(NSDate *)expiration
			    inMode:(NSString *)mode
			   dequeue:(BOOL)flag
{
  NSRunLoop* currentLoop = [NSRunLoop currentRunLoop];
  NSEventType type;
  NSEvent *event;
  BOOL done = NO;

  event = [self _eventMatchingMask:mask];
  if (event)
    done = YES;
  else if (!expiration)
    expiration = [NSDate distantFuture];

  // Not in queue so wait for next event
  while (!done) {
    NSDate *limitDate, *originalLimitDate;

    // flush any windows that need it
    [NSWindow _flushWindows];
    [self _flushCommunicationChannels];

    /* Retain the limitDate so it doesn't get release accidentally by
       runMode:beforeDate: if a timer which has this date as fire date gets
       released. */
    limitDate = [[currentLoop limitDateForMode:mode] retain];
    originalLimitDate = limitDate;

    event = [self _eventMatchingMask:mask];
    if (event) {
      [limitDate release];
      break;
    }

    if (limitDate)
      limitDate = [expiration earlierDate:limitDate];
    else
      limitDate = expiration;

    [currentLoop runMode:mode beforeDate:limitDate];
    [originalLimitDate release];

    event = [self _eventMatchingMask:mask];
    if (event)
      break;
  }

  // flush any windows that need it
  [NSWindow _flushWindows];
  [self _flushCommunicationChannels];

  type = [event type];

  // Unhide the cursor if necessary
  // but only if its not a null event
  if (event != gnustep_gui_null_event)
    {
      // Only if we should unhide when mouse moves
      if ([NSCursor isHiddenUntilMouseMoves])
	{
	  // Make sure the event is a mouse event before unhiding
	  if ((type == NSLeftMouseDown) || (type == NSLeftMouseUp)
	      || (type == NSRightMouseDown) || (type == NSRightMouseUp)
	      || (type == NSMouseMoved))
	    [NSCursor unhide];
	}
    }

  return event;
}

- (NSEvent *)peekEventMatchingMask:(unsigned int)mask
			 untilDate:(NSDate *)expiration
			    inMode:(NSString *)mode
			   dequeue:(BOOL)flag
{
  NSEvent *event = nil;

  event = [self _eventMatchingMask:mask];

  if (!event)
    {
      // Not in queue so peek for event
      event = [self peekNextEvent];

      event = [self _eventMatchingMask:mask];
    }

  // Unhide the cursor if necessary
  if (event && (event != gnustep_gui_null_event))
    {
      NSEventType type;

      // Only if we should unhide when mouse moves
      if ([NSCursor isHiddenUntilMouseMoves])
	{
	  // Make sure the event is a mouse event before unhiding
	  type = [event type];
	  if ((type == NSLeftMouseDown) || (type == NSLeftMouseUp)
	      || (type == NSRightMouseDown) || (type == NSRightMouseUp)
	      || (type == NSMouseMoved))
	    [NSCursor unhide];
	}
    }

  return event;
}

- (void)postEvent:(NSEvent *)event atStart:(BOOL)flag
{
  if (!flag)
    [event_queue addObject: event];
  else
    [event_queue insertObject: event atIndex: 0];
}

//
// Sending action messages
//
- (BOOL)sendAction:(SEL)aSelector
		to:aTarget
	      from:sender
{
  //
  // If the target responds to the selector
  // then have it perform it
  //
  if ([aTarget respondsToSelector:aSelector])
    {
      [aTarget performSelector:aSelector withObject:sender];
      return YES;
    }

  //
  // Otherwise traverse the responder chain
  //

  return NO;
}

- targetForAction:(SEL)aSelector
{
  return self;
}

- (BOOL)tryToPerform:(SEL)aSelector
		with:anObject
{
  return NO;
}

// Setting the application's icon
- (void)setApplicationIconImage:(NSImage *)anImage
{
    if (app_icon != nil)
    {
        [app_icon release];
    }

    app_icon = [anImage retain];
}

- (NSImage *)applicationIconImage
{
  return app_icon;
}

//
// Hiding all windows
//
- (void)hide:sender
{
  int i, count;
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

  // notify that we will hide
  [nc postNotificationName: NSApplicationWillHideNotification
      object: self];

  // TODO: hide the menu

  // Tell the windows to hide
  for (i = 0, count = [window_list count]; i < count; i++)
    [[window_list objectAtIndex:i] performHide:sender];

  app_is_hidden = YES;

  // notify that we did hide
  [nc postNotificationName: NSApplicationDidHideNotification
      object: self];
}

- (BOOL)isHidden
{
  return app_is_hidden;
}

- (void)unhide:sender
{
  int i, count;

  // Tell the windows to unhide
  for (i = 0, count = [window_list count]; i < count; i++)
    [[window_list objectAtIndex:i] performUnhide:sender];

  // TODO: unhide the menu

  app_is_hidden = NO;

  // Bring the key window to the front
  [[self keyWindow] makeKeyAndOrderFront:self];
}

- (void)unhideWithoutActivation
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

  // notify that we will unhide
  [nc postNotificationName: NSApplicationWillUnhideNotification
      object: self];

  [self unhide: self];

  // notify that we did unhide
  [nc postNotificationName: NSApplicationDidUnhideNotification
      object: self];
}

//
// Managing windows
//
- (NSWindow *)keyWindow
{
  int i, j;
  id w;

  j = [window_list count];
  for (i = 0;i < j; ++i)
    {
      w = [window_list objectAtIndex:i];
      if ([w isKeyWindow]) return w;
    }
  return nil;
}

- (NSWindow *)mainWindow
{
  int i, j;
  id w;

  j = [window_list count];
  for (i = 0;i < j; ++i)
    {
      w = [window_list objectAtIndex:i];
      if ([w isMainWindow]) return w;
    }
  return nil;
}

- (NSWindow *)makeWindowsPerform:(SEL)aSelector
			 inOrder:(BOOL)flag
{
  return nil;
}

- (void)miniaturizeAll:sender
{
  int i, count;

  for (i = 0, count = [window_list count]; i < count; i++)
    [[window_list objectAtIndex:i] miniaturize:sender];
}

- (void)preventWindowOrdering
{
}

- (void)setWindowsNeedUpdate:(BOOL)flag
{
}

- (void)updateWindows
{
  int i, count;
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

  // notify that we will update
  [nc postNotificationName: NSApplicationWillUpdateNotification
      object: self];

  for (i = 0, count = [window_list count]; i < count; i++)
    [[window_list objectAtIndex:i] update];

  // notify that we did update
  [nc postNotificationName: NSApplicationDidUpdateNotification
      object: self];
}

- (NSArray *)windows
{
  return window_list;
}

- (NSWindow *)windowWithWindowNumber:(int)windowNum
{
  int i, j;
  NSWindow *w;

  j = [window_list count];
  for (i = 0;i < j; ++i)
    {
      w = [window_list objectAtIndex:i];
      if ([w windowNumber] == windowNum) return w;
    }
  return nil;
}

//
// Showing Standard Panels
//
- (void)orderFrontColorPanel:sender
{
}

- (void)orderFrontDataLinkPanel:sender
{
}

- (void)orderFrontHelpPanel:sender
{
}

- (void)runPageLayout:sender
{
}

//
// Getting the main menu
//
- (NSMenu *)mainMenu
{
  return main_menu;
}

- (void)setMainMenu:(NSMenu *)aMenu
{
  int i, j;
  NSMenuItem *mc;
  NSArray *mi;

  // Release old and retain new
  [aMenu retain];
  [main_menu release];
  main_menu = aMenu;

  // Search for a menucell with the name Windows
  // This is the default windows menu
  mi = [main_menu itemArray];
  j = [mi count];
  windows_menu = nil;
  for (i = 0;i < j; ++i)
    {
      mc = [mi objectAtIndex:i];
      if ([[mc stringValue] compare:@"Windows"] == NSOrderedSame)
	{
	  // Found it!
	  windows_menu = mc;
	  break;
	}
    }
}

//
// Managing the Windows menu
//
- (void)addWindowsItem:aWindow
		 title:(NSString *)aString
	      filename:(BOOL)isFilename
{
  int i;

  // Not a subclass of window --forget it
  if (![aWindow isKindOfClass:[NSWindow class]])
    return;

  // Add to our window list, the array retains it
  i = [window_list count];
  [window_list addObject:aWindow];

  // set its window number
  [aWindow setWindowNumber:window_count];
  ++window_count;
	
  // If this was the first window then
  //   make it the main and key window
  if (i == 0)
    {
      [aWindow becomeMainWindow];
      [aWindow becomeKeyWindow];
    }
}

- (void)arrangeInFront:sender
{
}

- (void)changeWindowsItem:aWindow
		    title:(NSString *)aString
		 filename:(BOOL)isFilename
{
}

- (void)removeWindowsItem:aWindow
{
  // +++ This should be different
  if (aWindow == key_window)
	key_window = nil;
  if (aWindow == main_window)
	main_window = nil;

  // If we are within our dealloc then don't remove the window
  // Most likely dealloc is removing windows from our window list
  // and subsequently NSWindow is caling us to remove itself.
  if (gnustep_gui_app_is_in_dealloc)
      return;

  // Remove it from the window list
  [window_list removeObject: aWindow];

  return;
}

- (void)setWindowsMenu:aMenu
{
//  if (windows_menu)
//    [windows_menu setSubmenu:aMenu];
}

- (void)updateWindowsItem:aWindow
{
}

- (NSMenu *)windowsMenu
{
//  return [windows_menu submenu];
  return nil;
}

//
// Managing the Service menu
//
- (void)registerServicesMenuSendTypes:(NSArray *)sendTypes
			  returnTypes:(NSArray *)returnTypes
{
}

- (NSMenu *)servicesMenu
{
  return nil;
}

- (void)setServicesMenu:(NSMenu *)aMenu
{
}

- validRequestorForSendType:(NSString *)sendType
		 returnType:(NSString *)returnType
{
  return nil;
}

// Getting the display postscript context
- (NSDPSContext *)context
{
    return [NSDPSContext currentContext];
}

// Reporting an exception
- (void)reportException:(NSException *)anException
{}

//
// Terminating the application
//
- (void)terminate:sender
{
  if ([self applicationShouldTerminate:sender])
    app_should_quit = YES;
}

// Assigning a delegate
- delegate
{
  return delegate;
}

- (void)setDelegate:anObject
{
  NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];

  delegate = anObject;

#define SET_DELEGATE_NOTIFICATION(notif_name) \
  if ([delegate respondsToSelector:@selector(application##notif_name:)]) \
    [nc addObserver:delegate \
	  selector:@selector(application##notif_name:) \
	  name:NSApplication##notif_name##Notification object:self]

  SET_DELEGATE_NOTIFICATION(DidBecomeActive);
  SET_DELEGATE_NOTIFICATION(DidFinishLaunching);
  SET_DELEGATE_NOTIFICATION(DidHide);
  SET_DELEGATE_NOTIFICATION(DidResignActive);
  SET_DELEGATE_NOTIFICATION(DidUnhide);
  SET_DELEGATE_NOTIFICATION(DidUpdate);
  SET_DELEGATE_NOTIFICATION(WillBecomeActive);
  SET_DELEGATE_NOTIFICATION(WillFinishLaunching);
  SET_DELEGATE_NOTIFICATION(WillHide);
  SET_DELEGATE_NOTIFICATION(WillResignActive);
  SET_DELEGATE_NOTIFICATION(WillUnhide);
  SET_DELEGATE_NOTIFICATION(WillUpdate);
}

//
// Implemented by the delegate
//
- (BOOL)application:sender openFileWithoutUI:(NSString *)filename
{
  BOOL result = NO;

  if ([delegate respondsToSelector:@selector(application:openFileWithoutUI:)])
    result = [delegate application:sender openFileWithoutUI:filename];

  return result;
}
	
- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename
{
  BOOL result = NO;

  if ([delegate respondsToSelector:@selector(application:openFile:)])
    result = [delegate application:app openFile:filename];

  return result;
}

- (BOOL)application:(NSApplication *)app openTempFile:(NSString *)filename
{
  BOOL result = NO;

  if ([delegate respondsToSelector:@selector(application:openTempFile:)])
    result = [delegate application:app openTempFile:filename];

  return result;
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
  if ([delegate respondsToSelector:@selector(applicationDidBecomeActive:)])
    [delegate applicationDidBecomeActive:aNotification];
}
	
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
  if ([delegate respondsToSelector:@selector(applicationDidFinishLaunching:)])
    [delegate applicationDidFinishLaunching:aNotification];
}

- (void)applicationDidHide:(NSNotification *)aNotification
{
  if ([delegate respondsToSelector:@selector(applicationDidHide:)])
    [delegate applicationDidHide:aNotification];
}

- (void)applicationDidResignActive:(NSNotification *)aNotification
{
  if ([delegate respondsToSelector:@selector(applicationDidResignActive:)])
    [delegate applicationDidResignActive:aNotification];
}

- (void)applicationDidUnhide:(NSNotification *)aNotification
{
  if ([delegate respondsToSelector:@selector(applicationDidUnhide:)])
    [delegate applicationDidUnhide:aNotification];
}

- (void)applicationDidUpdate:(NSNotification *)aNotification
{
  if ([delegate respondsToSelector:@selector(applicationDidUpdate:)])
    [delegate applicationDidUpdate:aNotification];
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)app
{
  BOOL result = NO;

  if ([delegate respondsToSelector:@selector(applicationOpenUntitledFile:)])
    result = [delegate applicationOpenUntitledFile:app];

  return result;
}

- (BOOL)applicationShouldTerminate:sender
{
  BOOL result = YES;

  if ([delegate respondsToSelector:@selector(applicationShouldTerminate:)])
    result = [delegate applicationShouldTerminate:sender];

  return result;
}

- (void)applicationWillBecomeActive:(NSNotification *)aNotification
{
  if ([delegate respondsToSelector:@selector(applicationWillBecomeActive:)])
    [delegate applicationWillBecomeActive:aNotification];
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
  if ([delegate respondsToSelector:@selector(applicationWillFinishLaunching:)])
    [delegate applicationWillFinishLaunching:aNotification];
}

- (void)applicationWillHide:(NSNotification *)aNotification
{
  if ([delegate respondsToSelector:@selector(applicationWillHide:)])
    [delegate applicationWillHide:aNotification];
}

- (void)applicationWillResignActive:(NSNotification *)aNotification
{
  if ([delegate respondsToSelector:@selector(applicationWillResignActive:)])
    [delegate applicationWillResignActive:aNotification];
}

- (void)applicationWillUnhide:(NSNotification *)aNotification
{
  if ([delegate respondsToSelector:@selector(applicationWillUnhide:)])
    [delegate applicationWillUnhide:aNotification];
}

- (void)applicationWillUpdate:(NSNotification *)aNotification
{
  if ([delegate respondsToSelector:@selector(applicationWillUpdate:)])
    [delegate applicationWillUpdate:aNotification];
}

//
// NSCoding protocol
//
- (void)encodeWithCoder:aCoder
{
  [super encodeWithCoder:aCoder];

  [aCoder encodeObject: window_list];
  [aCoder encodeConditionalObject:key_window];
  [aCoder encodeConditionalObject:main_window];
  [aCoder encodeConditionalObject:delegate];
  [aCoder encodeObject:main_menu];
  [aCoder encodeConditionalObject:windows_menu];
}

- initWithCoder:aDecoder
{
  [super initWithCoder:aDecoder];

  window_list = [aDecoder decodeObject];
  key_window = [aDecoder decodeObject];
  main_window = [aDecoder decodeObject];
  delegate = [aDecoder decodeObject];
  main_menu = [aDecoder decodeObject];
  windows_menu = [aDecoder decodeObject];
  return self;
}

+ (void)setNullEvent:(NSEvent *)e
{
  ASSIGN(gnustep_gui_null_event, e);
}

+ (NSEvent *)getNullEvent;
{
  return gnustep_gui_null_event;
}

// Get next event
- (void)getNextEvent
{
  [event_queue addObject:gnustep_gui_null_event];
}

- (NSEvent *)peekNextEvent
{
  return gnustep_gui_null_event;
}

// handle a non-translated event
- (void)handleNullEvent
{}

- (void)_flushCommunicationChannels
{}

- (void)setupRunLoopInputSourcesForMode:(NSString*)mode
{}

@end
